# CrowdStrike Falcon EKS Protection - Existing Cluster Deployment

This guide explains how to manually deploy CrowdStrike Falcon protection to specific existing EKS clusters using the ECS infrastructure created by this solution.

## 🎯 Overview

Once your CrowdStrike Falcon EKS Protection solution is deployed, you can manually trigger ECS tasks to deploy Falcon components to any existing EKS cluster without waiting for an EventBridge event. This is useful for:

- **Deploying to existing clusters** that were created before this solution was deployed
- **Re-deploying after failures** or configuration changes
- **Testing deployments** on specific clusters
- **Targeted deployments** during maintenance windows

## 🏗️ How It Works

The deployed solution creates:
- **ECS Cluster**: `crowdstrike-eks-protection-cluster` (or with your custom prefix/suffix)
- **ECS Task Definition**: Contains all necessary tools and configurations
- **Private VPC**: Secure network environment for task execution
- **IAM Roles**: Permissions to access EKS clusters and Falcon APIs

When you manually run an ECS task, it:
1. Downloads the latest deployment scripts from GitHub
2. Retrieves Falcon API credentials from AWS Secrets Manager
3. Configures access to the target EKS cluster
4. Deploys Falcon Operator and components using the same logic as the automated solution

## 🚀 Quick Start

### Prerequisites

- The CrowdStrike Falcon EKS Protection solution must be already deployed
- AWS CLI configured with appropriate permissions
- Target EKS cluster must be in `ACTIVE` state

### Get CloudFormation Stack Outputs

CloudFormation stack outputs provide the resource Ids you need for various tasks.

```bash
# List stack outputs
aws cloudformation describe-stacks --stack-name STACK_NAME --query 'Stacks[0].Outputs[*].[OutputKey,OutputValue]' --output table
```


### Manual Deployment

```bash
# Set your target cluster details
export TARGET_CLUSTER_NAME="my-eks-cluster"
export TARGET_AWS_REGION="us-west-2"  
export TARGET_ACCOUNT_ID="123456789012"

# Get the ECS cluster and task definition names (adjust prefix if customized)
export ECS_CLUSTER_NAME="crowdstrike-eks-protection-cluster"
export TASK_DEFINITION="crowdstrike-eks-protection-cluster:1"
export SUBNET_ID="subnet-xxxxxx"
export SECURITY_GROUP="sg-xxxxxx"

# Run the ECS task
aws ecs run-task \
  --cluster $ECS_CLUSTER_NAME \
  --task-definition $TASK_DEFINITION \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[$SUBNET_ID],securityGroups=[$SECURITY_GROUP],assignPublicIp=DISABLED}" \
  --overrides '{
    "containerOverrides": [
      {
        "name": "falcon-eks-protection",
        "environment": [
          {"name": "EKS_CLUSTER_NAME", "value": "'$TARGET_CLUSTER_NAME'"},
          {"name": "AWS_REGION", "value": "'$TARGET_AWS_REGION'"},
          {"name": "ACCOUNT_ID", "value": "'$TARGET_ACCOUNT_ID'"}
        ]
      }
    ]
  }'
```

## 🔧 Configuration Details

### Required Environment Variables

When manually running the ECS task, you must override these environment variables:

| Variable | Description | Example |
|----------|-------------|---------|
| `EKS_CLUSTER_NAME` | Name of the target EKS cluster | `my-prod-cluster` |
| `AWS_REGION` | AWS region where the cluster exists | `us-west-2` |
| `ACCOUNT_ID` | AWS account ID containing the cluster | `123456789012` |

### Optional Environment Variables

You can also override these variables to customize the deployment:

| Variable | Default | Description | Values |
|----------|---------|-------------|--------|
| `SENSOR_TYPE` | `auto` | Which Falcon Sensor Type to deploy. | `auto`, `both`, `container`, `node` |
| `DEPLOY_FALCON_ADMISSION` | `true` |  Whether to deploy the Falcon Admission Controller. | `true`, `false` |
| `DEPLOY_FALCON_IMAGE_ANALYZER` | `true` | Whether to deploy the Falcon Image Analyzer. | `true`, `false` |

## 📊 Monitoring Task Execution

### 1. Check Task Status

```bash
# Get task status
aws ecs describe-tasks \
    --cluster crowdstrike-eks-protection-cluster \
    --tasks TASK_ARN \
    --query 'tasks[0].lastStatus' \
    --output text
```

### 2. View CloudWatch Logs

```bash
# Stream logs in real-time
aws logs tail /ecs/crowdstrike-falcon-eks-protection --follow

# Get specific log stream
aws logs describe-log-streams \
    --log-group-name /ecs/crowdstrike-falcon-eks-protection \
    --order-by LastEventTime \
    --descending \
    --max-items 1

# View logs for specific stream
aws logs get-log-events \
    --log-group-name /ecs/crowdstrike-falcon-eks-protection \
    --log-stream-name LOG_STREAM_NAME
```

### 3. Monitor Via AWS Console

1. Navigate to **ECS Console** → **Clusters** → `crowdstrike-eks-protection-cluster`
2. Click on **Tasks** tab to see running/stopped tasks
3. Click on a task ARN to view details and logs
4. Use **CloudWatch Console** → **Log groups** → `/ecs/crowdstrike-falcon-eks-protection`

## 🔍 Troubleshooting

### Common Issues

#### 1. Task Fails to Start
**Symptoms**: Task stops immediately with `STOPPED` status

**Solutions**:
```bash
# Check task exit code and reason
aws ecs describe-tasks \
    --cluster crowdstrike-eks-protection-cluster \
    --tasks TASK_ARN \
    --query 'tasks[0].stoppedReason'

# Common causes:
# - Network configuration issues (subnet/security group)
```

#### 2. Cannot Connect to EKS Cluster
**Symptoms**: Logs show "Unable to connect to Kubernetes cluster"

**Solutions**:
```bash
# Verify cluster is active
aws eks describe-cluster --name CLUSTER_NAME --region REGION

# Check cluster access entries
aws eks list-access-entries --cluster-name CLUSTER_NAME --region REGION

# Wait for cluster to be fully ready if recently created
```

#### 3. Cross-Account Access Issues
**Symptoms**: Permission denied errors for cross-account deployments

**Solutions**:
```bash
# Verify cross-account role exists
aws iam get-role --role-name crowdstrike-eks-protection-execution-role

# Check if task role can assume cross-account role
aws sts assume-role \
    --role-arn arn:aws:iam::TARGET_ACCOUNT:role/crowdstrike-eks-protection-execution-role \
    --role-session-name test-session
```

### Task Execution States

| State | Description | Action |
|-------|-------------|---------|
| `PENDING` | Task is being provisioned | Wait for task to start |
| `RUNNING` | Task is executing | Monitor logs for progress |
| `STOPPING` | Task is gracefully shutting down | Normal completion or error |
| `STOPPED` | Task completed or failed | Check exit code and logs |

### Log Locations
- **CloudWatch Logs**: `/ecs/crowdstrike-falcon-eks-protection`
- **Task Details**: ECS Console → Clusters → Tasks

### Verification Steps
After deployment, verify Falcon components are running:

```bash
# Update kubeconfig
aws eks update-kubeconfig --name CLUSTER_NAME --region REGION

# Check Falcon Operator
kubectl get namespace falcon-operator
kubectl get deployment -n falcon-operator

# Check Falcon Deployment
kubectl get falcondeployment -n default
kubectl describe falcondeployment falcon-deployment -n default
```

---

This manual ECS task approach provides a powerful way to deploy CrowdStrike Falcon protection to specific clusters while leveraging your existing automated infrastructure. The same deployment logic, security model, and monitoring capabilities apply whether triggered by events or run manually.
