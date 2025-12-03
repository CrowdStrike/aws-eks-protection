#!/bin/bash

# Deployment Script for CrowdStrike Falcon EKS Protection
# Uses alpine/k8s:1.28.4 public image with no build dependencies

set -eo pipefail

# Configuration
REGION=${AWS_REGION:-"us-west-2"}
SCOPE=${SCOPE:-"local account"}
REGIONS=${REGIONS:-""}
OUS=${OUS:-""}
ORGANIZATION_ID=${ORGANIZATION_ID:-""}
PERMISSIONS_BOUNDARY=${PERMISSIONS_BOUNDARY:-""}
VPC_CIDR=${VPC_CIDR:-"10.0.0.0/22"}
FALCON_CLIENT_ID=${FALCON_CLIENT_ID:-""}
FALCON_CLIENT_SECRET=${FALCON_CLIENT_SECRET:-""}
FALCON_CLOUD=${FALCON_CLOUD:-"us-1"}
DEPLOY_FALCON_ADMISSION=${DEPLOY_FALCON_ADMISSION:-"true"}
DEPLOY_FALCON_IMAGE_ANALYZER=${DEPLOY_FALCON_IMAGE_ANALYZER:-"false"}
DEPLOY_FALCON_NODE_SENSOR=${DEPLOY_FALCON_NODE_SENSOR:-"auto"}
DEPLOY_FALCON_CONTAINER=${DEPLOY_FALCON_CONTAINER:-"auto"}
RESOURCE_PREFIX=${RESOURCE_PREFIX:-"crowdstrike-eks-protection"}
RESOURCE_SUFFIX=${RESOURCE_SUFFIX:-""}
STACK_NAME=${STACK_NAME:-"crowdstrike-falcon-eks-protection"}

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

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

# Function to show usage
show_usage() {
    cat <<EOF
CrowdStrike Falcon EKS Protection - Deployment Script

Prerequisites:
- AWS CLI configured with appropriate credentials
- CrowdStrike Falcon API credentials

Required Environment Variables:
export AWS_REGION="us-west-2"                    # AWS region for deployment
export FALCON_CLIENT_ID="your-client-id"         # CrowdStrike Falcon Client ID
export FALCON_CLIENT_SECRET="your-client-secret" # CrowdStrike Falcon Client Secret
export FALCON_CLOUD="us-1"                       # CrowdStrike cloud region: us-1, us-2, eu-1, us-gov-1, us-gov-2

Optional Environment Variables:
# Deployment scope (local account or organization-wide)
export SCOPE="local account"                     # "local account" or "organization" (default: local account)

# Organization deployment parameters (required if SCOPE=organization)
export ORGANIZATION_ID="o-xxxxxxxxxx"            # AWS Organization ID
export REGIONS="us-west-2,us-east-1"            # Comma-separated list of regions
export OUS="r-xxxx,ou-xxxx-xxxxxxxx"            # Comma-separated list of Organization Units

# Network configuration
export VPC_CIDR="10.0.0.0/22"                   # VPC CIDR block (default: 10.0.0.0/22)

# Falcon component deployment flags
export DEPLOY_FALCON_ADMISSION="true"            # Deploy Falcon Kubernetes Admission Controller (default: true)
export DEPLOY_FALCON_IMAGE_ANALYZER="false"      # Deploy Falcon Image Analyzer (default: false)
export DEPLOY_FALCON_NODE_SENSOR="auto"          # Deploy Falcon Node Sensor: auto, true, false (default: auto)
export DEPLOY_FALCON_CONTAINER="auto"            # Deploy Falcon Container Sensor: auto, true, false (default: auto)

# Resource naming
export RESOURCE_PREFIX="crowdstrike-eks-protection"  # Resource name prefix (default: crowdstrike-eks-protection)
export RESOURCE_SUFFIX=""                        # Resource name suffix (default: empty)
export PERMISSIONS_BOUNDARY=""                   # IAM permissions boundary policy name (optional)
export STACK_NAME="crowdstrike-falcon-eks-protection"  # CloudFormation stack name (optional)

Usage:
./deploy.sh [command]

Commands:
  cloudformation    Deploy the solution using CloudFormation
  status           Check deployment status
  help             Show this help message

Examples:
# Local account deployment (default)
export SCOPE="local account" 
export FALCON_CLIENT_ID="your-client-id"
export FALCON_CLIENT_SECRET="your-client-secret"
export FALCON_CLOUD="us-1"
./deploy.sh cloudformation

# Organization-wide deployment
export SCOPE="organization"
export ORGANIZATION_ID="o-xxxxxxxxxx"
export REGIONS="us-west-2,us-east-1,eu-west-1"
export OUS="r-xxxx"
export FALCON_CLIENT_ID="your-client-id"
export FALCON_CLIENT_SECRET="your-client-secret"
export FALCON_CLOUD="us-1"
./deploy.sh cloudformation

# Check deployment status
./deploy.sh status

EOF
}

# Function to validate prerequisites
validate_prerequisites() {
    log "INFO" "Validating prerequisites..."
    
    # Check required tools
    local required_tools=("aws")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            log "ERROR" "$tool is not installed"
            exit 1
        fi
    done
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log "ERROR" "AWS credentials not configured"
        exit 1
    fi
    
    # Check required environment variables
    if [[ -z "$FALCON_CLIENT_ID" || -z "$FALCON_CLIENT_SECRET" ]]; then
        log "ERROR" "CrowdStrike API credentials are required"
        log "ERROR" "Please set FALCON_CLIENT_ID and FALCON_CLIENT_SECRET environment variables"
        exit 1
    fi
    
    # If organization deployment, validate organization parameters
    if [[ "$SCOPE" == "organization" ]]; then
        if [[ -z "$ORGANIZATION_ID" ]]; then
            log "ERROR" "ORGANIZATION_ID is required for organization scope deployment"
            exit 1
        fi
        
        if [[ -z "$REGIONS" ]]; then
            log "ERROR" "REGIONS is required for organization scope deployment"
            exit 1
        fi
        
        if [[ -z "$OUS" ]]; then
            log "ERROR" "OUS is required for organization scope deployment"
            exit 1
        fi
    fi
    
    # Validate FALCON_CLOUD parameter
    local valid_clouds=("us-1" "us-2" "eu-1" "us-gov-1" "us-gov-2")
    local cloud_valid=false
    for valid_cloud in "${valid_clouds[@]}"; do
        if [[ "$FALCON_CLOUD" == "$valid_cloud" ]]; then
            cloud_valid=true
            break
        fi
    done
    
    if [[ "$cloud_valid" != "true" ]]; then
        log "ERROR" "Invalid FALCON_CLOUD value: $FALCON_CLOUD"
        log "ERROR" "Valid values are: ${valid_clouds[*]}"
        exit 1
    fi
    
    # Validate deployment flags
    local valid_admission=false
    local valid_analyzer=false
    local valid_node=false
    local valid_container=false
    
    # Check DEPLOY_FALCON_ADMISSION
    for value in "true" "false"; do
        if [[ "$DEPLOY_FALCON_ADMISSION" == "$value" ]]; then
            valid_admission=true
            break
        fi
    done
    
    if [[ "$valid_admission" != "true" ]]; then
        log "ERROR" "Invalid DEPLOY_FALCON_ADMISSION value: $DEPLOY_FALCON_ADMISSION (must be: true or false)"
        exit 1
    fi
    
    # Check DEPLOY_FALCON_IMAGE_ANALYZER  
    for value in "true" "false"; do
        if [[ "$DEPLOY_FALCON_IMAGE_ANALYZER" == "$value" ]]; then
            valid_analyzer=true
            break
        fi
    done
    
    if [[ "$valid_analyzer" != "true" ]]; then
        log "ERROR" "Invalid DEPLOY_FALCON_IMAGE_ANALYZER value: $DEPLOY_FALCON_IMAGE_ANALYZER (must be: true or false)"
        exit 1
    fi
    
    # Check DEPLOY_FALCON_NODE_SENSOR
    for value in "true" "false" "auto"; do
        if [[ "$DEPLOY_FALCON_NODE_SENSOR" == "$value" ]]; then
            valid_node=true
            break
        fi
    done
    
    if [[ "$valid_node" != "true" ]]; then
        log "ERROR" "Invalid DEPLOY_FALCON_NODE_SENSOR value: $DEPLOY_FALCON_NODE_SENSOR (must be: auto, true, or false)"
        exit 1
    fi
    
    # Check DEPLOY_FALCON_CONTAINER
    for value in "true" "false" "auto"; do
        if [[ "$DEPLOY_FALCON_CONTAINER" == "$value" ]]; then
            valid_container=true
            break
        fi
    done
    
    if [[ "$valid_container" != "true" ]]; then
        log "ERROR" "Invalid DEPLOY_FALCON_CONTAINER value: $DEPLOY_FALCON_CONTAINER (must be: auto, true, or false)"
        exit 1
    fi
    
    log "SUCCESS" "Prerequisites validation passed"
}

# Function to deploy with CloudFormation
deploy_cloudformation() {
    log "INFO" "Deploying with CloudFormation..."
    
    # Build parameter overrides dynamically
    local param_overrides=(
        "Scope=$SCOPE"
        "FalconClientId=$FALCON_CLIENT_ID"
        "FalconClientSecret=$FALCON_CLIENT_SECRET"
        "FalconCloud=$FALCON_CLOUD"
        "DeployFalconAdmission=$DEPLOY_FALCON_ADMISSION"
        "DeployFalconImageAnalyzer=$DEPLOY_FALCON_IMAGE_ANALYZER"
        "DeployFalconNodeSensor=$DEPLOY_FALCON_NODE_SENSOR"
        "DeployFalconContainer=$DEPLOY_FALCON_CONTAINER"
        "VpcCidr=$VPC_CIDR"
        "ResourcePrefix=$RESOURCE_PREFIX"
        "ResourceSuffix=$RESOURCE_SUFFIX"
    )
    
    # Add organization-specific parameters if needed
    if [[ "$SCOPE" == "organization" ]]; then
        param_overrides+=("Regions=$REGIONS")
        param_overrides+=("OUs=$OUS")
        param_overrides+=("OrganizationId=$ORGANIZATION_ID")
    fi
    
    # Add permissions boundary if specified
    if [[ -n "$PERMISSIONS_BOUNDARY" ]]; then
        param_overrides+=("PermissionsBoundary=$PERMISSIONS_BOUNDARY")
    fi
    
    if aws cloudformation deploy \
        --template-file cloudformation.yaml \
        --stack-name "$STACK_NAME" \
        --parameter-overrides "${param_overrides[@]}" \
        --capabilities CAPABILITY_NAMED_IAM \
        --region "$REGION"; then
        log "SUCCESS" "CloudFormation deployment completed successfully"
        show_deployment_info "cloudformation"
    else
        log "ERROR" "CloudFormation deployment failed"
        exit 1
    fi
}


# Function to show deployment information
show_deployment_info() {
    local deployment_type=$1
    
    log "INFO" "=== Deployment Information ==="
    log "INFO" "Deployment Type: $deployment_type"
    log "INFO" "Container Image: alpine/k8s:1.28.4 (public)"
    log "INFO" "Region: $REGION"
    log "INFO" "Stack/Resource Name: $STACK_NAME"
    
    if [[ "$deployment_type" == "cloudformation" ]]; then
        log "INFO" "CloudFormation Stack: $STACK_NAME"
        log "INFO" "Getting stack outputs..."
        aws cloudformation describe-stacks \
            --stack-name "$STACK_NAME" \
            --query 'Stacks[0].Outputs' \
            --region "$REGION" \
            --output table
    fi
    
    log "INFO" "=== Next Steps ==="
    log "INFO" "1. The solution is now deployed and ready"
    log "INFO" "2. When you create an EKS cluster, the EventBridge rule will automatically trigger"
    log "INFO" "3. The CrowdStrike Falcon Operator will be installed automatically"
    log "INFO" "4. Monitor logs in CloudWatch: /ecs/crowdstrike-falcon-eks-protection"
    log "INFO" "5. Check ECS tasks for execution status"
}

# Function to check deployment status
check_status() {
    log "INFO" "Checking deployment status..."
    
    # Check if CloudFormation stack exists
    if aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" &>/dev/null; then
        log "INFO" "CloudFormation stack '$STACK_NAME' exists"
        aws cloudformation describe-stacks \
            --stack-name "$STACK_NAME" \
            --query 'Stacks[0].{StackStatus:StackStatus,CreatedTime:CreationTime,UpdatedTime:LastUpdatedTime}' \
            --region "$REGION" \
            --output table
    else
        log "WARNING" "CloudFormation stack '$STACK_NAME' not found"
    fi
    
}

# Main execution
main() {
    log "INFO" "CrowdStrike Falcon EKS Protection - Deployment"
    log "INFO" "Using public alpine/k8s:1.28.4 image (no build required)"
    
    case "${1:-}" in
        "cloudformation")
            validate_prerequisites
            deploy_cloudformation
            ;;
        "status")
            check_status
            ;;
        "--help"|"-h"|"help"|"")
            show_usage
            ;;
        *)
            log "ERROR" "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
}

# Show usage or run main
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
