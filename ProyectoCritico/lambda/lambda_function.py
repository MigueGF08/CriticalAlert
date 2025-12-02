import json
import boto3
import os
from datetime import datetime

sf_client = boto3.client('stepfunctions')
ddb = boto3.resource('dynamodb')
table = ddb.Table(os.environ['TABLE_NAME'])

def lambda_handler(event, context):
    try:
        input_data = json.loads(event['body']) if 'body' in event else event
        
        value = float(input_data.get('value', 0))
        test_name = input_data.get('test_name', 'unknown')
        result_id = input_data.get('result_id', str(input_data.get('patient_id', 'NO-ID')) + '-' + datetime.utcnow().strftime("%Y%m%d%H%M"))
        
        is_critical = False
        if input_data.get('is_critical', False):
            is_critical = True
        elif test_name.lower() == 'potassium' and (value < 2.5 or value > 6.0):
            is_critical = True
        
        response_data = {
            'result_id': result_id,
            'status': 'NORMAL',
            'critical': False
        }

        if is_critical:
            table.put_item(Item={
                'result_id': result_id,
                'status': 'PENDING',
                'acknowledged': False,
                'timestamp': datetime.utcnow().isoformat(),
                'details_summary': f"CRITICO: {input_data['patient_name']} tiene {test_name} en {value}. Nivel: {input_data['criticality']['level']}"
            })
            
            sf_client.start_execution(
                stateMachineArn=os.environ['SFN_ARN'],
                input=json.dumps(input_data)
            )
            response_data['status'] = 'CRITICAL_ALERT_SENT'
            response_data['critical'] = True
            
        return {
            'statusCode': 200,
            'headers': {
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Headers': 'Content-Type',
                'Access-Control-Allow-Methods': 'OPTIONS,POST'
            },
            'body': json.dumps(response_data)
        }

    except Exception as e:
        return {
            'statusCode': 500,
            'headers': {
                'Access-Control-Allow-Origin': '*',
            },
            'body': json.dumps({'error': str(e)})
        }