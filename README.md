# CrowdStrike Falcon EKS Protection

An automated solution for deploying CrowdStrike Falcon Operator, Sensor, KAC and ImageAnalyzer to EKS clusters across your AWS Organization using event-driven architecture.

## ✨ Features

- 🚀 **Event-Driven Automation**: Automatically installs Falcon components when EKS clusters are created
- 🐳 **No Build Dependencies**: Uses public `alpine/k8s:1.28.4` container image
- 🎯 **Intelligent Sensor Selection**: Auto-detects cluster type and deploys appropriate sensors
- 🔒 **Secure**: API credentials stored in AWS Secrets Manager
- 📊 **Observable**: Complete CloudWatch logging with structured output
- 🌐 **Self-Contained Infrastructure**: Creates own VPC and networking
- 🏢 **Organization Support**: Deploy across AWS Organizations or single accounts

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
export ORGANIZATION_ID="o-xxxxxxxxxx"            # AWS Organization ID
export REGIONS="us-west-2,us-east-1"            # Comma-separated list of regions
export OUS="r-xxxx,ou-xxxx-xxxxxxxx"            # Organization Units

# Network configuration
export VPC_CIDR="10.0.0.0/22"                   # VPC CIDR block (default: 10.0.0.0/22)

# Falcon component deployment flags
export DEPLOY_FALCON_ADMISSION="true"            # Deploy Falcon Kubernetes Admission Controller
export DEPLOY_FALCON_IMAGE_ANALYZER="false"      # Deploy Falcon Image Analyzer
export DEPLOY_FALCON_NODE_SENSOR="auto"          # auto, true, false
export DEPLOY_FALCON_CONTAINER="auto"            # auto, true, false

# Resource naming
export RESOURCE_PREFIX="crowdstrike-eks-protection"
export RESOURCE_SUFFIX=""
export PERMISSIONS_BOUNDARY=""                   # IAM permissions boundary (optional)
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
├── cloudformation.yaml                # Complete CloudFormation template
├── deploy.sh                          # CloudFormation deployment script
├── event_handler.sh                   # Retrieves event data and configures ECS Task environment
├── setup_cluster.py                   # Updates cluster access and network config to ensure secure communication
├── deploy_operator.sh                 # Deploys Falcon Operator and Deployment components
└── README.md                          # This documentation
```

## 🔧 How It Works

### 1. Infrastructure Setup
- **Self-Contained**: ECS Task runs in a dedicated VPC, subnets, NAT Gateway, and security groups
- **Container Image**: Uses public `alpine/k8s:1.28.4` image 
  - pre-installed tools: kubectl, aws-cli, helm, bash, curl, jq, eksctl
  - pulls latest scripts from GitHub at runtime

### 2. Script Details
- **Event Handler**: Retrieves event data and configures ECS Task environment with required variables such as Cluster name, AWS Account ID, AWS Region
- **Setup Script**: Adds the ECS Task ARN to the EKS Cluster Access entries and the ECS Task VPC NAT IP address to the inbound CIDR list
- **Deploy Script**: Determines sensor type and apply Falcon Operator and Falcon Deployment Components using kubectl
- **Falcon Deployment**: YAML manifest template with dynamic parameter substitution stored in Parameter Store

### 3. Enhanced Event-Driven Architecture
- **EventBridge Rule**: Triggers when EKS clusters are created
- **Centralized Custom EventBus**: EventBridge Rules across the AWS Organization target this to allow for a single, centralized ECS Cluster.
- **ECS Fargate Task**: Invoked via EventBridge rule

### 4. Intelligent Sensor Deployment
- **Auto Mode**: Automatically selects appropriate sensors based on cluster type
  - Fargate-only clusters → FalconContainer sensor
  - Node-based clusters → FalconNodeSensor
  - Hybrid clusters → FalconNodeSensor (preferred)
- **Manual Override**: Explicit control via environment variables

## 📊 Event-Driven Architecture

```
EKS Cluster Creation → EventBridge → Centralized EventBus → ECS Fargate Task
                           ↓                                     ↓
                     Get cluster name,                      alpine/k8s:1.28.4
                     region, account Id                     (in private VPC)
                                                                 ↓
                                                            Secrets Manager
                                                            (Falcon API credentials)
                                                                 ↓
                                                            GitHub Repository
                                                            (curl latest scripts)
                                                                 ↓
                                                            Parameter Store
                                                            (Falcon Deployment manifest)
                                                                 ↓
                                                            Apply Falcon Operator Deployment
                                                            (with auto-detection)
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
- **No Public IP/Ingress on Tasks**: All communication through NAT
- **Script Integrity**: Scripts pulled from trusted GitHub repository

## 🚀 Deployment

### CloudFormation Deployment (Recommended)

```bash
# Using the deployment script (recommended)
./deploy.sh cloudformation

# Or directly with AWS CLI - Local Account Deployment
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

## 📝 Customization

### Modify Falcon Deployment Manifest

To make changes to your Falcon Deployment manifest:

**Note:** When making changes to the manifest, the following lines must be left unchanged to ensure the script can set the Sensor Type when detecting the cluster:
```yaml
          deployNodeSensor: FINAL_DEPLOY_NODE_SENSOR
          deployContainerSensor: FINAL_DEPLOY_CONTAINER
```

1. Update the parameter value in the CloudFormation template:
```yaml
  FalconDeploymentParameter:
    Type: AWS::SSM::Parameter
    Properties:
      Name: /crowdstrike/falcon-eks-protection/falcon-deployment-manifest
      Type: String
      Description: CrowdStrike FalconDeployment YAML manifest
      Value: !Sub | # Modify below
        apiVersion: falcon.crowdstrike.com/v1alpha1
        kind: FalconDeployment
        metadata:
          name: falcon-deployment
          namespace: default
        spec:
          # Use Kubernetes secret for API credentials
          falconSecret:
            enabled: true
            namespace: default
            secretName: falcon-api-secret
          
          # Falcon API configuration
          falcon_api:
            cloud_region: ${FalconCloud}
          
          # Component deployment flags (will be updated by script based on cluster type)
          deployNodeSensor: FINAL_DEPLOY_NODE_SENSOR  # DO NOT CHANGE
          deployContainerSensor: FINAL_DEPLOY_CONTAINER  # DO NOT CHANGE
          deployAdmissionController: ${DeployFalconAdmission}
          deployImageAnalyzer: ${DeployFalconImageAnalyzer}
```

### Custom Deployment Scripts

To use your own fork or repository:

1. Update the parameter values in the CloudFormation template:
```yaml
EventHandlerParameter:
    Type: AWS::SSM::Parameter
    Properties:
      Name: /crowdstrike/falcon-eks-protection/handler-script-url
      Type: String
      Description: GitHub URL for event handler script
      Value: "https://raw.githubusercontent.com/CrowdStrike/aws-eks-protection/refs/heads/rp-refactor-for-ecs/event_handler.sh"

  SetupScriptParameter:
    Type: AWS::SSM::Parameter
    Properties:
      Name: /crowdstrike/falcon-eks-protection/setup-script-url
      Type: String
      Description: GitHub URL for cluster setup script
      Value: "https://raw.githubusercontent.com/CrowdStrike/aws-eks-protection/refs/heads/rp-refactor-for-ecs/setup_cluster.py"

  DeployScriptParameter:
    Type: AWS::SSM::Parameter
    Properties:
      Name: /crowdstrike/falcon-eks-protection/deploy-script-url
      Type: String
      Description: GitHub URL for deploy operator script
      Value: "https://raw.githubusercontent.com/CrowdStrike/aws-eks-protection/refs/heads/rp-refactor-for-ecs/deploy_operator.sh"
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

## 📄 Support and License

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

### Support

This is a community-driven, open source project. While it is not an official CrowdStroke product, it is actively maintained by CrowdStrike and supported in collaboration with the open source developer community.

For more information, please see our [SUPPORT](SUPPORT.md) file.
