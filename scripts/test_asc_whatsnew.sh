#!/bin/bash
# Test App Store Connect API permission to update whatsNew.
# Uses same secrets as mobile-release.yml.
set -euo pipefail

ISSUER_ID="$1"
KEY_ID="$2"
PRIVATE_KEY="$3"

# Write private key to temp file
KEY_FILE=$(mktemp)
printf '%s\n' "$PRIVATE_KEY" > "$KEY_FILE"
trap "rm -f $KEY_FILE" EXIT

# Generate JWT
header=$(printf '{"alg":"ES256","kid":"%s","typ":"JWT"}' "$KEY_ID" | base64 | tr -d '=' | tr '/+' '_-')
payload=$(printf '{"iss":"%s","iat":%d,"exp":%d,"aud":"appstoreconnect-v1"}' "$ISSUER_ID" $(date +%s) $(($(date +%s)+600)) | base64 | tr -d '=' | tr '/+' '_-')
signature=$(printf '%s.%s' "$header" "$payload" | openssl dgst -sha256 -sign "$KEY_FILE" | base64 | tr -d '=' | tr '/+' '_-')
JWT="${header}.${payload}.${signature}"

echo "=== Step 1: Find app ==="
APP_RESP=$(curl -sf -H "Authorization: Bearer $JWT" \
  "https://api.appstoreconnect.apple.com/v1/apps?filter[bundleId]=top.rwecho.cortexterminal&limit=1")
APP_ID=$(echo "$APP_RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['data'][0]['id'])")
echo "App ID: $APP_ID"

echo "=== Step 2: Find latest App Store Version ==="
VERSION_RESP=$(curl -sf -H "Authorization: Bearer $JWT" \
  "https://api.appstoreconnect.apple.com/v1/apps/$APP_ID/appStoreVersions?limit=1&sort=-createdDate")
VERSION_ID=$(echo "$VERSION_RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['data'][0]['id'])")
echo "Version ID: $VERSION_ID"

echo "=== Step 3: Read current whatsNew ==="
curl -sf -H "Authorization: Bearer $JWT" \
  "https://api.appstoreconnect.apple.com/v1/appStoreVersions/$VERSION_ID?fields[appStoreVersions]=whatsNew" \
  | python3 -m json.tool

echo ""
echo "SUCCESS: API key can read appStoreVersions."
echo "To write whatsNew, key needs App Manager role (Developer can read but not write)."
