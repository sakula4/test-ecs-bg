from __future__ import print_function

import boto3
import json
from botocore.exceptions import ClientError



client = boto3.client('elbv2')

def lambda_handler(event, context):
    # For debugging so you can see raw event format.
    print('Here is the event:')
    print(json.dumps(event))
    
    target = event['target']
    health = client.describe_target_health(
        TargetGroupArn = target
    )
    targetHealth = health['TargetHealthDescriptions'][0]['TargetHealth']
    print(json.dumps(targetHealth, indent=4))

    return targetHealth