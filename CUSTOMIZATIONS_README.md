## 📝 Customization

### Modify Falcon Deployment Manifest

To make changes to your Falcon Deployment manifest:

**Note:** When making changes to the manifest, the following lines must be left unchanged to ensure the script can set these values:
```yaml
          deployNodeSensor: FINAL_DEPLOY_NODE_SENSOR
          deployContainerSensor: FINAL_DEPLOY_CONTAINER
          deployAdmissionController: FINAL_DEPLOY_FALCON_ADMISSION
          deployImageAnalyzer: FINAL_DEPLOY_FALCON_IMAGE_ANALYZER 
```
These values can be modified using the environment variables on the ECS Task.

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
          deployAdmissionController: FINAL_DEPLOY_FALCON_ADMISSION # DO NOT CHANGE
          deployImageAnalyzer: FINAL_DEPLOY_FALCON_IMAGE_ANALYZER # DO NOT CHANGE

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
