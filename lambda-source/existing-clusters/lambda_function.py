import boto3
import json
import requests
import os
import logging
import botocore
from datetime import date

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# CONSTANTS
SUCCESS = "SUCCESS"
FAILED = "FAILED"

DATE = date.today()
PROJECT = os.environ['project_name']
BUCKET = os.environ['artifact_bucket']
REGION = os.environ['AWS_DEFAULT_REGION']

def start_build(clusterName, cluster_arn, node_type):
    try:
        session = boto3.session.Session()
        client = session.client(
            service_name='codebuild',
            region_name=REGION
        )
        build = client.start_build(
            projectName=PROJECT,
            artifactsOverride={
                'type': 'S3',
                'location': f'{BUCKET}',
                'path': 'BuildResults',
                'name': f'{clusterName}-{DATE}',
                'packaging': 'ZIP'
            },
            environmentVariablesOverride=[
                {
                    'name': 'CLUSTER',
                    'value': f'{clusterName}',
                    'type': 'PLAINTEXT'
                },
                {
                    'name': 'NODE_TYPE',
                    'value': f'{node_type}',
                    'type': 'PLAINTEXT'
                },
                {
                    'name': 'CLUSTER_ARN',
                    'value': f'{cluster_arn}',
                    'type': 'PLAINTEXT'
                }
            ]
        )
        buildId = build.get('build', {}).get('id')
        logger.info(f'Started build {PROJECT}, buildId {buildId}')
    except botocore.exceptions.ClientError as error:
        logger.error(error)

def check_fargate(region, clusterName):
    session = boto3.session.Session()
    client = session.client(
        service_name='eks',
        region_name=region
    )
    try:
        response = client.list_fargate_profiles(
            clusterName=clusterName,
            maxResults=10
        )
        if response['fargateProfileNames'] not in []:
            logger.info('No fargate profiles found, setting node_type to nodegroup...')
            node_type = 'nodegroup'
            return node_type
        else:
            node_type = 'fargate'
            return node_type
    except botocore.exceptions.ClientError as error:
        logger.error(error)
        node_type = 'none'
        return node_type
    
def get_active_regions():
    session = boto3.session.Session()
    client = session.client(
        service_name='ec2',
        region_name=REGION
    )
    try:
        active_regions = []
        describe_regions_response = client.describe_regions(AllRegions=False)
        regions = describe_regions_response['Regions']
        for region in regions:
            active_regions += [region['RegionName']]
        return active_regions
    except botocore.exceptions.ClientError as error:
        logger.error(error)
        active_regions = []
        return active_regions
    
def cfnresponse_send(event, context, responseStatus, responseData, physicalResourceId=None, noEcho=False):
    responseUrl = event['ResponseURL']
    print(responseUrl)
    responseBody = {}
    responseBody['Status'] = responseStatus
    responseBody['Reason'] = 'See the details in CloudWatch Log Stream: '
    responseBody['PhysicalResourceId'] = physicalResourceId
    responseBody['StackId'] = event['StackId']
    responseBody['RequestId'] = event['RequestId']
    responseBody['LogicalResourceId'] = event['LogicalResourceId']
    responseBody['Data'] = responseData
    json_responseBody = json.dumps(responseBody)
    print("Response body:\n" + json_responseBody)
    headers = {
        'content-type': '',
        'content-length': str(len(json_responseBody))
    }
    try:
        response = requests.put(responseUrl,
                                data=json_responseBody,
                                headers=headers)
        print("Status code: " + response.reason)
    except Exception as e:
        print("send(..) failed executing requests.put(..): " + str(e))

def lambda_handler(event,context):
    logger.info('Got event {}'.format(event))
    logger.info('Context {}'.format(context))
    logger.info('Gathering Event Details...')
    response_d = {}

    logger.info('Checking EKS Cluster for API Access Config..')
    try:
        active_regions = get_active_regions()
        for region in active_regions:
            session = boto3.session.Session()
            client = session.client(
                service_name='eks',
                region_name=region
            )
            clusters = []
            cluster_list = client.list_clusters()
            clusters = cluster_list.get('clusters')
            for clusterName in clusters:
                cluster_details = client.describe_cluster(
                    name=clusterName
                )
                cluster_arn = cluster_details.get('cluster', {}).get('arn')
                node_type = check_fargate(region, clusterName)
                if node_type not in 'none':
                    if 'API' in cluster_details.get('cluster', {}).get('accessConfig', {}).get('authenticationMode'):
                        start_build(clusterName, cluster_arn, node_type)
                    else:
                        logger.info(f'API Access not enabled on cluster {clusterName}')
        cfnresponse_send(event, context, SUCCESS, response_d, "CustomResourcePhysicalID")
    except botocore.exceptions.ClientError as error:
        logger.error(error)
        response_d['error'] = error
        cfnresponse_send(event, context, SUCCESS, response_d, "CustomResourcePhysicalID")