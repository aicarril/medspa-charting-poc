import json
import os
import boto3
from datetime import datetime
from decimal import Decimal

bedrock = boto3.client("bedrock-runtime", region_name=os.environ.get("AWS_REGION", "us-east-1"))
dynamodb = boto3.resource("dynamodb", region_name=os.environ.get("AWS_REGION", "us-east-1"))
s3 = boto3.client("s3", region_name=os.environ.get("AWS_REGION", "us-east-1"))

CHARTS_TABLE = os.environ["CHARTS_TABLE"]
TEMPLATES_TABLE = os.environ["TEMPLATES_TABLE"]
S3_BUCKET = os.environ["S3_BUCKET"]
MODEL_ID = os.environ.get("MODEL_ID", "us.anthropic.claude-haiku-4-5-20251001-v1:0")


def get_template(template_id):
    table = dynamodb.Table(TEMPLATES_TABLE)
    resp = table.get_item(Key={"templateId": template_id})
    return resp.get("Item")


def invoke_bedrock(prompt):
    body = json.dumps({
        "anthropic_version": "bedrock-2023-05-31",
        "max_tokens": 4096,
        "messages": [{"role": "user", "content": prompt}]
    })
    resp = bedrock.invoke_model(modelId=MODEL_ID, body=body, contentType="application/json", accept="application/json")
    result = json.loads(resp["body"].read())
    return result["content"][0]["text"]


def extract_fields(transcript, template):
    fields = template["fields"]
    field_descriptions = []
    for k, v in fields.items():
        label = v.get("label", k)
        ftype = v.get("type", "string")
        field_descriptions.append(f'- "{k}" ({ftype}): {label}')

    prompt = f"""Extract structured chart data from this medical spa transcript.

Template: {template['name']}
Fields to extract:
{chr(10).join(field_descriptions)}

Transcript:
{transcript}

Return ONLY valid JSON with all field keys present. Use null for fields not mentioned. For arrays, return empty array if not mentioned. For booleans, infer from context or use null."""

    raw = invoke_bedrock(prompt)
    # Parse JSON from response (handle markdown code blocks)
    text = raw.strip()
    if text.startswith("```"):
        text = text.split("\n", 1)[1].rsplit("```", 1)[0].strip()
    return json.loads(text)


def score_confidence(transcript, extracted, template):
    prompt = f"""Score the confidence (0.0-1.0) of each extracted field based on how clearly it was stated in the transcript.

Template: {template['name']}
Transcript:
{transcript}

Extracted data:
{json.dumps(extracted, indent=2)}

Return ONLY valid JSON mapping each field key to a confidence score (0.0-1.0). Use 0.0 for fields that were not mentioned."""

    raw = invoke_bedrock(prompt)
    text = raw.strip()
    if text.startswith("```"):
        text = text.split("\n", 1)[1].rsplit("```", 1)[0].strip()
    return json.loads(text)


def handler(event, context):
    body = json.loads(event.get("body", "{}")) if isinstance(event.get("body"), str) else event
    session_id = body["sessionId"]
    transcript = body["transcript"]
    template_id = body.get("templateId", "neuromodulator")

    template = get_template(template_id)
    if not template:
        return {"statusCode": 404, "body": json.dumps({"error": "Template not found"})}

    # Pass 1: Extract fields
    extracted = extract_fields(transcript, template)

    # Pass 2: Score confidence
    confidence = score_confidence(transcript, extracted, template)

    # Save raw transcript to S3
    s3.put_object(
        Bucket=S3_BUCKET,
        Key=f"transcripts/{session_id}.txt",
        Body=transcript,
        ContentType="text/plain"
    )

    # Save chart record to DynamoDB (convert floats to Decimal)
    charts_table = dynamodb.Table(CHARTS_TABLE)
    record = json.loads(json.dumps({
        "sessionId": session_id,
        "templateId": template_id,
        "chart": extracted,
        "confidence": confidence,
        "transcript": transcript,
        "createdAt": datetime.utcnow().isoformat(),
        "status": "extracted"
    }), parse_float=Decimal)
    charts_table.put_item(Item=record)

    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json", "Access-Control-Allow-Origin": "*"},
        "body": json.dumps({"sessionId": session_id, "chart": extracted, "confidence": confidence, "templateId": template_id})
    }
