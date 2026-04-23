import json
import os
import boto3
import uuid
from datetime import datetime
from decimal import Decimal

dynamodb = boto3.resource("dynamodb", region_name=os.environ.get("AWS_REGION", "us-east-1"))
lambda_client = boto3.client("lambda", region_name=os.environ.get("AWS_REGION", "us-east-1"))

CHARTS_TABLE = os.environ["CHARTS_TABLE"]
TEMPLATES_TABLE = os.environ["TEMPLATES_TABLE"]
EXTRACT_FUNCTION = os.environ["EXTRACT_FUNCTION"]

CORS_HEADERS = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "Content-Type",
    "Access-Control-Allow-Methods": "GET,POST,PUT,OPTIONS"
}


class DecimalEncoder(json.JSONEncoder):
    def default(self, o):
        if isinstance(o, Decimal):
            return float(o)
        return super().default(o)


def respond(status, body):
    return {"statusCode": status, "headers": {**CORS_HEADERS, "Content-Type": "application/json"}, "body": json.dumps(body, cls=DecimalEncoder)}


def handler(event, context):
    method = event.get("requestContext", {}).get("http", {}).get("method", "")
    path = event.get("rawPath", "")

    if method == "OPTIONS":
        return respond(200, {})

    # POST /sessions
    if method == "POST" and path == "/sessions":
        body = json.loads(event.get("body", "{}"))
        session_id = str(uuid.uuid4())
        table = dynamodb.Table(CHARTS_TABLE)
        item = {
            "sessionId": session_id,
            "templateId": body.get("templateId", "neuromodulator"),
            "status": "created",
            "createdAt": datetime.utcnow().isoformat(),
            "transcript": "",
            "chart": {}
        }
        table.put_item(Item=item)
        return respond(201, {"sessionId": session_id, **item})

    # GET /sessions/{id}
    if method == "GET" and path.startswith("/sessions/") and "/extract" not in path and "/chart" not in path:
        session_id = path.split("/sessions/")[1]
        table = dynamodb.Table(CHARTS_TABLE)
        resp = table.get_item(Key={"sessionId": session_id})
        item = resp.get("Item")
        if not item:
            return respond(404, {"error": "Session not found"})
        return respond(200, item)

    # PUT /sessions/{id}/chart
    if method == "PUT" and "/chart" in path:
        session_id = path.split("/sessions/")[1].split("/chart")[0]
        body = json.loads(event.get("body", "{}"))
        table = dynamodb.Table(CHARTS_TABLE)
        chart_data = json.loads(json.dumps(body.get("chart", {})), parse_float=Decimal)
        table.update_item(
            Key={"sessionId": session_id},
            UpdateExpression="SET chart = :c, #s = :s, updatedAt = :u",
            ExpressionAttributeNames={"#s": "status"},
            ExpressionAttributeValues={":c": chart_data, ":s": "reviewed", ":u": datetime.utcnow().isoformat()}
        )
        return respond(200, {"sessionId": session_id, "status": "reviewed"})

    # POST /sessions/{id}/extract
    if method == "POST" and "/extract" in path:
        session_id = path.split("/sessions/")[1].split("/extract")[0]
        body = json.loads(event.get("body", "{}"))
        table = dynamodb.Table(CHARTS_TABLE)
        resp = table.get_item(Key={"sessionId": session_id})
        item = resp.get("Item")
        if not item:
            return respond(404, {"error": "Session not found"})
        transcript = body.get("transcript", item.get("transcript", ""))
        template_id = body.get("templateId", item.get("templateId", "neuromodulator"))
        payload = {"sessionId": session_id, "transcript": transcript, "templateId": template_id}
        result = lambda_client.invoke(FunctionName=EXTRACT_FUNCTION, Payload=json.dumps(payload))
        result_payload = json.loads(result["Payload"].read())
        if "body" in result_payload:
            return respond(200, json.loads(result_payload["body"]))
        return respond(200, result_payload)

    # GET /templates
    if method == "GET" and path == "/templates":
        table = dynamodb.Table(TEMPLATES_TABLE)
        resp = table.scan()
        return respond(200, {"templates": resp.get("Items", [])})

    return respond(404, {"error": "Not found"})
