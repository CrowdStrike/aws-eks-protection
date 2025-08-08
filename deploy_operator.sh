#!/bin/bash

# Configuration variables with defaults
NAMESPACE=${NAMESPACE:-"default"}
POD_NAME=${POD_NAME:-"my-application"}
DEPLOYMENT_NAME=${DEPLOYMENT_NAME:-"my-application"}
DEPLOYMENT_YAML=${DEPLOYMENT_YAML:-""}
TIMEOUT=${TIMEOUT:-300}
AWS_REGION=${AWS_REGION:-"us-west-2"}
EKS_CLUSTER_NAME=${EKS_CLUSTER_NAME:-""}
KUBECTL_CONTEXT=${KUBECTL_CONTEXT:-""}

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
DEPLOY_FALCON_IMAGE_ANALYZER=${DEPLOY_FALCON_IMAGE_ANALYZER:-"false"}
DEPLOY_FALCON_NODE_SENSOR=${DEPLOY_FALCON_NODE_SENSOR:-"auto"}    # auto, true, false
DEPLOY_FALCON_CONTAINER=${DEPLOY_FALCON_CONTAINER:-"auto"}        # auto, true, false

# Fargate-specific variables
FARGATE_PROFILE_NAME=${FARGATE_PROFILE_NAME:-""}
FARGATE_POD_EXECUTION_ROLE_ARN=${FARGATE_POD_EXECUTION_ROLE_ARN:-""}
FARGATE_SUBNETS=${FARGATE_SUBNETS:-""}

# Cluster type detection variables
IS_FARGATE="false"
HAS_MANAGED_NODES="false"

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

# Function to detect cluster type
detect_cluster_type() {
    log "INFO" "Detecting cluster type for $EKS_CLUSTER_NAME"
    
    # Check for Fargate profiles
    local fargate_profiles
    fargate_profiles=$(aws eks list-fargate-profiles \
        --cluster-name "$EKS_CLUSTER_NAME" \
        --region "$AWS_REGION" \
        --query 'fargateProfileNames' \
        --output text 2>/dev/null)
    
    if [[ -n "$fargate_profiles" && "$fargate_profiles" != "None" && "$fargate_profiles" != "null" ]]; then
        IS_FARGATE="true"
        log "INFO" "Cluster has Fargate profiles: $fargate_profiles"
    else
        log "INFO" "No Fargate profiles detected"
    fi

    # Check for managed node groups
    if aws eks list-nodegroups \
        --cluster-name "$EKS_CLUSTER_NAME" \
        --region "$AWS_REGION" \
        --query 'nodegroups[0]' \
        --output text 2>/dev/null | grep -q .; then
        HAS_MANAGED_NODES="true"
        log "INFO" "Cluster has managed node groups"
    fi

    # If neither found, check for self-managed nodes
    if [[ "$IS_FARGATE" == "false" && "$HAS_MANAGED_NODES" == "false" ]]; then
        if kubectl get nodes --no-headers 2>/dev/null | grep -q .; then
            log "INFO" "Cluster has self-managed nodes"
            HAS_MANAGED_NODES="true"
        fi
    fi

    # Log cluster type
    if [[ "$IS_FARGATE" == "true" ]]; then
        if [[ "$HAS_MANAGED_NODES" == "true" ]]; then
            log "INFO" "Detected hybrid cluster (Fargate + Node Groups)"
        else
            log "INFO" "Detected Fargate-only cluster"
        fi
    else
        log "INFO" "Detected node-based cluster"
    fi
}

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

# Function to determine sensor deployment strategy based on cluster type
determine_sensor_strategy() {
    local deploy_node_sensor="false"
    local deploy_container="false"
    
    # Auto-determine based on cluster type if set to "auto"
    if [[ "$DEPLOY_FALCON_NODE_SENSOR" == "auto" || "$DEPLOY_FALCON_CONTAINER" == "auto" ]]; then
        if [[ "$IS_FARGATE" == "true" && "$HAS_MANAGED_NODES" == "false" ]]; then
            # Fargate-only cluster - use container sensor
            deploy_container="true"
            deploy_node_sensor="false"
            log "INFO" "Fargate-only cluster detected - using FalconContainer"
        elif [[ "$HAS_MANAGED_NODES" == "true" ]]; then
            # Node-based or hybrid cluster - prefer node sensor
            deploy_node_sensor="true"
            deploy_container="false"
            log "INFO" "Node-based cluster detected - using FalconNodeSensor"
        else
            log "WARNING" "Could not determine cluster type - defaulting to FalconNodeSensor"
            deploy_node_sensor="true"
            deploy_container="false"
        fi
    else
        # Use explicit settings
        deploy_node_sensor="$DEPLOY_FALCON_NODE_SENSOR"
        deploy_container="$DEPLOY_FALCON_CONTAINER"
    fi
    
    # Validate that both aren't enabled
    if [[ "$deploy_node_sensor" == "true" && "$deploy_container" == "true" ]]; then
        log "ERROR" "Cannot deploy both FalconNodeSensor and FalconContainer on the same cluster"
        exit 1
    fi
    
    # Export for use in other functions
    export FINAL_DEPLOY_NODE_SENSOR="$deploy_node_sensor"
    export FINAL_DEPLOY_CONTAINER="$deploy_container"
    
    log "INFO" "Sensor strategy: NodeSensor=$deploy_node_sensor, Container=$deploy_container"
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
    
    # Determine sensor strategy
    determine_sensor_strategy
    
    # Create API credentials secret
    create_falcon_secret
    
    # Get FalconDeployment Manifest from Parameter Store
    log "INFO" "Retrieving FalconDeployment manifest from Parameter Store"
    
    # Check if FALCON_DEPLOYMENT_PARAMETER is set
    if [[ -z "$FALCON_DEPLOYMENT_PARAMETER" ]]; then
        log "ERROR" "FALCON_DEPLOYMENT_PARAMETER environment variable is not set"
        exit 1
    fi
    
    # Retrieve the manifest template from Parameter Store
    local manifest_template
    manifest_template=$(aws ssm get-parameter \
        --name "$FALCON_DEPLOYMENT_PARAMETER" \
        --region "$AWS_REGION" \
        --query 'Parameter.Value' \
        --output text)
    
    if [ $? -ne 0 ]; then
        log "ERROR" "Failed to retrieve FalconDeployment manifest from Parameter Store"
        exit 1
    fi
    
    # Create temporary manifest file
    manifest_file="/tmp/falcon-deployment-$(date +%s).yaml"
    
    # Replace placeholders with actual determined values
    echo "$manifest_template" | \
        sed "s/FINAL_DEPLOY_NODE_SENSOR/$FINAL_DEPLOY_NODE_SENSOR/g" | \
        sed "s/FINAL_DEPLOY_CONTAINER/$FINAL_DEPLOY_CONTAINER/g" > "$manifest_file"
    
    if [ ! -f "$manifest_file" ]; then
        log "ERROR" "Failed to create FalconDeployment manifest file"
        exit 1
    fi
    
    log "SUCCESS" "FalconDeployment manifest prepared successfully"
    log "INFO" "Manifest file: $manifest_file"

    # Apply the FalconDeployment
    log "INFO" "Applying FalconDeployment manifest"
    log "INFO" "Components enabled: NodeSensor=$FINAL_DEPLOY_NODE_SENSOR, Container=$FINAL_DEPLOY_CONTAINER, Admission=$DEPLOY_FALCON_ADMISSION, ImageAnalyzer=$DEPLOY_FALCON_IMAGE_ANALYZER"
    
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
        if [[ "$FINAL_DEPLOY_NODE_SENSOR" == "true" ]]; then
            kubectl get falconnodesensor -A 2>/dev/null || log "WARNING" "FalconNodeSensor not yet created"
        fi
        if [[ "$FINAL_DEPLOY_CONTAINER" == "true" ]]; then
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
    
    # Detect cluster type
    detect_cluster_type
    
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
}

# Run main function
main
