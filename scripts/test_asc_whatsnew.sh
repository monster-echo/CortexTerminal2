#!/bin/bash
set -euo pipefail

ISSUER_ID="$1"
KEY_ID="$2"
PRIVATE_KEY="$3"

KEY_FILE=$(mktemp)
printf '%s\n' "$PRIVATE_KEY" > "$KEY_FILE"
trap "rm -f $KEY_FILE" EXIT

header=$(printf '{"alg":"ES256","kid":"%s","typ":"JWT"}' "$KEY_ID" | base64 | tr -d '=' | tr '/+' '_-')
payload=$(printf '{"iss":"%s","iat":%d,"exp":%d,"aud":"appstoreconnect-v1"}' "$ISSUER_ID" $(date +%s) $(($(date +%s)+600)) | base64 | tr -d '=' | tr '/+' '_-')
signature=$(printf '%s.%s' "$header" "$payload" | openssl dgst -sha256 -sign "$KEY_FILE" | base64 | tr -d '=' | tr '/+' '_-')
JWT="${header}.${payload}.${signature}"

echo "=== Step 1: Find app ==="
HTTP_CODE=$(curl -s -o /tmp/asc_app.json -w "%{http_code}" -H "Authorization: Bearer $JWT" \
  "https://api.appstoreconnect.apple.com/v1/apps?filter[bundleId]=top.rwecho.cortexterminal&limit=1")
echo "HTTP $HTTP_CODE"
cat /tmp/asc_app.json | python3 -m json.tool 2>&1 | head -10
