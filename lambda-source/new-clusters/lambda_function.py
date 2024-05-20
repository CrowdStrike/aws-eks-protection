import boto3
import os
import logging
import botocore
from datetime import date

logger = logging.getLogger()
logger.setLevel(logging.INFO)

DATE = date.today()
PROJECT = os.environ['project_name']
BUCKET = os.environ['artifact_bucket']

def start_build(region, clusterName, cluster_arn, node_type):
    try:
        session = boto3.session.Session()
        client = session.client(
            service_name='codebuild',
            region_name=region
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

def lambda_handler(event,context):
    logger.info('Got event {}'.format(event))
    logger.info('Context {}'.format(context))
    
    logger.info('Gathering Event Details...')
    region = event['region']
    clusterName = event['detail']['requestParameters']['name']
    eventName = event['detail']['eventName']
    if 'CreateCluster' in eventName:
        node_type = 'nodegroup'
    elif 'CreateFargateProfile' in eventName:
        node_type = 'fargate'

    logger.info('Checking EKS Cluster for API Access Config..')
    try:
        session = boto3.session.Session()
        client = session.client(
            service_name='eks',
            region_name=region
        )
        cluster_details = client.describe_cluster(
            name=clusterName
        )
        cluster_arn = cluster_details.get('cluster', {}).get('arn')
        if 'API' in cluster_details.get('cluster', {}).get('accessConfig', {}).get('authenticationMode'):
            start_build(region, clusterName, cluster_arn, node_type)
        else:
            logger.info(f'API Access not enabled on cluster {clusterName}')
    except botocore.exceptions.ClientError as error:
        logger.error(error)