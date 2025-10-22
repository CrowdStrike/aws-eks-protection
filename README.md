![CrowdStrike Logo (Light)](https://raw.githubusercontent.com/CrowdStrike/.github/main/assets/cs-logo-light-mode.png#gh-light-mode-only)
![CrowdStrike Logo (Dark)](https://raw.githubusercontent.com/CrowdStrike/.github/main/assets/cs-logo-dark-mode.png#gh-dark-mode-only)

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
- 🎯 **Intelligent Sensor Selection**: Auto-detects cluster type and deploys appropriate sensors
- 🔒 **Secure**: API credentials stored in AWS Secrets Manager
- 📊 **Observable**: Complete CloudWatch logging with structured output
- 🌐 **Self-Contained Infrastructure**: Creates own VPC and networking
- 🏢 **Organization Support**: Deploy across AWS Organizations or single accounts

## ⚙️ How It Works

### 1. Infrastructure Setup
- **Self-Contained**: ECS Task runs in a dedicated VPC, subnets, NAT Gateway, and security groups
- **Container Image**: Uses public `amazon/aws-cli:2.15.30` image 
  - pre-installed tools: aws-cli
  - installs dependencies and pulls latest scripts from GitHub at runtime

### 2. Script Details
- **Event Handler**: Retrieves event data and configures ECS Task environment with required variables such as Cluster name, AWS Account ID, AWS Region
- **Setup Script**: Adds the ECS Task ARN to the EKS Cluster Access entries and the ECS Task VPC NAT IP address to the inbound CIDR list
- **Deploy Script**: Determines sensor type and apply Falcon Operator and Falcon Deployment Components using kubectl
- **Falcon Deployment**: YAML manifest template with dynamic parameter substitution stored in Parameter Store

### 3. Enhanced Event-Driven Architecture
- **EventBridge Rule**: Triggers when EKS clusters are created
- **Centralized Custom EventBus**: EventBridge Rules across the AWS Organization target this to allow for a single, centralized ECS Cluster.
- **ECS Fargate Task**: Invoked via EventBridge rule to run EKS Protection Scripts

### 4. Intelligent Sensor Deployment
- **Auto Mode**: Set `SensorType` = `auto` to automatically select appropriate sensors based on cluster type
  - Fargate-only clusters → Falcon Container sensor
  - Node-based clusters → Falcon Node sensor
  - Hybrid clusters → Falcon Node sensor & Falcon Container sensor
- **Manual Override**: Set `SensorType` to `node`, `container` or `both` to force a sensor type and bypass cluster type detection

### Container Sensor Injection Behavior
- Container sensor injection disabled by default
- `falcon-sidecar-injector` pods may run but only inject the container sensor if Fargate pods are labeled.
- This prevents duplicative sensors when running hybrid clusters (EC2 and Fargate) and allows both `DEPLOY_FALCON_NODE_SENSOR = true` and `DEPLOY_FALCON_CONTAINER = true`.

**NOTE: Use the following label to inject Falcon Container to your pods**  
 `falcon.crowdstrike.com/inject: "true"`

## 📊 Event-Driven Architecture

```
EKS Cluster Creation → EventBridge → Centralized EventBus → ECS Fargate Task
                           ↓                                     ↓
                     Get cluster name,                      amazon/aws-cli:2.15.30
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

## 📋 CloudFormation Parameters

The following table describes all parameters available when deploying the CloudFormation template:

| Parameter | Type | Default | Description | Allowed Values |
|-----------|------|---------|-------------|----------------|
| **Deployment Configuration** |
| `Scope` | String | `organization` | Whether to deploy across the organization or locally to the current AWS account | `organization`, `local account` |
| `Regions` | List\<String\> | _(empty)_ | Which regions to deploy EventBridge rules | |
| `OUs` | List\<String\> | _(empty)_ | Which OUs to onboard if Scope = organization. If onboarding the entire organization, use the root OU (r-******) | |
| `OrganizationId` | String | _(empty)_ | Your AWS Organization Id if Scope = organization | |
| `DelegatedAdmin` | String | `false` | Indicates whether this is a Delegated Administrator account | `true`, `false` |
| `PermissionsBoundary` | String | _(empty)_ | The name of the policy used to set the permissions boundary for IAM roles | |
| **Network Configuration** |
| `VpcCidr` | String | `10.0.0.0/22` | CIDR block for the VPC | |
| **Falcon API Credentials** |
| `FalconClientId` | String | _(required)_ | CrowdStrike Falcon Client ID | |
| `FalconClientSecret` | String | _(required)_ | CrowdStrike Falcon Client Secret | |
| `FalconCloud` | String | _(required)_ | CrowdStrike Falcon Cloud | `us-1`, `us-2`, `eu-1`, `us-gov-1`, `us-gov-2` |
| **Falcon Operator Options** |
| `DeployFalconAdmission` | String | `true` | Deploy Falcon Kubernetes Admission Controller | `true`, `false` |
| `DeployFalconImageAnalyzer` | String | `true` | Deploy Falcon Image Analyzer (requires additional API permissions) | `true`, `false` |
| `Backend` | String | `kernel` | Backend for Daemonset (node) sensor | `kernel`, `bpf` |
| `FalconSensorType` | String | `auto` | Which Falcon Sensor to deploy. auto will determine sensor based on cluster type (Recommended) | `auto`, `both`, `node`, `container` |
| `KubectlVersion` | String | `1.33.0` | Version of kubectl to install | |
| **Resource Names** |
| `ResourcePrefix` | String | `crowdstrike-eks-protection` | The prefix to be added to all resource names | |
| `ResourceSuffix` | String | _(empty)_ | The suffix to be added to all resource names | |

### Parameter Notes

- **Falcon API Credentials**: All three Falcon parameters (`FalconClientId`, `FalconClientSecret`, `FalconCloud`) are required for deployment
- **Organization Deployment**: When `Scope` is set to `organization`, you must also provide `OrganizationId` and `OUs`
- **Sensor Type Auto-Detection**: When `FalconSensorType` is set to `auto`, the system automatically selects the appropriate sensor based on cluster configuration
- **kubectl Version Compatibility**: kubectl version 1.33.0 is compatible with Kubernetes versions 1.31-1.34. Ensure kubectl version compatibility with your target Kubernetes cluster versions.  Typically the kubectl version should be within 1 minor and 1 major version of your kubernetes cluster version.
- **Secure Parameters**: `FalconClientId` and `FalconClientSecret` are marked as `NoEcho` and will be stored securely in AWS Secrets Manager

## 📄 Support and License

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

### Support

This is a community-driven, open source project. While it is not an official CrowdStroke product, it is actively maintained by CrowdStrike and supported in collaboration with the open source developer community.

For more information, please see our [SUPPORT](SUPPORT.md) file.
