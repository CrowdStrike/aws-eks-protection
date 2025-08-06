#!/bin/bash
set -eo pipefail

# Function to parse EventBridge event for EKS cluster information
parse_event() {
    echo "Processing EKS cluster event..."
    
    # Check if we have event data from EventBridge
    if [[ -n "${EVENT_DATA}" ]]; then
        echo "Event data received: ${EVENT_DATA}"
        
        # Extract cluster information from event
        export EKS_CLUSTER_NAME=$(echo "${EVENT_DATA}" | jq -r '.detail.responseElements.cluster.name // .detail.requestParameters.name // empty')
        export AWS_REGION=$(echo "${EVENT_DATA}" | jq -r '.detail.awsRegion // empty')
        
        if [[ -z "${EKS_CLUSTER_NAME}" || "${EKS_CLUSTER_NAME}" == "null" ]]; then
            echo "ERROR: Could not extract cluster name from event data"
            exit 1
        fi
        
        echo "Extracted EKS cluster: ${EKS_CLUSTER_NAME} in region: ${AWS_REGION}"
    else
        echo "No EVENT_DATA found, checking environment variables..."
        
        # Check for environment variables if no event data
        if [[ -n "${EKS_CLUSTER_NAME}" ]]; then
            echo "Using EKS_CLUSTER_NAME from environment: ${EKS_CLUSTER_NAME}"
        fi
        
        if [[ -n "${AWS_REGION}" ]]; then
            echo "Using AWS_REGION from environment: ${AWS_REGION}"
        fi
    fi
    
    # Validate required environment variables
    if [[ -z "${EKS_CLUSTER_NAME}" ]]; then
        echo "ERROR: EKS_CLUSTER_NAME environment variable is required"
        exit 1
    fi
    
    if [[ -z "${AWS_REGION}" ]]; then
        echo "ERROR: AWS_REGION environment variable is required"
        exit 1
    fi
    
    # Set default values for containerized execution
    export NAMESPACE=${NAMESPACE:-"default"}
    export POD_NAME=${POD_NAME:-"falcon-test-app"}
    export DEPLOYMENT_NAME=${DEPLOYMENT_NAME:-"falcon-test-app"}
    export DEPLOY_FALCON_OPERATOR=${DEPLOY_FALCON_OPERATOR:-"true"}
    export DEPLOY_FALCON_RESOURCES=${DEPLOY_FALCON_RESOURCES:-"true"}
    
    echo "Configuration:"
    echo "  EKS Cluster: ${EKS_CLUSTER_NAME}"
    echo "  AWS Region: ${AWS_REGION}"
    echo "  Deploy Falcon Operator: ${DEPLOY_FALCON_OPERATOR}"
    echo "  Deploy Falcon Resources: ${DEPLOY_FALCON_RESOURCES}"
}

# Function to wait for cluster to be available
wait_for_cluster() {
    echo "Waiting for EKS cluster to be available..."
    local max_attempts=30
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        if aws eks describe-cluster --name "${EKS_CLUSTER_NAME}" --region "${AWS_REGION}" --query 'cluster.status' --output text 2>/dev/null | grep "ACTIVE"; then
            echo "EKS cluster ${EKS_CLUSTER_NAME} is active"
            return 0
        fi
        
        echo "Waiting for cluster to be active (attempt $attempt/$max_attempts)..."
        sleep 30
        attempt=$((attempt + 1))
    done
    
    echo "ERROR: EKS cluster did not become active within timeout"
    return 1
}

# Main execution
main() {
    echo "=== CrowdStrike Falcon EKS Protection - Event-Driven Execution ==="
    
    # Parse event data
    parse_event
    
    # assume role
    if [[ -n "$ASSUME_ROLE_ARN" ]]; then
        echo "Assuming role: $ASSUME_ROLE_ARN"
        
        CREDENTIALS=$(aws sts assume-role \
            --role-arn "$ASSUME_ROLE_ARN" \
            --role-session-name "cs-eks-protect-$(date +%s)" \
            --output json)
        
        export AWS_ACCESS_KEY_ID=$(echo "$CREDENTIALS" | jq -r '.Credentials.AccessKeyId')
        export AWS_SECRET_ACCESS_KEY=$(echo "$CREDENTIALS" | jq -r '.Credentials.SecretAccessKey')
        export AWS_SESSION_TOKEN=$(echo "$CREDENTIALS" | jq -r '.Credentials.SessionToken')
        
        echo "Role assumed successfully"
    else
        echo "No role to assume, using default credentials"
    fi
    
    # Wait for cluster to be available
    wait_for_cluster
    
    # Setup Cluster Access
    echo "Updating Access configuration for cluster ${EKS_CLUSTER_NAME}..."
    python3 setup_cluster.py

    # Update kubeconfig
    echo "Updating kubeconfig for cluster ${EKS_CLUSTER_NAME}..."
    aws eks update-kubeconfig --name "${EKS_CLUSTER_NAME}" --region "${AWS_REGION}"

    # Execute the main installation script
    echo "Executing CrowdStrike Falcon Operator installation..."
    cd /app
    exec ./check_and_install.sh
}

# Run main function
main "$@"
