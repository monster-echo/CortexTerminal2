#!/bin/bash
set -euo pipefail

echo "ISSUER_ID length: ${#1}"
echo "KEY_ID length: ${#2}"  
echo "PRIVATE_KEY starts with: ${3:0:27}"

# Simple JWT test  
KEY_FILE=$(mktemp)
printf '%s\n' "$3" > "$KEY_FILE"
trap "rm -f $KEY_FILE" EXIT

header=$(printf '{"alg":"ES256","kid":"%s","typ":"JWT"}' "$2" | base64 -w0 | tr -d '=' | tr '/+' '_-')
payload=$(printf '{"iss":"%s","iat":%d,"exp":%d,"aud":"appstoreconnect-v1"}' "$1" $(date +%s) $(($(date +%s)+600)) | base64 -w0 | tr -d '=' | tr '/+' '_-')
signature=$(printf '%s.%s' "$header" "$payload" | openssl dgst -sha256 -sign "$KEY_FILE" | base64 -w0 | tr -d '=' | tr '/+' '_-')
JWT="${header}.${payload}.${signature}"

echo "JWT generated, length: ${#JWT}"

HTTP_CODE=$(curl -s -o /tmp/asc_resp.json -w "%{http_code}" -H "Authorization: Bearer $JWT" \
  "https://api.appstoreconnect.apple.com/v1/apps?filter[bundleId]=top.rwecho.cortexterminal&limit=1")
echo "HTTP: $HTTP_CODE"
head -c 500 /tmp/asc_resp.json