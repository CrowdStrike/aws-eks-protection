import os
import time
import boto3
import botocore

AWS_REGION = os.environ["AWS_REGION"]
PRINCIPAL_ARN = os.environ["PRINCIPAL_ARN"]
USERNAME = os.environ["USERNAME"]
CLUSTER = os.environ["CLUSTER"]
NODETYPE = os.environ["NODE_TYPE"]
ACCOUNT_ID = os.environ["ACCOUNT_ID"]
REGION = os.environ["REGION"]
SWITCH_ROLE = os.environ["SWITCH_ROLE"]
NAT_IP = os.environ["NAT_IP"]
ACCESS_POLICY = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
DEPLOY_MODE = os.environ.get("DEPLOY_MODE", "organization")


def check_cluster(session):
    client = session.client(service_name="eks", region_name=AWS_REGION)

    cluster_details = client.describe_cluster(name=CLUSTER)
    while "ACTIVE" not in cluster_details.get("cluster", {}).get("status"):
        time.sleep(60)
        cluster_details = client.describe_cluster(name=CLUSTER)
    else:
        print(f"Cluster {CLUSTER} is now active")
        return


def setup_cluster(session):
    client = session.client(service_name="eks", region_name=AWS_REGION)

    try:
        print(f"Adding access entry for {CLUSTER}")
        client.create_access_entry(clusterName=CLUSTER, principalArn=PRINCIPAL_ARN, username=USERNAME, type="STANDARD")

    except botocore.exceptions.ClientError as error:
        if error.response["Error"]["Code"] == "ResourceInUseException":
            print(f"Skipping Access Entry for {CLUSTER}: {PRINCIPAL_ARN} already exists")
        else:
            print(error)
    try:
        print(f"Adding access policy for {CLUSTER}")
        client.associate_access_policy(
            clusterName=CLUSTER, principalArn=PRINCIPAL_ARN, policyArn=ACCESS_POLICY, accessScope={"type": "cluster"}
        )
    except botocore.exceptions.ClientError as error:
        print(error)
    try:
        print(f"Adding NAT IP for {CLUSTER}")
        response = client.update_cluster_config(
            name=CLUSTER,
            resourcesVpcConfig={
                "publicAccessCidrs": [
                    f"{NAT_IP}/32",
                ]
            },
        )
        update_id = response["update"]["id"]
        update_response = client.describe_update(name=CLUSTER, updateId=update_id)
        while update_response["update"]["status"] in "InProgress":
            print("waiting for update to complete...")
            time.sleep(30)
            update_response = client.describe_update(name=CLUSTER, updateId=update_id)
    except botocore.exceptions.ClientError as error:
        print(error)
    print(f"Cluster: {CLUSTER} is now setup")
    return


def new_session(account_id, region):
    if DEPLOY_MODE == "single-account":
        return boto3.Session()
    elif DEPLOY_MODE == "organization":
        try:
            sts_connection = boto3.client("sts")
            credentials = sts_connection.assume_role(
                RoleArn=f"arn:aws:iam::{account_id}:role/{SWITCH_ROLE}",
                RoleSessionName=f"crowdstrike-eks-{account_id}",
            )
            return boto3.session.Session(
                aws_access_key_id=credentials["Credentials"]["AccessKeyId"],
                aws_secret_access_key=credentials["Credentials"]["SecretAccessKey"],
                aws_session_token=credentials["Credentials"]["SessionToken"],
                region_name=region,
            )
        except sts_connection.exceptions.ClientError as exc:
            # Print the error and continue.
            # Handle what to do with accounts that cannot be accessed
            # due to assuming role errors.
            print("Cannot access adjacent account: ", account_id, exc)
            return None


session = new_session()
check_cluster(session)
setup_cluster(session)
