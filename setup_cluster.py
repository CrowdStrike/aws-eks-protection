"""Setup EKS Cluster access for CrowdStrike EKS Protection"""
import os
import time
import logging
import boto3
import botocore

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)
logger = logging.getLogger(__name__)

AWS_REGION = os.environ['AWS_REGION']
SCOPE = os.environ['SCOPE']
EKS_CLUSTER_NAME = os.environ['EKS_CLUSTER_NAME']
ACCOUNT_ID = os.environ['ACCOUNT_ID']
SWITCH_ROLE = os.environ['SWITCH_ROLE']
NAT_IP = os.environ['NAT_IP']
TASK_ARN = os.environ['TASK_ARN']
PARTITION = os.environ['PARTITION']


def check_cluster(eks_client):
    """Get Cluster Details and Status"""
    cluster_details = eks_client.describe_cluster(
        name=EKS_CLUSTER_NAME
    )
    current_cidrs = cluster_details.get('cluster', {}).get('resourcesVpcConfig', {}).get('publicAccessCidrs')
    while 'ACTIVE' not in cluster_details.get('cluster', {}).get('status'):
        time.sleep(60)
        cluster_details = eks_client.describe_cluster(
            name=EKS_CLUSTER_NAME
        )
    logger.info('Cluster %s is now active', EKS_CLUSTER_NAME)
    return current_cidrs


def setup_cluster(eks_client, cidrs_list):
    """Add Access entries and IP COnfig to EKS Cluster"""
    if SCOPE == 'organization':
        arn = f'arn:{PARTITION}:iam::{ACCOUNT_ID}:role/{SWITCH_ROLE}'
    else:
        arn = TASK_ARN
    try:
        logger.info('Adding access entry for %s', EKS_CLUSTER_NAME)
        eks_client.create_access_entry(
            clusterName=EKS_CLUSTER_NAME,
            principalArn=arn,
            username='crowdstrike-eks-protection',
            type='STANDARD'
        )

    except botocore.exceptions.ClientError as error:
        if error.response['Error']['Code'] == "ResourceInUseException":
            logger.warning('Skipping Access Entry for %s: %s already exists', EKS_CLUSTER_NAME, arn)
        else:
            logger.error(error)
    try:
        logger.info('Adding access policy for %s', EKS_CLUSTER_NAME)
        access_policy = f'arn:{PARTITION}:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy'
        eks_client.associate_access_policy(
            clusterName=EKS_CLUSTER_NAME,
            principalArn=arn,
            policyArn=access_policy,
            accessScope={
                'type': 'cluster'
            }
        )
    except botocore.exceptions.ClientError as error:
        logger.error(error)
    # Check if cluster already allows access from anywhere
    if '0.0.0.0/0' in cidrs_list:
        logger.info('Cluster %s already allows access from 0.0.0.0/0, skipping NAT IP update', EKS_CLUSTER_NAME)
    else:
        try:
            logger.info('Adding NAT IP for %s', EKS_CLUSTER_NAME)
            cidrs_list.append(f'{NAT_IP}/32')
            response = eks_client.update_cluster_config(
                name=EKS_CLUSTER_NAME,
                resourcesVpcConfig={
                    'publicAccessCidrs': cidrs_list
                }
            )
            update_id = response['update']['id']
            update_response = eks_client.describe_update(
                name=EKS_CLUSTER_NAME,
                updateId=update_id
            )
            while update_response['update']['status'] in 'InProgress':
                logger.info('waiting for update to complete...')
                time.sleep(30)
                update_response = eks_client.describe_update(
                    name=EKS_CLUSTER_NAME,
                    updateId=update_id
                )
        except botocore.exceptions.ClientError as error:
            logger.error(error)
    logger.info('Cluster: %s is now setup', EKS_CLUSTER_NAME)


eks = boto3.client(service_name='eks', region_name=AWS_REGION)
public_access_cidrs = check_cluster(eks)
setup_cluster(eks, public_access_cidrs)
