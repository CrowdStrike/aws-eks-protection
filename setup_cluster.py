import os
import time
import boto3
import botocore

AWS_REGION = os.environ['AWS_REGION']
SCOPE = os.environ['SCOPE']
EKS_CLUSTER_NAME = os.environ['EKS_CLUSTER_NAME']
ACCOUNT_ID = os.environ['ACCOUNT_ID']
SWITCH_ROLE = os.environ['SWITCH_ROLE']
NAT_IP = os.environ['NAT_IP']
TASK_ARN = os.environ['TASK_ARN']
ACCESS_POLICY = 'arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy'

def check_cluster(eks):
    cluster_details = eks.describe_cluster(
        name=EKS_CLUSTER_NAME
    )
    public_access_cidrs = cluster_details.get('cluster', {}).get('resourcesVpcConfig', {}).get('publicAccessCidrs')
    while 'ACTIVE' not in cluster_details.get('cluster', {}).get('status'):
        time.sleep(60)
        cluster_details = eks.describe_cluster(
            name=EKS_CLUSTER_NAME
        )
    else:
        print(f'Cluster {EKS_CLUSTER_NAME} is now active')
        return public_access_cidrs
    
def setup_cluster(eks, public_access_cidrs):
    if SCOPE == 'organization':
        arn = SWITCH_ROLE
    else:
        arn = TASK_ARN
    try:
        print(f'Adding access entry for {EKS_CLUSTER_NAME}')
        eks.create_access_entry(
            clusterName=EKS_CLUSTER_NAME,
            principalArn=arn,
            username='crowdstrike-eks-protection',
            type='STANDARD'
        )
    
    except botocore.exceptions.ClientError as error:
        if error.response['Error']['Code'] == "ResourceInUseException":
            print(f'Skipping Access Entry for {EKS_CLUSTER_NAME}: {arn} already exists')
        else:
            print(error)
    try:
        print(f'Adding access policy for {EKS_CLUSTER_NAME}')
        eks.associate_access_policy(
            clusterName=EKS_CLUSTER_NAME,
            principalArn=arn,
            policyArn=ACCESS_POLICY,
            accessScope={
                'type': 'cluster'
            }
        )
    except botocore.exceptions.ClientError as error:
        print(error)
    try:
        print(f'Adding NAT IP for {EKS_CLUSTER_NAME}')
        public_access_cidrs.append(f'{NAT_IP}/32')
        response = eks.update_cluster_config(
            name=EKS_CLUSTER_NAME,
            resourcesVpcConfig={
                'publicAccessCidrs': public_access_cidrs
            }
        )
        update_id = response['update']['id']
        update_response = eks.describe_update(
            name=EKS_CLUSTER_NAME,
            updateId=update_id
        )
        while update_response['update']['status'] in 'InProgress':
            print('waiting for update to complete...')
            time.sleep(30)
            update_response = eks.describe_update(
                name=EKS_CLUSTER_NAME,
                updateId=update_id
            )
    except botocore.exceptions.ClientError as error:
        print(error)
    print(f'Cluster: {EKS_CLUSTER_NAME} is now setup')
    return

# Cross Account
def new_session():
    try:
        sts_connection = boto3.client('sts')
        credentials = sts_connection.assume_role(
            RoleArn=f'arn:aws:iam::{ACCOUNT_ID}:role/{SWITCH_ROLE}',
            RoleSessionName=f'crowdstrike-eks-{ACCOUNT_ID}'
        )
        session = boto3.session.Session(
            aws_access_key_id=credentials['Credentials']['AccessKeyId'],
            aws_secret_access_key=credentials['Credentials']['SecretAccessKey'],
            aws_session_token=credentials['Credentials']['SessionToken'],
            region_name=AWS_REGION
        )
        return session.client(
            service_name='eks',
            region_name=AWS_REGION
        )
    except sts_connection.exceptions.ClientError as exc:
        # Print the error and continue
        print("Cannot access adjacent account: ", ACCOUNT_ID, exc)
        return None

if SCOPE == 'organization':
    eks = new_session()
else:
    eks = boto3.client(
            service_name='eks',
            region_name=AWS_REGION
        )
public_access_cidrs = check_cluster(eks)
setup_cluster(eks, public_access_cidrs)