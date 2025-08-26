## 📝 Customization

### Modify Falcon Deployment Manifest

To make changes to your Falcon Deployment manifest:

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

          # Component deployment flags, DO NOT MODIFY
          deployNodeSensor: SET_NODE_SENSOR
          deployContainerSensor: SET_CONTAINER_SENSOR
          deployAdmissionController: SET_FALCON_ADMISSION
          deployImageAnalyzer: SET_IMAGE_ANALYZER

          # Set Daemonset Backend
          falconNodeSensor:
            node:
              backend: ${Backend}

          # Disable Default Injection of Container Sensor
          falconContainerSensor:
            injector:
              disableDefaultNamespaceInjection: true
              disableDefaultPodInjection: true

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
      Value: "https://raw.githubusercontent.com/CrowdStrike/aws-eks-protection/refs/heads/main/event_handler.sh"

  SetupScriptParameter:
    Type: AWS::SSM::Parameter
    Properties:
      Name: /crowdstrike/falcon-eks-protection/setup-script-url
      Type: String
      Description: GitHub URL for cluster setup script
      Value: "https://raw.githubusercontent.com/CrowdStrike/aws-eks-protection/refs/heads/main/setup_cluster.py"

  DeployScriptParameter:
    Type: AWS::SSM::Parameter
    Properties:
      Name: /crowdstrike/falcon-eks-protection/deploy-script-url
      Type: String
      Description: GitHub URL for deploy operator script
      Value: "https://raw.githubusercontent.com/CrowdStrike/aws-eks-protection/refs/heads/main/deploy_operator.sh"
```

2. Redeploy the CloudFormation stack

### Custom Container Image

To use a different container image:

1. Update the container image in task definition:
```yaml
ContainerDefinitions:
  - Image: your-custom-image:tag
```

**Note**: Ensure the image contains required tools: kubectl, aws-cli, curl, bash

2. Redeploy the CloudFormation stack

### Environment Variable Extensions

Add custom environment variables to the ECS task definition:
```yaml
Environment:
  - Name: TIMEOUT
    Value: "600"
  - Name: FALCON_OPERATOR_NAMESPACE
    Value: "custom-namespace"
```
