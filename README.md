# CrowdStrike Falcon EKS Protection

An automated solution for deploying CrowdStrike Falcon Operator, Sensor, KAC and ImageAnalyzer to EKS clusters across your AWS Organization using event-driven architecture.

## Usage Guides

| Guide | Description |
|-------|-------------|
| [Deployment Guide](DEPLOYMENT_GUIDE_README.md) | Complete setup instructions, prerequisites, and deployment options for new installations |
| [Existing Cluster Guide](EXISTING_CLUSTER_README.md) | Manual deployment instructions for protecting existing EKS clusters |
| [Customization Guide](CUSTOMIZATIONS_README.md) | Advanced configuration options for modifying Falcon deployment manifests and scripts |


## ✨ Features

- 🚀 **Event-Driven Automation**: Automatically installs Falcon components when EKS clusters are created
- 🐳 **No Build Dependencies**: Uses public `alpine/k8s:1.28.4` container image
- 🎯 **Intelligent Sensor Selection**: Auto-detects cluster type and deploys appropriate sensors
- 🔒 **Secure**: API credentials stored in AWS Secrets Manager
- 📊 **Observable**: Complete CloudWatch logging with structured output
- 🌐 **Self-Contained Infrastructure**: Creates own VPC and networking
- 🏢 **Organization Support**: Deploy across AWS Organizations or single accounts

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

## ⚙️ How It Works

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

### Core Falcon Deployment Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `DEPLOY_FALCON_ADMISSION` | `true` | Deploy Admission Controller |
| `DEPLOY_FALCON_IMAGE_ANALYZER` | `true` | Deploy Image Analyzer |
| `DEPLOY_FALCON_NODE_SENSOR` | `true` | Deploy Node Sensor (EC2) |
| `DEPLOY_FALCON_CONTAINER` | `true` | Deploy Container Sensor (Fargate) |

### Fargate Compatability

If using Fargate or plan to add Fargate to your clusters in the future,  
please ensure `DEPLOY_FALCON_CONTAINER = true`

**Injection Behavior**
- Container sensor injection disabled by default
- `falcon-sidecar-injector` pods will run but only inject the container sensor if Fargate pods are labeled.
- This prevents duplicative sensors when running hybrid clusters (EC2 and Fargate) and allows you to set both `DEPLOY_FALCON_NODE_SENSOR = true` and `DEPLOY_FALCON_CONTAINER = true`

**Use the following label to inject Falcon Container**  
 `falcon.crowdstrike.com/inject: "true"`


## 🔐 Security Features

- **IAM Roles**: Separate execution and task roles with minimal permissions
- **Secrets Manager**: API credentials stored securely, never in logs
- **VPC Deployment**: ECS tasks run in private subnets
- **No Public IP/Ingress on Tasks**: All communication through NAT
- **Script Integrity**: Scripts pulled from trusted GitHub repository

## 📄 Support and License

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

### Support

This is a community-driven, open source project. While it is not an official CrowdStroke product, it is actively maintained by CrowdStrike and supported in collaboration with the open source developer community.

For more information, please see our [SUPPORT](SUPPORT.md) file.
