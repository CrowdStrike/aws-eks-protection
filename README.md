# CrowdStrike Falcon EKS Protection

An automated solution for deploying CrowdStrike Falcon Operator to EKS clusters using event-driven architecture.

## ✨ Features

- 🚀 **Event-Driven Automation**: Automatically installs Falcon Operator when EKS clusters are created
- 🐳 **No Build Dependencies**: Uses public `alpine/k8s:1.28.4` container image
- 🎯 **Intelligent Sensor Selection**: Auto-detects cluster type and deploys appropriate sensors
- 🔒 **Secure**: API credentials stored in AWS Secrets Manager
- 📊 **Observable**: Complete CloudWatch logging and monitoring

## 🛠 Prerequisites

1. **AWS CLI** configured with appropriate permissions
2. **VPC and Private Subnets** for ECS deployment
3. **CrowdStrike Falcon API Credentials** with required permissions:
   - `Falcon Images Download: Read`
   - `Sensor Download: Read`

## 🚀 Quick Start

### 1. Set Required Environment Variables

```bash
export AWS_REGION="us-west-2"
export VPC_ID="vpc-xxxxxxxx"
export PRIVATE_SUBNET_IDS="subnet-xxxxx,subnet-yyyyy"
export FALCON_CLIENT_ID="your-client-id"
export FALCON_CLIENT_SECRET="your-client-secret"
export FALCON_CLOUD="us-1"                       # us-1, us-2, eu-1, us-gov-1, us-gov-2
```

### 2. Set Optional Configuration Variables

```bash
export DEPLOY_FALCON_ADMISSION="true"            # Deploy Falcon Kubernetes Admission Controller
export DEPLOY_FALCON_IMAGE_ANALYZER="false"      # Deploy Falcon Image Analyzer
export DEPLOY_FALCON_NODE_SENSOR="auto"          # auto, true, false
export DEPLOY_FALCON_CONTAINER="auto"            # auto, true, false
export STACK_NAME="crowdstrike-falcon-eks-protection"
```

### 3. Deploy with CloudFormation

```bash
./deploy.sh cloudformation
```

### 4. Check Deployment Status

```bash
./deploy.sh status
```

## 📁 File Structure

```
eks-protection/
├── cloudformation.yaml                 # Complete CloudFormation template
├── check_and_install.sh               # Main installation script (pulled from GitHub)
├── ecs-task-definition.json           # ECS task definition reference
├── deploy.sh                          # Deployment script
└── README.md                          # This documentation
```

## 🔧 How It Works

### 1. Container Image
- Uses public `alpine/k8s:1.28.4` image with pre-installed tools:
  - kubectl, aws-cli, helm, bash, curl, jq, eksctl
  - No build time or ECR dependency required

### 2. Script Management
- **Main Script**: `check_and_install.sh` is pulled directly from GitHub at runtime
- **Event Handler**: Small orchestration script stored in AWS Parameter Store
- **Falcon Deployment**: YAML manifest template with dynamic parameter substitution stored in AWS Parameter Store

### 3. Event-Driven Architecture
- **EventBridge Rule**: Triggers when EKS clusters are created
- **ECS Fargate Task**: Executes the installation automatically
- **Cluster Detection**: Auto-detects Fargate vs. Node-based clusters

### 4. Intelligent Sensor Deployment
- **Auto Mode**: Automatically selects appropriate sensors based on cluster type
  - Fargate-only clusters → FalconContainer sensor
  - Node-based clusters → FalconNodeSensor
  - Hybrid clusters → FalconNodeSensor (preferred)
- **Manual Override**: Explicit control via environment variables

## 📊 Architecture Flow

```
EKS Cluster Creation → EventBridge → ECS Fargate Task → Script Download → Falcon Installation
                                         ↓                      ↓
                           alpine/k8s:1.28.4 (public)    GitHub Repository
                                         ↓                      ↓
                              Secrets Manager           check_and_install.sh
                               (API credentials)        (latest version)
```

## 🎯 Configuration Options

### Core Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `FALCON_CLOUD` | `us-1` | CrowdStrike cloud region |
| `DEPLOY_FALCON_ADMISSION` | `true` | Deploy Admission Controller |
| `DEPLOY_FALCON_IMAGE_ANALYZER` | `false` | Deploy Image Analyzer |
| `DEPLOY_FALCON_NODE_SENSOR` | `auto` | Deploy Node Sensor |
| `DEPLOY_FALCON_CONTAINER` | `auto` | Deploy Container Sensor |

### Sensor Deployment Logic

| Cluster Type | Node Sensor | Container Sensor | Logic |
|--------------|-------------|------------------|-------|
| Fargate-only | ❌ | ✅ | Container sensor required for Fargate |
| Node-based | ✅ | ❌ | Node sensor preferred for EC2 instances |
| Hybrid | ✅ | ❌ | Node sensor covers both EC2 and Fargate |

## 🔐 Security Features

- **IAM Roles**: Separate execution and task roles with minimal permissions
- **Secrets Manager**: API credentials stored securely, never in logs
- **VPC Deployment**: ECS tasks run in private subnets
- **No Public IPs**: All communication through VPC endpoints or NAT
- **Script Integrity**: Scripts pulled from trusted GitHub repository

## 📋 CloudFormation Template Features

The `cloudformation.yaml` template includes:

- ✅ **ECS Infrastructure**: Cluster, task definition, security groups
- ✅ **IAM Security**: Execution and task roles with least privilege
- ✅ **Event Integration**: EventBridge rule for automatic triggering  
- ✅ **Secret Management**: Secure API credential storage
- ✅ **Parameter Store**: Configuration and script URL management
- ✅ **CloudWatch Logging**: Complete execution visibility
- ✅ **GitHub Integration**: Dynamic script downloading

## 🚀 Deployment

### CloudFormation Deployment (Recommended)

```bash
# Using the deployment script
./deploy.sh cloudformation

# Or directly with AWS CLI
aws cloudformation deploy \
  --template-file cloudformation.yaml \
  --stack-name crowdstrike-falcon-eks-protection \
  --parameter-overrides \
    VpcId=vpc-xxxxxxxx \
    PrivateSubnetIds="subnet-xxxxx\\,subnet-yyyyy" \
    FalconClientId=your-client-id \
    FalconClientSecret=your-client-secret \
    FalconCloud=us-1 \
    DeployFalconAdmission=true \
    DeployFalconImageAnalyzer=false \
    DeployFalconNodeSensor=auto \
    DeployFalconContainer=auto \
  --capabilities CAPABILITY_NAMED_IAM
```

### Parameter Validation

The deployment script automatically validates:
- ✅ AWS CLI configuration and credentials
- ✅ Required environment variables
- ✅ VPC and subnet accessibility  
- ✅ CrowdStrike cloud region values
- ✅ Boolean and enum parameter formats

## 🔍 Monitoring and Troubleshooting

### CloudWatch Logs

Monitor execution in CloudWatch Logs:
- **Log Group**: `/ecs/crowdstrike-falcon-eks-protection`
- **Log Stream**: `ecs/falcon-eks-protection/{task-id}`

### Key Log Messages to Monitor

```bash
# Successful execution indicators
"Connected to Kubernetes cluster"
"Falcon Operator installed and ready"  
"FalconDeployment applied successfully"

# Error indicators
"Unable to connect to Kubernetes cluster"
"Failed to install IAM OIDC provider"
"Invalid FALCON_CLOUD value"
```

### ECS Task Monitoring

```bash
# List running tasks
aws ecs list-tasks --cluster crowdstrike-falcon-eks-protection

# Describe specific task
aws ecs describe-tasks --cluster crowdstrike-falcon-eks-protection --tasks TASK_ARN

# Check task logs
aws logs get-log-events --log-group-name /ecs/crowdstrike-falcon-eks-protection --log-stream-name STREAM_NAME
```

### EventBridge Rule Status

```bash
# Verify rule is enabled
aws events describe-rule --name crowdstrike-falcon-eks-cluster-created

# Check rule targets
aws events list-targets-by-rule --rule crowdstrike-falcon-eks-cluster-created
```

## 🚨 Common Issues and Solutions

### 1. Task Fails to Start

**Symptoms**: ECS task stops immediately or fails to start

**Solutions**:
- Verify IAM execution role permissions
- Check VPC/subnet configuration allows internet access
- Confirm Secrets Manager access permissions
- Validate private subnet has NAT gateway or VPC endpoints

### 2. Script Download Fails

**Symptoms**: "Failed to download script from GitHub"

**Solutions**:
- Check internet connectivity from private subnets
- Verify GitHub repository URL is accessible
- Ensure curl/wget tools are available in container

### 3. Kubernetes Connection Issues

**Symptoms**: "Unable to connect to Kubernetes cluster"

**Solutions**:
- Verify EKS cluster is in ACTIVE state
- Check task IAM role has EKS permissions
- Ensure cluster is in same region as ECS task
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

### Updating the Solution

1. **Scripts**: Automatically updated from GitHub (no action required)
2. **CloudFormation Template**: Update and redeploy stack
3. **Configuration**: Modify environment variables and redeploy

### Version Compatibility

- **EKS**: Compatible with all supported EKS versions (1.25+)
- **Kubernetes**: Uses kubectl v1.28.4 (compatible with K8s 1.25-1.30)
- **AWS CLI**: Latest v2 included in alpine/k8s image
- **Falcon Operator**: Uses latest stable release

### Script Updates

The `check_and_install.sh` script is automatically pulled from GitHub, ensuring:
- ✅ Latest bug fixes and improvements
- ✅ Updated Falcon Operator compatibility
- ✅ Enhanced cluster detection logic
- ✅ New feature support

## 📝 Customization

### Custom GitHub Repository

To use your own fork or repository:

1. Update the `GitHubScriptParameter` value in CloudFormation template:
```yaml
GitHubScriptParameter:
  Type: AWS::SSM::Parameter
  Properties:
    Value: "https://raw.githubusercontent.com/YOUR_ORG/YOUR_REPO/main/check_and_install.sh"
```

2. Redeploy the CloudFormation stack

### Custom Container Image

To use a different container image:

1. Update the container image in task definition:
```yaml
ContainerDefinitions:
  - Image: your-custom-image:tag
```

2. Ensure the image contains required tools: kubectl, aws-cli, curl, bash

### Environment Variable Extensions

Add custom environment variables to the ECS task definition:
```yaml
Environment:
  - Name: CUSTOM_TIMEOUT
    Value: "600"
  - Name: FALCON_OPERATOR_NAMESPACE
    Value: "custom-namespace"
```

## 🤝 Contributing

To contribute improvements to this solution:

1. Fork the repository
2. Create a feature branch
3. Test changes thoroughly
4. Submit a pull request

## 📄 Support and License

This solution is provided as-is for CrowdStrike customers and partners. For support:

1. Check CloudWatch logs for execution details
2. Review ECS task status and configuration
3. Validate IAM permissions and network connectivity
4. Test CrowdStrike API credentials independently

For additional assistance, consult CrowdStrike documentation or support channels.
