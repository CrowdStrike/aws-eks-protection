#!/bin/bash

# Configuration variables
TIMEOUT=${TIMEOUT:-300}
AWS_REGION=${AWS_REGION:-""}
EKS_CLUSTER_NAME=${EKS_CLUSTER_NAME:-""}
ACCOUNT_ID=${ACCOUNT_ID:-""}

# Role assumption configuration
EXECUTION_ROLE_NAME="crowdstrike-eks-protection-execution-role"

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
DEPLOY_FALCON_NODE_SENSOR="false"
DEPLOY_FALCON_CONTAINER="false"
IS_FARGATE="false"

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
    exit $exit_code
}

# Set error handling after functions are defined
set -eo pipefail
trap 'handle_error $? $LINENO' ERR

# Function to assume IAM role for EKS operations
assume_execution_role() {
    log "INFO" "Assuming role: $EXECUTION_ROLE_NAME"
    
    if [ -z "$ACCOUNT_ID" ]; then
        ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    fi
    
    local role_arn="arn:aws:iam::${ACCOUNT_ID}:role/${EXECUTION_ROLE_NAME}"
    local session_name="cs-eks-protect-$(date +%s)"
    
    local role_credentials=$(aws sts assume-role \
        --role-arn "$role_arn" \
        --role-session-name "$session_name" \
        --output json)
    
    if [ $? -ne 0 ]; then
        log "ERROR" "Failed to assume role: $role_arn"
        exit 1
    fi
    
    # Export the assumed role credentials
    export AWS_ACCESS_KEY_ID=$(echo "$role_credentials" | jq -r '.Credentials.AccessKeyId')
    export AWS_SECRET_ACCESS_KEY=$(echo "$role_credentials" | jq -r '.Credentials.SecretAccessKey')
    export AWS_SESSION_TOKEN=$(echo "$role_credentials" | jq -r '.Credentials.SessionToken')
    
    # Verify the role assumption
    local assumed_identity=$(aws sts get-caller-identity --output json)
    local assumed_arn=$(echo "$assumed_identity" | jq -r '.Arn')
    
    if [[ "$assumed_arn" == *"$EXECUTION_ROLE_NAME"* ]]; then
        log "SUCCESS" "Role assumed successfully: $assumed_arn"
    else
        log "ERROR" "Role assumption verification failed. Current identity: $assumed_arn"
        exit 1
    fi
}

# Function to check AWS CLI and configure EKS kubeconfig
set_kubeconfig() {
    if ! command -v aws &> /dev/null; then
        log "ERROR" "AWS CLI is not installed"
        exit 1
    fi

    if [ -z "$EKS_CLUSTER_NAME" ]; then
        log "ERROR" "EKS_CLUSTER_NAME is not set"
        exit 1
    fi

    # Generate kubeconfig with direct token instead of exec plugin
    log "INFO" "Generating EKS token and creating token-based kubeconfig"
    
    # Get the cluster endpoint and CA data
    CLUSTER_ENDPOINT=$(aws eks describe-cluster --name "$EKS_CLUSTER_NAME" --region "$AWS_REGION" --query 'cluster.endpoint' --output text)
    CLUSTER_CA=$(aws eks describe-cluster --name "$EKS_CLUSTER_NAME" --region "$AWS_REGION" --query 'cluster.certificateAuthority.data' --output text)
    
    # Generate token directly
    TOKEN_RESPONSE=$(aws eks get-token --cluster-name "$EKS_CLUSTER_NAME" --region "$AWS_REGION" --output json)
    TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.status.token')
    
    if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
        log "ERROR" "Failed to generate EKS token"
        exit 1
    fi
    
    log "INFO" "Token generated successfully, creating kubeconfig"
    
    # Create kubeconfig with direct token
    mkdir -p ~/.kube
    cat > ~/.kube/config << EOF
apiVersion: v1
kind: Config
clusters:
- cluster:
    certificate-authority-data: $CLUSTER_CA
    server: $CLUSTER_ENDPOINT
  name: $EKS_CLUSTER_NAME
contexts:
- context:
    cluster: $EKS_CLUSTER_NAME
    user: $EKS_CLUSTER_NAME-user
  name: $EKS_CLUSTER_NAME
current-context: $EKS_CLUSTER_NAME
users:
- name: $EKS_CLUSTER_NAME-user
  user:
    token: $TOKEN
EOF

    log "INFO" "Token-based kubeconfig created successfully"
}

# Function to check kubectl and cluster connectivity
check_cluster_connection() {
    if ! command -v kubectl &> /dev/null; then
        log "ERROR" "kubectl is not installed"
        exit 1
    fi

    kubectl config view --minify --raw

    log "INFO" "Testing Kubernetes cluster connectivity..."
    
    # Debug AWS credentials and token generation
    log "INFO" "Current AWS identity:"
    aws sts get-caller-identity || log "ERROR" "AWS credentials not working"
    
    log "INFO" "Testing direct AWS EKS get-token call:"
    aws eks get-token --cluster-name "$EKS_CLUSTER_NAME" --region "$AWS_REGION" || log "ERROR" "AWS EKS get-token failed"
    
    # Debug information
    log "INFO" "Current kubeconfig context:"
    kubectl config current-context || log "WARNING" "No current context set"
    
    log "INFO" "Cluster endpoint from kubeconfig:"
    kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}' || log "WARNING" "Cannot get cluster endpoint"
    
    log "INFO" "Testing cluster connectivity with detailed output..."
    if ! kubectl cluster-info; then
        log "ERROR" "Unable to connect to Kubernetes cluster"
        
        # Additional debugging
        log "INFO" "Attempting to get cluster version for more details..."
        kubectl version 2>&1 || log "WARNING" "kubectl version failed"
        
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

detect_cluster_type() {
    log "INFO" "Detecting cluster type for $EKS_CLUSTER_NAME"
    local max_attempts=6
    local attempt=1

    # Check for Fargate profiles
    while [[ $attempt -le $max_attempts ]]; do
        log "INFO" "Looking for Fargate profiles (attempt $attempt/$max_attempts)..."
        
        if aws eks list-fargate-profiles \
            --cluster-name "$EKS_CLUSTER_NAME" \
            --region "$AWS_REGION" \
            --query 'fargateProfileNames' \
            --output text 2>/dev/null | grep -v -q "None"; then
            export IS_FARGATE="true"
            log "INFO" "Cluster has fargate profiles"
            break
        fi

        # fargate_profiles=$(aws eks list-fargate-profiles \
        #     --cluster-name "$EKS_CLUSTER_NAME" \
        #     --region "$AWS_REGION" \
        #     --query 'fargateProfileNames' \
        #     --output text 2>/dev/null)
        
        # if [[ -n "$fargate_profiles" ]] && [[ "$fargate_profiles" != "None" ]] && [[ "$fargate_profiles" != "" ]]; then
        #     log "INFO" "Found Fargate profiles: $fargate_profiles"
        #     break
        # fi
        if [[ $attempt -eq $max_attempts ]]; then
            log "WARN" "No Fargate profiles found after $max_attempts attempts"
            break
        fi
        
        sleep 10
        attempt=$((attempt + 1))
    done

    # Check for node groups
    local attempt=1
    while [[ $attempt -le $max_attempts ]]; do
        log "INFO" "Looking for node groups (attempt $attempt/$max_attempts)..."
        
        if aws eks list-nodegroups \
            --cluster-name "$EKS_CLUSTER_NAME" \
            --region "$AWS_REGION" \
            --query 'nodegroups[0]' \
            --output text 2>/dev/null | grep -v -q "None"; then
            HAS_NODES="true"
            log "INFO" "Cluster has node groups"
            break
        fi
        
        if [[ $attempt -eq $max_attempts ]]; then
            log "WARN" "No node groups found after $max_attempts attempts"
            break
        fi
        
        sleep 10
        ((attempt++))
    done


    if [[ "$IS_FARGATE" == "true" ]]; then
        export DEPLOY_FALCON_CONTAINER="true"
    fi
    if [[ "$HAS_NODES" == "true" ]]; then
        export DEPLOY_FALCON_NODE_SENSOR="true"
    fi
    # If neither found, default to node deployment
    if [[ "$IS_FARGATE" == "false" && "$HAS_NODES" == "false" ]]; then
        export DEPLOY_FALCON_NODE_SENSOR="true"
    fi
}

determine_sensor() {
    if [[ "$SENSOR_TYPE" == "node" ]]; then
        export DEPLOY_FALCON_NODE_SENSOR="true"
    fi
    if [[ "$SENSOR_TYPE" == "container" ]]; then
        export DEPLOY_FALCON_CONTAINER="true"
    fi
    # If neither found, default to node deployment
    if [[ "$SENSOR_TYPE" == "both" ]]; then
        export DEPLOY_FALCON_CONTAINER="true"
        export DEPLOY_FALCON_NODE_SENSOR="true"
    fi
}

install_fargate_profile() {
    if ! aws eks describe-fargate-profile \
            --region "$AWS_REGION" \
            --cluster-name "$EKS_CLUSTER_NAME" \
            --fargate-profile-name fp-falcon-operator \
            --query 'fargateProfile.fargateProfileName' \
            --output text &>/dev/null; then
    
        log "INFO" "Attempting to discover existing Fargate pod execution role..."
        
        # Try to get role ARN from existing Fargate profile
        log "INFO" "Checking existing Fargate profiles for role ARN..."
        # shellcheck disable=SC2155
        local existing_profile=$(aws eks list-fargate-profiles \
            --cluster-name "$EKS_CLUSTER_NAME" \
            --region "$AWS_REGION" \
            --query 'fargateProfileNames[0]' \
            --output text 2>/dev/null)

        if [ "$existing_profile" != "None" ] && [ -n "$existing_profile" ]; then
            # shellcheck disable=SC2155
            local role_arn=$(aws eks describe-fargate-profile \
                --cluster-name "$EKS_CLUSTER_NAME" \
                --fargate-profile-name "$existing_profile" \
                --region "$AWS_REGION" \
                --query 'fargateProfile.podExecutionRoleArn' \
                --output text 2>/dev/null)
        fi

        if [ -n "$role_arn" ] && [ "$role_arn" != "None" ]; then
            log "INFO" "Found role ARN from existing Fargate profile '$existing_profile': $role_arn"
        else
            # Else try to look for roles with the Fargate execution policy attached
            log "INFO" "Searching for roles with AmazonEKSFargatePodExecutionRolePolicy..."
            # shellcheck disable=SC2155
            local role_name=$(aws iam list-entities-for-policy \
                --policy-arn arn:aws:iam::aws:policy/AmazonEKSFargatePodExecutionRolePolicy \
                --entity-filter Role \
                --query 'PolicyRoles[0].RoleName' \
                --output text 2>/dev/null)
            
            if [ "$role_name" != "None" ] && [ -n "$role_name" ]; then
                local role_arn="arn:aws:iam::${ACCOUNT_ID}:role/${role_name}"
                log "INFO" "Found role with Fargate execution policy: $role_arn"
            fi
        fi

        log "INFO" "Creating Fargate profile fp-falcon-operator..."
        if [ -z "$role_arn" ]; then
            log "ERROR" "No Fargate pod execution role found using any discovery method"
            log "ERROR" "Please ensure:"
            log "ERROR" "  1. A role exists with the AmazonEKSFargatePodExecutionRolePolicy attached, OR"
            log "ERROR" "  2. An existing Fargate profile exists in the cluster"
            exit 1
        fi
        aws eks create-fargate-profile \
            --region "$AWS_REGION" \
            --cluster-name "$EKS_CLUSTER_NAME" \
            --fargate-profile-name fp-falcon-operator \
            --pod-execution-role-arn "$role_arn" \
            --selectors namespace=falcon-operator

    else
        log "INFO" "Fargate profile fp-falcon-operator exists"
    fi
}

# Function to install CrowdStrike Falcon Operator
install_falcon_operator() {
    log "INFO" "Installing CrowdStrike Falcon Operator"

    if [[ "$IS_FARGATE" == "true" ]] && [[ "$DEPLOY_FALCON_NODE_SENSOR" == "false" ]]; then
        install_fargate_profile
    fi

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
    
    wait_for_operator
}

# Function to wait for operator to be ready
wait_for_operator() {
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
 
    # Create temporary manifest file with substitutions
    # shellcheck disable=SC2155
    local manifest_file="/tmp/falcon-deployment-$(date +%s).yaml"
    
    # Replace placeholder values in the manifest
    echo "$MANIFEST_TEMPLATE" | \
        sed "s/SET_NODE_SENSOR/$DEPLOY_FALCON_NODE_SENSOR/g" | \
        sed "s/SET_CONTAINER_SENSOR/$DEPLOY_FALCON_CONTAINER/g" | \
        sed "s/SET_FALCON_ADMISSION/$DEPLOY_FALCON_ADMISSION/g" | \
        sed "s/SET_IMAGE_ANALYZER/$DEPLOY_FALCON_IMAGE_ANALYZER/g" > "$manifest_file"
    
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
    # Assume execution role first
    assume_execution_role
    
    # Setup and check configuration
    set_kubeconfig
    check_cluster_connection
    if [[ "$SENSOR_TYPE" == "auto" ]]; then
        detect_cluster_type
    else
        determine_sensor
    fi

    # CrowdStrike Falcon Operator Installation
    validate_falcon_credentials
    install_falcon_operator
    
    # Deploy Falcon resources
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
