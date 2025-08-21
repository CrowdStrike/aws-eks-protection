#!/bin/bash

# Configuration variables
TIMEOUT=${TIMEOUT:-300}
AWS_REGION=${AWS_REGION:-""}
EKS_CLUSTER_NAME=${EKS_CLUSTER_NAME:-""}

# CrowdStrike Falcon Operator configuration
FALCON_OPERATOR_NAMESPACE=${FALCON_OPERATOR_NAMESPACE:-"falcon-operator"}
FALCON_CLIENT_ID=${FALCON_CLIENT_ID:-""}
FALCON_CLIENT_SECRET=${FALCON_CLIENT_SECRET:-""}
FALCON_CLOUD_REGION=${FALCON_CLOUD_REGION:-"autodiscover"}
FALCON_CID=${FALCON_CID:-""}
DEPLOY_FALCON_OPERATOR=${DEPLOY_FALCON_OPERATOR:-"true"}
DEPLOY_FALCON_RESOURCES=${DEPLOY_FALCON_RESOURCES:-"true"}
FALCON_OPERATOR_VERSION=${FALCON_OPERATOR_VERSION:-"latest"}

# FalconDeployment component configuration
DEPLOY_FALCON_ADMISSION=${DEPLOY_FALCON_ADMISSION:-"true"}
DEPLOY_FALCON_IMAGE_ANALYZER=${DEPLOY_FALCON_IMAGE_ANALYZER:-"true"}
DEPLOY_FALCON_NODE_SENSOR=${DEPLOY_FALCON_NODE_SENSOR:-"true"}
DEPLOY_FALCON_CONTAINER=${DEPLOY_FALCON_CONTAINER:-"true"}

# Parameter Store configuration
FALCON_DEPLOYMENT_PARAMETER=${FALCON_DEPLOYMENT_PARAMETER:-"/crowdstrike/falcon-eks-protection/falcon-deployment-manifest"}

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Enhanced logging function with levels
log() {
    local level=$1
    local message=$2
    local color=""
    
    case $level in
        "ERROR") color=$RED ;;
        "WARNING") color=$YELLOW ;;
        "SUCCESS") color=$GREEN ;;
        *) color=$NC ;;
    esac
    
    echo -e "${color}[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message${NC}"
}

# Error handling function
handle_error() {
    local exit_code=$1
    local line_number=$2
    log "ERROR" "Script failed at line $line_number with exit code $exit_code"
    cleanup
    exit $exit_code
}

# Cleanup function
cleanup() {
    log "INFO" "Performing cleanup..."
    # Add cleanup tasks here
}

# Set error handling after functions are defined
set -eo pipefail
trap 'handle_error $? $LINENO' ERR

# Function to check AWS CLI and configure EKS
configure_eks() {
    if ! command -v aws &> /dev/null; then
        log "ERROR" "AWS CLI is not installed"
        exit 1
    fi

    if [ -z "$EKS_CLUSTER_NAME" ]; then
        log "ERROR" "EKS_CLUSTER_NAME is not set"
        exit 1
    fi

    log "INFO" "Updating kubeconfig for EKS cluster: $EKS_CLUSTER_NAME"
    aws eks update-kubeconfig --name "$EKS_CLUSTER_NAME" --region "$AWS_REGION"
}

# Function to check if kubectl is available
check_kubectl() {
    if ! command -v kubectl &> /dev/null; then
        log "ERROR" "kubectl is not installed"
        exit 1
    fi
}

# Function to check cluster connectivity
check_cluster_connection() {
    if ! kubectl cluster-info &> /dev/null; then
        log "ERROR" "Unable to connect to Kubernetes cluster"
        exit 1
    fi
    log "SUCCESS" "Connected to Kubernetes cluster"
}

# Function to validate CrowdStrike API credentials
validate_falcon_credentials() {
    log "INFO" "Validating CrowdStrike Falcon API credentials"
    
    if [[ "$DEPLOY_FALCON_OPERATOR" != "true" ]]; then
        log "INFO" "Falcon Operator deployment disabled, skipping credential validation"
        return 0
    fi
    
    if [[ -z "$FALCON_CLIENT_ID" || -z "$FALCON_CLIENT_SECRET" ]]; then
        log "ERROR" "CrowdStrike API credentials not provided"
        log "ERROR" "Please set FALCON_CLIENT_ID and FALCON_CLIENT_SECRET environment variables"
        log "ERROR" "API Key must have permissions: 'Falcon Images Download: Read' and 'Sensor Download: Read'"
        exit 1
    fi
    
    log "SUCCESS" "Falcon API credentials provided"
}

# Function to check if Falcon Operator is installed
check_falcon_operator_installed() {
    if kubectl get namespace "$FALCON_OPERATOR_NAMESPACE" &> /dev/null && \
       kubectl get deployment -n "$FALCON_OPERATOR_NAMESPACE" falcon-operator-controller-manager &> /dev/null; then
        return 0
    else
        return 1
    fi
}

# Function to install CrowdStrike Falcon Operator
install_falcon_operator() {
    log "INFO" "Installing CrowdStrike Falcon Operator"
    
    if [[ "$DEPLOY_FALCON_OPERATOR" != "true" ]]; then
        log "INFO" "Falcon Operator deployment disabled, skipping installation"
        return 0
    fi
    
    # Check if already installed
    if check_falcon_operator_installed; then
        log "SUCCESS" "Falcon Operator is already installed"
        return 0
    fi
    
    # Install the operator
    local operator_url="https://github.com/crowdstrike/falcon-operator/releases/${FALCON_OPERATOR_VERSION}/download/falcon-operator.yaml"
    
    log "INFO" "Applying Falcon Operator manifest from: $operator_url"
    kubectl apply -f "$operator_url"
    
    # Wait for operator to be ready
    log "INFO" "Waiting for Falcon Operator to be ready..."
    kubectl wait --for=condition=available \
        --timeout=300s \
        deployment/falcon-operator-controller-manager \
        -n "$FALCON_OPERATOR_NAMESPACE"
    
    if [ $? -eq 0 ]; then
        log "SUCCESS" "Falcon Operator installed and ready"
    else
        log "ERROR" "Falcon Operator failed to become ready"
        kubectl describe deployment falcon-operator-controller-manager -n "$FALCON_OPERATOR_NAMESPACE"
        exit 1
    fi
}

# Function to create Kubernetes secret for Falcon API credentials
create_falcon_secret() {
    log "INFO" "Creating Falcon API credentials secret"
    
    # Check if secret already exists
    if kubectl get secret falcon-api-secret -n default &> /dev/null; then
        log "INFO" "Falcon API secret already exists, updating..."
        kubectl delete secret falcon-api-secret -n default
    fi
    
    # Create secret with the correct keys expected by FalconDeployment
    kubectl create secret generic falcon-api-secret \
        --from-literal=falcon-client-id="$FALCON_CLIENT_ID" \
        --from-literal=falcon-client-secret="$FALCON_CLIENT_SECRET" \
        -n default
    
    if [[ -n "$FALCON_CID" ]]; then
        # Add CID if provided
        kubectl patch secret falcon-api-secret -n default \
            --patch='{"data":{"falcon-cid":"'"$(echo -n "$FALCON_CID" | base64)"'"}}'
    fi
    
    if [ $? -eq 0 ]; then
        log "SUCCESS" "Falcon API secret created successfully"
    else
        log "ERROR" "Failed to create Falcon API secret"
        exit 1
    fi
}

# Function to create FalconDeployment resource
create_falcon_deployment() {
    log "INFO" "Creating FalconDeployment resource"
    
    if [[ "$DEPLOY_FALCON_RESOURCES" != "true" ]]; then
        log "INFO" "Falcon resource deployment disabled, skipping FalconDeployment"
        return 0
    fi
    
    # Create API credentials secret
    create_falcon_secret
    
    # Get FalconDeployment Manifest from Parameter Store
    log "INFO" "Retrieving FalconDeployment manifest from Parameter Store: $FALCON_DEPLOYMENT_PARAMETER"
    
    local manifest_template
    manifest_template=$(aws ssm get-parameter \
        --name "$FALCON_DEPLOYMENT_PARAMETER" \
        --region "$AWS_REGION" \
        --query 'Parameter.Value' \
        --output text)
    
    if [[ -z "$manifest_template" ]]; then
        log "ERROR" "Failed to retrieve FalconDeployment manifest from Parameter Store"
        exit 1
    fi
    
    # Create temporary manifest file with substitutions
    local manifest_file="/tmp/falcon-deployment-$(date +%s).yaml"
    
    # Replace placeholder values in the manifest
    echo "$manifest_template" | \
        sed "s/FINAL_DEPLOY_FALCON_ADMISSION/$DEPLOY_FALCON_ADMISSION/g" | \
        sed "s/FINAL_DEPLOY_FALCON_IMAGE_ANALYZER/$DEPLOY_FALCON_IMAGE_ANALYZER/g" > "$manifest_file"
    
    if [ ! -f "$manifest_file" ]; then
        log "ERROR" "Failed to create FalconDeployment manifest file"
        exit 1
    fi
    
    log "SUCCESS" "FalconDeployment manifest prepared successfully"
    log "INFO" "Manifest file: $manifest_file"

    # Show the manifest content for debugging
    log "INFO" "FalconDeployment manifest content:"
    cat "$manifest_file"

    # Apply the FalconDeployment
    log "INFO" "Applying FalconDeployment manifest"
    log "INFO" "Components: Node Sensor = $DEPLOY_FALCON_NODE_SENSOR, Container Sensor = $DEPLOY_FALCON_CONTAINER, Admission Controller = $DEPLOY_FALCON_ADMISSION, Image Analyzer = $DEPLOY_FALCON_IMAGE_ANALYZER"
    
    kubectl apply -f "$manifest_file"
    
    if [ $? -eq 0 ]; then
        log "SUCCESS" "FalconDeployment applied successfully"
        
        # Wait for deployment to be ready
        log "INFO" "Waiting for FalconDeployment to be processed..."
        sleep 10
        
        # Check status
        kubectl get falcondeployment falcon-deployment -n default -o wide
        
        log "SUCCESS" "FalconDeployment created successfully"
        
        # Show created resources
        log "INFO" "Checking created Falcon resources..."
        if [[ "$DEPLOY_FALCON_NODE_SENSOR" == "true" ]]; then
            kubectl get falconnodesensor -A 2>/dev/null || log "WARNING" "FalconNodeSensor not yet created"
        fi
        if [[ "$DEPLOY_FALCON_CONTAINER" == "true" ]]; then
            kubectl get falconcontainer -A 2>/dev/null || log "WARNING" "FalconContainer not yet created"
        fi
        if [[ "$DEPLOY_FALCON_ADMISSION" == "true" ]]; then
            kubectl get falconadmission -A 2>/dev/null || log "WARNING" "FalconAdmission not yet created"
        fi
        if [[ "$DEPLOY_FALCON_IMAGE_ANALYZER" == "true" ]]; then
            kubectl get falconimageanalyzer -A 2>/dev/null || log "WARNING" "FalconImageAnalyzer not yet created"
        fi
        
    else
        log "ERROR" "Failed to apply FalconDeployment"
        cat "$manifest_file"
        exit 1
    fi
    
    # Clean up manifest file
    rm -f "$manifest_file"
}

# Main execution
main() {
    log "INFO" "Starting EKS cluster setup and CrowdStrike Falcon Operator deployment"
    
    # Configure EKS
    configure_eks
    
    # Continue with existing checks
    check_kubectl
    check_cluster_connection
    
    # CrowdStrike Falcon Operator Installation
    log "INFO" "=== CrowdStrike Falcon Operator Setup ==="
    validate_falcon_credentials
    install_falcon_operator
    
    # Deploy Falcon resources
    log "INFO" "=== CrowdStrike Falcon Resources Deployment ==="
    create_falcon_deployment
    
    log "SUCCESS" "CrowdStrike Falcon Operator and resources deployment completed successfully"
    log "INFO" "=== Deployment Summary ==="
    log "INFO" "- FalconNodeSensor: $DEPLOY_FALCON_NODE_SENSOR"
    log "INFO" "- FalconContainer: $DEPLOY_FALCON_CONTAINER"
    log "INFO" "- FalconAdmission: $DEPLOY_FALCON_ADMISSION"
    log "INFO" "- FalconImageAnalyzer: $DEPLOY_FALCON_IMAGE_ANALYZER"
    if [[ "$DEPLOY_FALCON_CONTAINER" == "true" ]]; then
        log "INFO" "NOTE:"
        log "INFO" "To enable container sensor injection on Fargate pods, add label:"
        log "INFO" "  falcon.crowdstrike.com/inject: \"true\""
    fi
}

# Run main function
main
