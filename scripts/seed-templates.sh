#!/usr/bin/env bash
set -euo pipefail
REGION="${AWS_REGION:-us-east-1}"
TABLE="medspa-templates"

aws dynamodb put-item --table-name "$TABLE" --region "$REGION" --item '{
  "templateId": {"S": "neuromodulator"},
  "name": {"S": "Neuromodulator Treatment Form"},
  "fields": {"M": {
    "patientName": {"M": {"type": {"S": "string"}, "label": {"S": "Patient Name"}}},
    "dateOfService": {"M": {"type": {"S": "string"}, "label": {"S": "Date of Service"}}},
    "provider": {"M": {"type": {"S": "string"}, "label": {"S": "Provider"}}},
    "product": {"M": {"type": {"S": "string"}, "label": {"S": "Product (Botox/Dysport)"}}},
    "totalUnits": {"M": {"type": {"S": "number"}, "label": {"S": "Total Units"}}},
    "treatmentAreas": {"M": {"type": {"S": "array"}, "label": {"S": "Treatment Areas"}, "items": {"M": {"area": {"M": {"type": {"S": "string"}}}, "units": {"M": {"type": {"S": "number"}}}}}}},
    "lotNumber": {"M": {"type": {"S": "string"}, "label": {"S": "Lot Number"}}},
    "dilution": {"M": {"type": {"S": "string"}, "label": {"S": "Dilution"}}},
    "needleSize": {"M": {"type": {"S": "string"}, "label": {"S": "Needle Size"}}},
    "consentObtained": {"M": {"type": {"S": "boolean"}, "label": {"S": "Informed Consent Obtained"}}},
    "prePhotos": {"M": {"type": {"S": "boolean"}, "label": {"S": "Pre-Treatment Photos Taken"}}},
    "adverseReactions": {"M": {"type": {"S": "string"}, "label": {"S": "Adverse Reactions"}}},
    "postCareInstructions": {"M": {"type": {"S": "string"}, "label": {"S": "Post-Care Instructions Given"}}},
    "followUpDate": {"M": {"type": {"S": "string"}, "label": {"S": "Follow-Up Date"}}},
    "notes": {"M": {"type": {"S": "string"}, "label": {"S": "Additional Notes"}}}
  }}
}'

aws dynamodb put-item --table-name "$TABLE" --region "$REGION" --item '{
  "templateId": {"S": "filler"},
  "name": {"S": "Filler Treatment Form"},
  "fields": {"M": {
    "patientName": {"M": {"type": {"S": "string"}, "label": {"S": "Patient Name"}}},
    "dateOfService": {"M": {"type": {"S": "string"}, "label": {"S": "Date of Service"}}},
    "provider": {"M": {"type": {"S": "string"}, "label": {"S": "Provider"}}},
    "product": {"M": {"type": {"S": "string"}, "label": {"S": "Product (Juvederm/Restylane/Sculptra/Radiesse)"}}},
    "totalSyringes": {"M": {"type": {"S": "number"}, "label": {"S": "Total Syringes"}}},
    "treatmentAreas": {"M": {"type": {"S": "array"}, "label": {"S": "Treatment Areas"}, "items": {"M": {"area": {"M": {"type": {"S": "string"}}}, "syringes": {"M": {"type": {"S": "number"}}}, "technique": {"M": {"type": {"S": "string"}}}}}}},
    "lotNumber": {"M": {"type": {"S": "string"}, "label": {"S": "Lot Number"}}},
    "anesthetic": {"M": {"type": {"S": "string"}, "label": {"S": "Anesthetic Used"}}},
    "cannulaOrNeedle": {"M": {"type": {"S": "string"}, "label": {"S": "Cannula or Needle"}}},
    "aspirationPerformed": {"M": {"type": {"S": "boolean"}, "label": {"S": "Aspiration Performed"}}},
    "consentObtained": {"M": {"type": {"S": "boolean"}, "label": {"S": "Informed Consent Obtained"}}},
    "prePhotos": {"M": {"type": {"S": "boolean"}, "label": {"S": "Pre-Treatment Photos Taken"}}},
    "complications": {"M": {"type": {"S": "string"}, "label": {"S": "Complications"}}},
    "postCareInstructions": {"M": {"type": {"S": "string"}, "label": {"S": "Post-Care Instructions Given"}}},
    "followUpDate": {"M": {"type": {"S": "string"}, "label": {"S": "Follow-Up Date"}}},
    "notes": {"M": {"type": {"S": "string"}, "label": {"S": "Additional Notes"}}}
  }}
}'

aws dynamodb put-item --table-name "$TABLE" --region "$REGION" --item '{
  "templateId": {"S": "aesthetic"},
  "name": {"S": "Aesthetic Treatment Form"},
  "fields": {"M": {
    "patientName": {"M": {"type": {"S": "string"}, "label": {"S": "Patient Name"}}},
    "dateOfService": {"M": {"type": {"S": "string"}, "label": {"S": "Date of Service"}}},
    "provider": {"M": {"type": {"S": "string"}, "label": {"S": "Provider"}}},
    "treatmentType": {"M": {"type": {"S": "string"}, "label": {"S": "Treatment Type (microneedling/dermaplaning/chemical peel/IPL/laser)"}}},
    "treatmentAreas": {"M": {"type": {"S": "array"}, "label": {"S": "Treatment Areas"}, "items": {"M": {"area": {"M": {"type": {"S": "string"}}}, "settings": {"M": {"type": {"S": "string"}}}}}}},
    "skinType": {"M": {"type": {"S": "string"}, "label": {"S": "Skin Type (Fitzpatrick)"}}},
    "productsUsed": {"M": {"type": {"S": "string"}, "label": {"S": "Products/Serums Used"}}},
    "deviceSettings": {"M": {"type": {"S": "string"}, "label": {"S": "Device Settings"}}},
    "consentObtained": {"M": {"type": {"S": "boolean"}, "label": {"S": "Informed Consent Obtained"}}},
    "prePhotos": {"M": {"type": {"S": "boolean"}, "label": {"S": "Pre-Treatment Photos Taken"}}},
    "skinResponse": {"M": {"type": {"S": "string"}, "label": {"S": "Skin Response (erythema/edema)"}}},
    "postCareInstructions": {"M": {"type": {"S": "string"}, "label": {"S": "Post-Care Instructions Given"}}},
    "followUpDate": {"M": {"type": {"S": "string"}, "label": {"S": "Follow-Up Date"}}},
    "contraindications": {"M": {"type": {"S": "string"}, "label": {"S": "Contraindications Reviewed"}}},
    "notes": {"M": {"type": {"S": "string"}, "label": {"S": "Additional Notes"}}}
  }}
}'

echo "Seeded 3 templates: neuromodulator, filler, aesthetic"
