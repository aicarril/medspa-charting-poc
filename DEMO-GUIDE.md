# Demo Guide — MSI MedSpa Transcribe + Chart Extraction POC

## Opening Script

> "Hi, I'd like to show you how we can eliminate manual charting for medical spa providers. Today, a provider spends 5-10 minutes after every appointment typing up treatment notes. With this POC, they tap one button, speak naturally during or after the appointment, and the system automatically fills out the chart — correctly recognizing medical spa terms like Botox, glabella, and microneedling. Let me show you how it works."

---

## Step-by-Step Demo

### Step 1: Show the Chart Templates

- **Say**: "First, let me show you the system already knows your chart formats. We've loaded three of your actual treatment form templates — Neuromodulator, Filler, and Aesthetic."
- **Do**: Open a browser and navigate to:
  ```
  https://haywkpmggd.execute-api.us-east-1.amazonaws.com/templates
  ```
- **Show**: JSON response listing 3 templates — `neuromodulator`, `filler`, `aesthetic` — each with their full field schemas (15-16 fields per template).
- **Explain**: "These templates are stored in DynamoDB and are fully configurable. When you add a new state or treatment type, you just add a new template — no code changes needed."

### Step 2: Start a New Charting Session

- **Say**: "Now let's simulate what happens when a provider starts a session. They select the treatment type — in this case, a Botox appointment — and the system creates a session."
- **Do**: Run this in a terminal or use a REST client:
  ```bash
  curl -s -X POST https://haywkpmggd.execute-api.us-east-1.amazonaws.com/sessions \
    -H "Content-Type: application/json" \
    -d '{"templateId":"neuromodulator"}' | python3 -m json.tool
  ```
- **Show**: A `201 Created` response with a new `sessionId`, `status: "created"`, and empty `chart` and `transcript` fields.
- **Explain**: "The session is now tracked. In the full product, this is where the provider taps 'Start Session' in Meevo and the mic activates."

### Step 3: Submit a Transcript for Chart Extraction

- **Say**: "Now the provider has finished speaking. Here's a realistic dictation — watch what happens when we send it to the AI."
- **Do**: Replace `SESSION_ID` with the ID from Step 2, then run:
  ```bash
  curl -s -X POST https://haywkpmggd.execute-api.us-east-1.amazonaws.com/sessions/SESSION_ID/extract \
    -H "Content-Type: application/json" \
    -d '{
      "transcript": "Patient Sarah Johnson came in today for her regular Botox appointment. She is concerned about her forehead lines and the glabella area. After reviewing her history and obtaining informed consent, I administered 20 units of Botox to the glabella, 10 units to each crow'\''s feet area, and 12 units to the forehead lines for a total of 52 units. Lot number BX2024-789. Used a 30-gauge needle with standard injection technique. No adverse reactions observed. Patient tolerated the procedure well. Photographs were taken before treatment. Post-treatment instructions given: no lying down for 4 hours, no strenuous exercise for 24 hours, avoid rubbing the treated areas. Follow-up scheduled in 2 weeks."
    }' | python3 -m json.tool
  ```
- **Show**: The response contains:
  - `chart.patientName`: "Sarah Johnson"
  - `chart.product`: "Botox"
  - `chart.treatmentAreas`: glabella, crow's feet, forehead lines
  - `chart.totalUnits`: 52
  - `chart.lotNumber`: "BX2024-789"
  - `chart.consentObtained`: true
  - `chart.prePhotos`: true
  - `chart.postCareInstructions`: no lying down for 4 hours...
  - `chart.followUpDate`: "2 weeks"
  - `confidence` scores: 0.95 for clearly stated fields, 0.0 for fields not mentioned
- **Explain**: "The AI made two passes — first to extract the data, then to score its own confidence. Notice the confidence scores: 0.95 for things the provider clearly said, 0.0 for things like 'dilution' that weren't mentioned. This tells the provider exactly which fields to double-check."

### Step 4: Show the Stored Data

- **Say**: "Everything is persisted. The raw transcript is in S3, and the structured chart is in DynamoDB."
- **Do**: Retrieve the session:
  ```bash
  curl -s https://haywkpmggd.execute-api.us-east-1.amazonaws.com/sessions/SESSION_ID | python3 -m json.tool
  ```
- **Show**: Full session record with `status: "extracted"`, the complete chart, confidence scores, and transcript.
- **Explain**: "This is HIPAA-ready — all data stays within AWS. S3 for raw transcripts, DynamoDB for structured charts. Nothing leaves the AWS boundary."

### Step 5: Provider Reviews and Saves the Chart

- **Say**: "The provider reviews the auto-filled chart, corrects anything the AI missed, and saves. Let me show that flow."
- **Do**:
  ```bash
  curl -s -X PUT https://haywkpmggd.execute-api.us-east-1.amazonaws.com/sessions/SESSION_ID/chart \
    -H "Content-Type: application/json" \
    -d '{
      "chart": {
        "patientName": "Sarah Johnson",
        "provider": "Dr. Martinez",
        "dateOfService": "2026-04-23",
        "product": "Botox",
        "totalUnits": 52,
        "treatmentAreas": [
          {"area": "glabella", "units": 20},
          {"area": "crow'\''s feet (left)", "units": 10},
          {"area": "crow'\''s feet (right)", "units": 10},
          {"area": "forehead lines", "units": 12}
        ],
        "lotNumber": "BX2024-789",
        "dilution": "100 units/2.5mL saline",
        "needleSize": "30 gauge",
        "consentObtained": true,
        "prePhotos": true,
        "adverseReactions": "None",
        "postCareInstructions": "No lying down 4 hours, no exercise 24 hours, avoid rubbing treated areas",
        "followUpDate": "2026-05-07",
        "notes": "Patient tolerated procedure well. Regular maintenance patient."
      }
    }' | python3 -m json.tool
  ```
- **Show**: `status: "reviewed"` — the chart is finalized.
- **Explain**: "The provider added the fields the AI couldn't infer — their own name, the exact date, the dilution ratio. Everything else was pre-filled. What used to take 5-10 minutes now takes 30 seconds of review."

### Step 6: Show Custom Vocabulary Working

- **Say**: "One thing that makes this accurate is the custom vocabulary. We've loaded 41 medical spa terms — Botox, Dysport, Juvederm, glabella, microneedling, and more. Without this, standard speech-to-text would misspell these terms. With it, they're recognized correctly every time."
- **Do**: Show the vocabulary:
  ```bash
  aws transcribe get-vocabulary --vocabulary-name medspa-vocabulary --region us-east-1 --query '{Name:VocabularyName,Status:VocabularyState,Language:LanguageCode}'
  ```
- **Show**: `VocabularyName: medspa-vocabulary`, `VocabularyState: READY`, `LanguageCode: en-US`
- **Explain**: "This vocabulary is extensible. When you add new products or procedures, you just add terms — no model retraining needed."

---

## Live URLs and Resources

| Resource | URL / Identifier |
|----------|-----------------|
| REST API | `https://haywkpmggd.execute-api.us-east-1.amazonaws.com` |
| GET templates | `https://haywkpmggd.execute-api.us-east-1.amazonaws.com/templates` |
| POST new session | `https://haywkpmggd.execute-api.us-east-1.amazonaws.com/sessions` |
| S3 Bucket | `medspa-storage-779846822196` |
| Charts DynamoDB Table | `medspa-charts` |
| Templates DynamoDB Table | `medspa-templates` |
| Custom Vocabulary | `medspa-vocabulary` |
| Cognito Identity Pool | `us-east-1:76dedb29-db76-475f-bdb2-aafcfa06fe8b` |
| Extract Lambda | `medspa-extract-chart` |
| API Lambda | `medspa-api` |
| AWS Region | `us-east-1` |
| AWS Console — DynamoDB | `https://us-east-1.console.aws.amazon.com/dynamodbv2/home?region=us-east-1#table?name=medspa-charts` |
| AWS Console — S3 | `https://s3.console.aws.amazon.com/s3/buckets/medspa-storage-779846822196?region=us-east-1` |

---

## Anticipated Questions and Answers

**Q1: How accurate is the transcription for medical terms?**
A: We use Amazon Transcribe with a custom vocabulary of 41 medical spa terms. Terms like Botox, Dysport, glabella, microneedling, and hyaluronic acid are recognized correctly. Without custom vocabulary, these would often be misspelled. Accuracy improves further as we add more terms.

**Q2: Is this HIPAA compliant?**
A: Yes. All data stays within AWS — Amazon Transcribe, Bedrock, S3, and DynamoDB are all HIPAA-eligible services. No data leaves the AWS boundary. The S3 bucket has AES-256 encryption and all public access blocked. For production, we'd add Cognito user authentication and VPC endpoints.

**Q3: How long does the chart extraction take?**
A: The Bedrock extraction (two passes — extract + confidence scoring) takes 3-8 seconds. This is well within the customer's stated tolerance of up to 10 seconds. We use Claude Haiku for speed; we can switch to Sonnet for higher accuracy if needed.

**Q4: What happens if the AI gets a field wrong?**
A: Every field has a confidence score (0.0-1.0). Fields the AI is unsure about are flagged with low scores so the provider knows exactly what to review. The provider can edit any field before saving. The system is designed as AI-assisted, not AI-autonomous.

**Q5: Can we add new chart templates for different states or procedures?**
A: Yes. Templates are stored as JSON in DynamoDB. Adding a new template is a data operation — no code changes. The LLM dynamically reads the template fields and extracts accordingly. The customer mentioned state-by-state compliance differences; each state can have its own template variant.

**Q6: What's the cost per appointment?**
A: For a 2-minute dictation: ~$0.06 for Transcribe (with custom vocabulary), ~$0.01 for Bedrock (two Haiku calls). Total ~$0.07 per appointment. At 100 spas × 2.5 providers × 20 appointments/day × 5 days/week, that's roughly $1,750/week or $7,000/month for the entire fleet.

**Q7: Does this work with real-time streaming or only post-session?**
A: This POC demonstrates the post-session dictation flow (provider speaks after the appointment). The architecture supports real-time streaming via WebSocket — the Cognito Identity Pool already has `transcribe:StartStreamTranscription` permissions. Real-time streaming would be the next phase.

**Q8: How does this integrate with Meevo?**
A: The REST API is the integration point. Meevo's web app would call these endpoints — create session, submit transcript, retrieve chart. The API uses standard REST with CORS enabled, so it can be called from any web frontend.

**Q9: What if Bedrock is down or slow?**
A: The Lambda has a 60-second timeout. If Bedrock doesn't respond, the session stays in "created" status and the provider can retry. The transcript is always saved to S3 regardless, so no data is lost. For production, we'd add a retry queue with SQS.

**Q10: Can providers use this on mobile?**
A: Yes. The browser captures audio via the Web Audio API, which works on modern mobile browsers (iOS Safari, Chrome Android). The Cognito Identity Pool provides temporary credentials directly to the browser — no server-side session needed.

---

## Troubleshooting

### API returns 500 or timeout
- **Check**: Lambda logs in CloudWatch — `aws logs tail /aws/lambda/medspa-extract-chart --since 5m`
- **Likely cause**: Bedrock throttling or model not available in region
- **Fix**: Wait 30 seconds and retry. If persistent, check Bedrock model access in the AWS console under Bedrock → Model access

### "Template not found" error on extract
- **Check**: `curl https://haywkpmggd.execute-api.us-east-1.amazonaws.com/templates` — verify templates are loaded
- **Fix**: Re-run the seed script: `bash /shared-repo/scripts/seed-templates.sh`

### CORS errors in browser
- **Check**: Browser console for the exact error
- **Likely cause**: Missing `Content-Type` header in request
- **Fix**: Ensure requests include `-H "Content-Type: application/json"`

### Custom vocabulary shows "PENDING" instead of "READY"
- **Check**: `aws transcribe get-vocabulary --vocabulary-name medspa-vocabulary --query VocabularyState`
- **Fix**: Wait 2-3 minutes — vocabulary creation is async. If it shows "FAILED", check the vocabulary file format and re-create.

### Cognito credentials fail
- **Check**: `aws cognito-identity get-id --identity-pool-id us-east-1:76dedb29-db76-475f-bdb2-aafcfa06fe8b`
- **Fix**: Verify the identity pool exists and unauthenticated access is enabled. Check the IAM role trust policy.

### Session not found after creation
- **Check**: Copy the exact `sessionId` from the POST /sessions response
- **Likely cause**: Typo in the session ID or DynamoDB eventual consistency (rare)
- **Fix**: Wait 1 second and retry the GET
