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
- new_clusters_lambda_function
- eks_build.zip
- eventbridge_stackset.yml
4. In the CloudFormation console select create stack.
5. Choose Specify Template and upload init.yml
6. Fill out the parameters, click next.
7. Optional: change Stack Failure Options to Preserve successfully provisioned resources. This option will allow you to maintain the stack and update parameters in the event of a mistake.
7. Enabled the capabilities in the blue box and click submit.

## Organizations Setup
1. Download the contents of this repository.
2. Log in to the Management Account of your AWS Organization
3. Upload the following files to the root of an S3 Bucket.
- existing_clusters_lambda_function.zip 
- new_clusters_lambda_function
- eks_build.zip
- eventbridge_stackset.yml
- eventbridge_role_stackset.yml
4. In the CloudFormation console select create stack.
5. Choose Specify Template and upload init.yml
6. Fill out the parameters, click next.
7. Optional: change Stack Failure Options to Preserve successfully provisioned resources. This option will allow you to maintain the stack and update parameters in the event of a mistake.
7. Enabled the capabilities in the blue box and click submit.

## Parameter Details
| Parameter | Description | Options |
|---|---|---|
|EKSS3Bucket|S3 bucket name where code is located| |
|FalconClientId|Your Falcon API Client Id | |
|FalconClientSecret|Your Falcon API Client Secret | |
|FalconCID|Your Falcon CID | |
|CrowdStrikeCloud|Your Falcon Cloud | us1, us2, eu1|
|DockerAPIToken|Your Docker API Token | |
|AdministrationRoleARN|ARN for CloudFormation Administration Role | |
|ExecutionRoleName|Name of CloudFormation Execution Role | |
|Regions|List of regions to deploy | |
|Registry|Whether to source images from CrowdStrike or mirror to ECR | |
|Backend|Whether sensor backend is bpf or kernel | |
|EnableKAC|Whether to deploy Falcon Kubernetes Admission Controller | |
|CodeBuildProject|Name of CodeBuild Project | |
|CodeBuildRole|Name of CodeBuild execution role | |
|KubernetesUserName|Name of Kubernetes user | |

## Resources

- Init Stack 
1. Create Secret to manage Falcon API Credentials
2. Create EventBridge 
3. Create Lambda
4. Create CodeBuild
5. Create IAM Roles
- EventBridge Stackset
1. Create EventBridge Rules in each region

## How it works

## Questions or concerns?

If you encounter any issues or have questions about this repository, please open an [issue](https://github.com/CrowdStrike/aws-eks-protection/issues/new/choose).

## Statement of Support

CrowdStrike EKS Protection is a community-driven, open source project designed to provide options for onboarding AWS with CrowdStrike Cloud Security. While not a formal CrowdStrike product, this repo is maintained by CrowdStrike and supported in partnership with the open source community.