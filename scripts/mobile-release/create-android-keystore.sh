#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="$ROOT_DIR/.local/mobile-release"
KEYSTORE_PATH="$OUT_DIR/corterm-release.jks"
SECRETS_PATH="$OUT_DIR/secrets.env"
KEY_ALIAS="${CORTEX_ANDROID_KEY_ALIAS:-corterm}"

if [[ -e "$KEYSTORE_PATH" && "${FORCE:-0}" != "1" ]]; then
  echo "Keystore already exists: $KEYSTORE_PATH" >&2
  echo "Set FORCE=1 to overwrite it." >&2
  exit 1
fi

mkdir -p "$OUT_DIR"
chmod 700 "$OUT_DIR"

KEYSTORE_PASSWORD="$(openssl rand -hex 32)"
KEY_PASSWORD="$(openssl rand -hex 32)"

keytool -genkeypair \
  -v \
  -keystore "$KEYSTORE_PATH" \
  -storetype JKS \
  -alias "$KEY_ALIAS" \
  -keyalg RSA \
  -keysize 4096 \
  -validity 10000 \
  -dname "CN=Corterm, OU=Mobile, O=Corterm, L=Shanghai, ST=Shanghai, C=CN" \
  -storepass "$KEYSTORE_PASSWORD" \
  -keypass "$KEY_PASSWORD" >/dev/null

KEYSTORE_BASE64="$(base64 < "$KEYSTORE_PATH" | tr -d '\n')"

{
  printf 'CORTEX_ANDROID_KEYSTORE_BASE64=%q\n' "$KEYSTORE_BASE64"
  printf 'CORTEX_ANDROID_KEYSTORE_PASSWORD=%q\n' "$KEYSTORE_PASSWORD"
  printf 'CORTEX_ANDROID_KEY_PASSWORD=%q\n' "$KEY_PASSWORD"
  printf 'CORTEX_ANDROID_KEY_ALIAS=%q\n' "$KEY_ALIAS"
} > "$SECRETS_PATH"

chmod 600 "$KEYSTORE_PATH" "$SECRETS_PATH"

keytool -list \
  -keystore "$KEYSTORE_PATH" \
  -storepass "$KEYSTORE_PASSWORD" \
  -alias "$KEY_ALIAS" >/dev/null

echo "Created Android release keystore: $KEYSTORE_PATH"
echo "Wrote Android GitHub secret values to: $SECRETS_PATH"
echo "Next: append Google Play and Apple values to $SECRETS_PATH, then run scripts/mobile-release/set-github-mobile-secrets.sh"
