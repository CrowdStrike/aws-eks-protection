![](https://raw.githubusercontent.com/CrowdStrike/falconpy/main/docs/asset/cs-logo.png)

## CrowdStrike EKS Protection

This repository provides CloudFormation templates to automatically deploy the Falcon Sensor against EKS Clusters across an AWS Organization.

## Prerequisites

### Create Falcon API Client and Secret
1. In CrowdStrike Console, Navigate to API Clients and Keys page.
2. Click on "Add new API client".
3. Within the "Add new API client" modal, create a new client name and enable following scopes:
- 
4. Add new API Client
5. Save the CLIENT ID and SECRET displayed for your records. The SECRET will not be visible after this step.

## Single Account Setup
1. Download the contents of this repository.
2. Log in to your AWS Account
3. Upload the following files to the root of an S3 Bucket.
- existing_clusters_lambda_function.zip 
- new_clusters_lambda_function.zip
- eks_build.zip
- eks-eventbridge-stackset.yml
- eks-protection-stack.yml
- eks-target-roles-stackset.yml
4. In the CloudFormation console select create stack.
5. Choose Specify Template and upload init.yml
6. Fill out the parameters, click next.
7. Optional: change Stack Failure Options to Preserve successfully provisioned resources. This option will allow you to maintain the stack and update parameters in the event of a mistake.
7. Enable the capabilities in the blue box and click submit.

## Organizations Setup
1. Download the contents of this repository.
2. Log in to the Management Account or Delegated Administrator of your AWS Organization
3. Upload the following files to the root of an S3 Bucket.
- existing_clusters_lambda_function.zip 
- new_clusters_lambda_function.zip
- eks_build.zip
- eks-eventbridge-stackset.yml
- eks-protection-stack.yml
- eks-target-roles-stackset.yml
4. In the CloudFormation console select create stack.
5. Choose Specify Template and upload init.yml
6. Fill out the parameters, click next.
7. Optional: change Stack Failure Options to Preserve successfully provisioned resources. This option will allow you to maintain the stack and update parameters in the event of a mistake.
7. Enable the capabilities in the blue box and click submit.

## How it works
This solution automatically deploys the Falcon Sensor against your EKS Clusters using the following workflow:

- New Cluster
1. New cluster event triggers lambda
2. Lambda checks if cluster has EKS API authentication mode enabled
3. If yes Lambda triggers CodeBuild
4. CodeBuild checks for Active Status of cluster
5. Once active, Code Build adds Access policy to allow IAM Role to manage cluster
6. CodeBuild gets latest Falcon Images and pushes to ECR
7. CodeBuild configures yaml files for deployment
8. Code Build installs Sensors

**Note:** The SideCar (container) sensor injection is disabled by default to prevent duplicate sensors running on hybrid (Fargate & EC2) environments.  To deploy SideCar sensor, please annotate your pods and/or namespaces to enable injection.  For more info see: https://github.com/CrowdStrike/falcon-operator/blob/main/docs/resources/container/README.md

- Existing Clusters
1. Launching the CloudFormation Stack triggers lambda
2. Lambda generates list of EKS Clusters in the environment
3. Lambda checks if each cluster has Fargate
4. Lambda checks if cluster has EKS API authentication mode enabled
5. If yes Lambda triggers CodeBuild
6. CodeBuild checks for Active Status of cluster
7. Code Build adds Access policy to allow IAM Role to manage cluster
8. CodeBuild gets latest Falcon Images and pushes to ECR
9. CodeBuild configures yaml files for deployment
10. Code Build installs Sensors

## Questions or concerns?

If you encounter any issues or have questions about this repository, please open an [issue](https://github.com/CrowdStrike/aws-eks-protection/issues/new/choose).

## Statement of Support

CrowdStrike EKS Protection is a community-driven, open source project designed to provide options for onboarding AWS with CrowdStrike Cloud Security. While not a formal CrowdStrike product, this repo is maintained by CrowdStrike and supported in partnership with the open source community.