#!/bin/bash
set -eo pipefail

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

# Function to validate and setup configuration
setup_configuration() {
    log "INFO" "Setting up CrowdStrike Falcon EKS Protection configuration..."
    
    # Validate required environment variables (now passed directly from EventBridge)
    if [[ -z "${EKS_CLUSTER_NAME}" ]]; then
        log "ERROR" "EKS_CLUSTER_NAME environment variable is required"
        exit 1
    fi
    
    if [[ -z "${AWS_REGION}" ]]; then
        log "ERROR" "AWS_REGION environment variable is required"
        exit 1
    fi
    
    log "INFO" "Event-sourced values:"
    log "INFO" "  EKS Cluster: ${EKS_CLUSTER_NAME}"
    log "INFO" "  AWS Region: ${AWS_REGION}"
    log "INFO" "  Account ID: ${ACCOUNT_ID:-'Not provided'}"
    
    # Set default values for containerized execution
    export NAMESPACE=${NAMESPACE:-"default"}
    export POD_NAME=${POD_NAME:-"falcon-test-app"}
    export DEPLOYMENT_NAME=${DEPLOYMENT_NAME:-"falcon-test-app"}
    export DEPLOY_FALCON_OPERATOR=${DEPLOY_FALCON_OPERATOR:-"true"}
    export DEPLOY_FALCON_RESOURCES=${DEPLOY_FALCON_RESOURCES:-"true"}
    
    log "INFO" "Configuration:"
    log "INFO" "  EKS Cluster: ${EKS_CLUSTER_NAME}"
    log "INFO" "  AWS Region: ${AWS_REGION}"
    log "INFO" "  Deploy Falcon Operator: ${DEPLOY_FALCON_OPERATOR}"
    log "INFO" "  Deploy Falcon Resources: ${DEPLOY_FALCON_RESOURCES}"
}

# Function to wait for cluster to be available
wait_for_cluster() {
    log "INFO" "Waiting for EKS cluster to be available..."
    local max_attempts=30
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        if aws eks describe-cluster --name "${EKS_CLUSTER_NAME}" --region "${AWS_REGION}" --query 'cluster.status' --output text 2>/dev/null | grep "ACTIVE"; then
            log "INFO" "EKS cluster ${EKS_CLUSTER_NAME} is active"
            return 0
        fi
        
        log "INFO" "Waiting for cluster to be active (attempt $attempt/$max_attempts)..."
        sleep 60
        attempt=$((attempt + 1))
    done
    
    log "ERROR" "EKS cluster did not become active within timeout"
    return 1
}

# Main execution
main() {
    log "INFO" "=== CrowdStrike Falcon EKS Protection - Event-Driven Execution ==="
    
    # Setup config
    setup_configuration
    
    # assume role
    if [[ -n "$ASSUME_ROLE_ARN" ]]; then
        log "INFO" "Assuming role: $ASSUME_ROLE_ARN"
        
        CREDENTIALS=$(aws sts assume-role \
            --role-arn "$ASSUME_ROLE_ARN" \
            --role-session-name "cs-eks-protect-$(date +%s)" \
            --output json)
        
        export AWS_ACCESS_KEY_ID=$(log "INFO" "$CREDENTIALS" | jq -r '.Credentials.AccessKeyId')
        export AWS_SECRET_ACCESS_KEY=$(log "INFO" "$CREDENTIALS" | jq -r '.Credentials.SecretAccessKey')
        export AWS_SESSION_TOKEN=$(log "INFO" "$CREDENTIALS" | jq -r '.Credentials.SessionToken')
        
        log "INFO" "Role assumed successfully"
    else
        log "INFO" "No role to assume, using default credentials"
    fi
    
    # Wait for cluster to be available
    wait_for_cluster
    
    # Setup Cluster Access
    log "INFO" "Updating Access configuration for cluster ${EKS_CLUSTER_NAME}..."
    python3 setup_cluster.py

    # Update kubeconfig
    log "INFO" "Updating kubeconfig for cluster ${EKS_CLUSTER_NAME}..."
    aws eks update-kubeconfig --name "${EKS_CLUSTER_NAME}" --region "${AWS_REGION}"

    # Execute the main installation script
    log "INFO" "Executing CrowdStrike Falcon Operator installation..."
    cd /app
    exec ./check_and_install.sh
}

# Run main function
main "$@"
