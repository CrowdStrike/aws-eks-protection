import os
import time
import boto3
import botocore

AWS_REGION = os.environ['AWS_REGION']
PRINCIPAL_ARN = os.environ['PRINCIPAL_ARN']
USERNAME = os.environ['USERNAME']
CLUSTER = os.environ['CLUSTER']
NODETYPE = os.environ['NODE_TYPE']
ACCESS_POLICY = 'arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy'

def check_cluster():
    session = boto3.session.Session()
    client = session.client(
        service_name='eks',
        region_name=AWS_REGION
    )

    cluster_details = client.describe_cluster(
        name=CLUSTER
    )
    while 'ACTIVE' not in cluster_details.get('cluster', {}).get('status'):
        time.sleep(60)
        cluster_details = client.describe_cluster(
            name=CLUSTER
        )
    else:
        print(f'Cluster {CLUSTER} is now active')
        return
    
def setup_cluster():
    session = boto3.session.Session()
    client = session.client(
        service_name='eks',
        region_name=AWS_REGION
    )

    try:
        print(f'Adding access entry for {CLUSTER}')
        client.create_access_entry(
            clusterName=CLUSTER,
            principalArn=PRINCIPAL_ARN,
            username=USERNAME,
            type='STANDARD'
        )
    
    except botocore.exceptions.ClientError as error:
        if error.response['Error']['Code'] == "ResourceInUseException":
            print(f'Skipping Access Entry for {CLUSTER}: {PRINCIPAL_ARN} already exists')
        else:
            print(error)
    try:
        print(f'Adding access policy for {CLUSTER}')
        client.associate_access_policy(
            clusterName=CLUSTER,
            principalArn=PRINCIPAL_ARN,
            policyArn=ACCESS_POLICY,
            accessScope={
                'type': 'cluster'
            }
        )
        print(f'Cluster: {CLUSTER} is now setup')
    except botocore.exceptions.ClientError as error:
        print(error)
    return

check_cluster()
setup_cluster()