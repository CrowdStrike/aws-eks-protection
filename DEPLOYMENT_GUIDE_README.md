# CrowdStrike Falcon EKS Protection - Deployment Guide

## 🛠 Prerequisites

1. **AWS CLI** configured with appropriate permissions
2. **CrowdStrike Falcon API Credentials** with required permissions:
   - `Falcon Images Download: Read`
   - `Sensor Download: Read`

## 🚀 Quick Start Deployment

### 1. Set Required Environment Variables

```bash
export AWS_REGION="us-west-2"
export FALCON_CLIENT_ID="your-client-id"
export FALCON_CLIENT_SECRET="your-client-secret"
export FALCON_CLOUD="us-1"                       # us-1, us-2, eu-1, us-gov-1, us-gov-2
```

### 2. Set Optional Configuration Variables

```bash
# Deployment scope
export SCOPE="local account"                     # "local account" or "organization"

# Organization deployment (required if SCOPE=organization)
export ORGANIZATION_ID="o-xxxxxxxxxx"           # AWS Organization ID
export REGIONS="us-west-2,us-east-1"            # Comma-separated list of regions
export OUS="r-xxxx,ou-xxxx-xxxxxxxx"            # Organization Units

# Network configuration
export VPC_CIDR="10.0.0.0/22"                   # VPC CIDR block (default: 10.0.0.0/22)

# Falcon component deployment flags
export DEPLOY_FALCON_ADMISSION="true"            # Deploy Falcon Kubernetes Admission Controller
export DEPLOY_FALCON_IMAGE_ANALYZER="true"       # Deploy Falcon Image Analyzer
export DEPLOY_FALCON_NODE_SENSOR="auto"          # auto, true, false
export DEPLOY_FALCON_CONTAINER="auto"            # auto, true, false

# Resource naming
export RESOURCE_PREFIX="crowdstrike-eks-protection"
export RESOURCE_SUFFIX=""                        # Suffix for Resource Names (optional)
export PERMISSIONS_BOUNDARY=""                   # IAM permissions boundary (optional)
export STACK_NAME="crowdstrike-falcon-eks-protection"
```

### 3. Deploy CloudFormation via Script

```bash
./deploy.sh cloudformation
```

### 4. Check Deployment Status

```bash
./deploy.sh status
```

## 🚀 No Script - CLI Deployment

```bash
# Local Account Deployment
aws cloudformation deploy \
  --template-file cloudformation.yaml \
  --stack-name crowdstrike-falcon-eks-protection \
  --parameter-overrides \
    Scope="local account" \
    FalconClientId=your-client-id \
    FalconClientSecret=your-client-secret \
    FalconCloud=us-1 \
    VpcCidr=10.0.0.0/22 \
    DeployFalconAdmission=true \
    DeployFalconImageAnalyzer=false \
    DeployFalconNodeSensor=auto \
    DeployFalconContainer=auto \
    ResourcePrefix=crowdstrike-eks-protection \
  --capabilities CAPABILITY_NAMED_IAM

# Organization-Wide Deployment
aws cloudformation deploy \
  --template-file cloudformation.yaml \
  --stack-name crowdstrike-falcon-eks-protection \
  --parameter-overrides \
    Scope=organization \
    OrganizationId=o-xxxxxxxxxx \
    Regions="us-west-2,us-east-1" \
    OUs="r-xxxx,ou-xxxx-xxxxxxxx" \
    FalconClientId=your-client-id \
    FalconClientSecret=your-client-secret \
    FalconCloud=us-1 \
    VpcCidr=10.0.0.0/22 \
  --capabilities CAPABILITY_NAMED_IAM
```

## 🔍 Monitoring and Troubleshooting

### Get CloudFormation Stack Outputs

CloudFormation stack outputs provide the resource Ids you need for various monitoring tasks.

```bash
# List stack outputs
aws cloudformation describe-stacks --stack-name STACK_NAME --query 'Stacks[0].Outputs[*].[OutputKey,OutputValue]' --output table
```

### CloudWatch Logs

Monitor execution in CloudWatch Logs:
- **Log Group**: `/ecs/crowdstrike-falcon-eks-protection`
- **Log Stream**: `ecs/falcon-eks-protection/{task-id}`

### ECS Task Monitoring

```bash
# Get cluster status
aws ecs describe-clusters --clusters CLUSTER_ARN or NAME --query 'clusters[0].status' --output text

# List running tasks
aws ecs list-tasks --cluster CLUSTER_ARN or NAME

# Describe specific task
aws ecs describe-tasks --cluster CLUSTER_ARN or NAME --tasks TASK_ARN

# Check task logs
aws logs get-log-events --log-group-name /ecs/crowdstrike-falcon-eks-protection --log-stream-name STREAM_NAME
```

### EventBridge Rule Status

```bash
# Verify rule is enabled
aws events describe-rule --name RULE_NAME

# Check rule targets
aws events list-targets-by-rule --rule RULE_NAME
```

## 🚨 Common Issues and Solutions

### 1. Task Fails to Start

**Symptoms**: ECS task stops immediately or fails to start

**Solutions**:
- Verify IAM roles haven't been modified or removed
- Confirm Secrets Manager secret hasn't been modified or removed
- Check CloudWatch logs for detailed error messages
- Validate task definition resource requirements (CPU/Memory)
- Ensure Task is launched in the correct VPC and VPC components haven't been modified or removed

### 2. Script Download Fails

**Symptoms**: "Failed to download script from GitHub"

**Solutions**:
- Ensure Task is launched in the correct VPC and VPC components haven't been modified or removed
- Verify GitHub URLs in parameter store are correct

### 3. Kubernetes Connection Issues

**Symptoms**: "Unable to connect to Kubernetes cluster"

**Solutions**:
- Verify EKS cluster is in ACTIVE state
- Check EKS Cluster Access and Network config
- Wait for cluster to be fully available

### 4. Falcon Operator Installation Fails

**Symptoms**: Operator pods fail to start or create

**Solutions**:
- Verify CrowdStrike API credentials are correct
- Check API key has required permissions
- Ensure cluster has IAM OIDC provider configured
- Validate cluster has sufficient resources

### 5. Sensor Selection Issues

**Symptoms**: Wrong sensor type deployed or no sensors

**Solutions**:
- Check cluster type detection logic in logs
- Verify DEPLOY_FALCON_NODE_SENSOR and DEPLOY_FALCON_CONTAINER settings
- Ensure cluster has appropriate node groups or Fargate profiles

## 🔄 Updates and Maintenance

### Disabling the Solution
If for any reason you want to disable or "pause" the event triggers for this solution you only need to disable one EventBridge rule which will effectively cut-off communication from EventBridge to the ECS Task:

1. Navigate to EventBridge in the AWS Account which maintains the ECS Task
2. Navigate to Rules
3. Select the custom EventBus
4. Select the rule <rule_name>
5. Click disable

### Updating the Solution

1. **Scripts**: Automatically uses latest from GitHub (no action required)
2. **CloudFormation Template**: Update and redeploy stack
3. **Configuration**: Modify environment variables and redeploy

### Version Compatibility

- **EKS**: Compatible with all supported EKS versions (1.25+)
- **Kubernetes**: Uses kubectl v1.28.4 (compatible with K8s 1.25-1.30)
- **AWS CLI**: Latest v2 included in alpine/k8s image
- **Falcon Operator**: Uses latest stable release
