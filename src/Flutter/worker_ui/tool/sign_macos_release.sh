#!/bin/bash
# Credentials stay in the runner and are removed on every exit path.
set -euo pipefail
app="$1"
dmg="$2"
: "${RUNNER_TEMP:?}" "${SIGNING_P12:?}" "${SIGNING_PASSWORD:?}"
: "${API_PRIVATE_KEY:?}" "${API_KEY_ID:?}" "${API_ISSUER_ID:?}"
keychain="$RUNNER_TEMP/desktop-signing.keychain-db"
p12="$RUNNER_TEMP/desktop-signing.p12"
api_key="$RUNNER_TEMP/notary-api.p8"
entitlements="$RUNNER_TEMP/worker-signing.entitlements"
cleanup() {
  security delete-keychain "$keychain" >/dev/null 2>&1 || true
  rm -f "$p12" "$api_key" "$entitlements"
}
trap cleanup EXIT
umask 077
printf '%s' "$SIGNING_P12" | base64 --decode > "$p12"
printf '%s' "$API_PRIVATE_KEY" > "$api_key"
keychain_password="$(openssl rand -hex 24)"
security create-keychain -p "$keychain_password" "$keychain"
security unlock-keychain -p "$keychain_password" "$keychain"
security set-keychain-settings -lut 21600 "$keychain"
security import "$p12" -P "$SIGNING_PASSWORD" -k "$keychain" -T /usr/bin/codesign >/dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$keychain_password" "$keychain" >/dev/null
identity="$(security find-identity -v -p codesigning "$keychain" | sed -n '/Developer ID Application:/s/.*"\(.*\)"/\1/p' | head -n 1)"
test -n "$identity" || { echo 'No valid Developer ID Application identity'; exit 1; }
cat > "$entitlements" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>com.apple.security.cs.allow-jit</key><true/>
</dict></plist>
PLIST
# Sign real Mach-O files first, then enclosing frameworks and the app.
# Never use --deep for signing: nested worker code needs its own entitlements.
while IFS= read -r -d '' binary; do
  if file -b "$binary" | grep -q 'Mach-O'; then
    if [ "$(basename "$binary")" = corterm ]; then
      codesign --force --timestamp --options runtime --keychain "$keychain" --sign "$identity" --entitlements "$entitlements" "$binary"
    else
      codesign --force --timestamp --options runtime --keychain "$keychain" --sign "$identity" "$binary"
    fi
  fi
done < <(find "$app" -type f -print0)
while IFS= read -r -d '' framework; do
  codesign --force --timestamp --options runtime --keychain "$keychain" --sign "$identity" "$framework"
done < <(find "$app" -depth -type d -name '*.framework' -print0)
codesign --force --timestamp --options runtime --keychain "$keychain" --sign "$identity" "$app"
codesign --verify --deep --strict --verbose=2 "$app"
ln -s /Applications "$(dirname "$app")/Applications"
hdiutil create -volname '云枢终端' -srcfolder "$(dirname "$app")" -ov -format UDZO "$dmg"
codesign --timestamp --keychain "$keychain" --sign "$identity" "$dmg"
xcrun notarytool submit "$dmg" --key "$api_key" --key-id "$API_KEY_ID" --issuer "$API_ISSUER_ID" --wait --output-format json > "$RUNNER_TEMP/notary-result.json"
python3 -c 'import json,sys; r=json.load(open(sys.argv[1])); print("Notarization:",r["status"],r["id"]); sys.exit(0 if r["status"]=="Accepted" else 1)' "$RUNNER_TEMP/notary-result.json"
xcrun stapler staple "$dmg"
xcrun stapler validate "$dmg"
spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg"
