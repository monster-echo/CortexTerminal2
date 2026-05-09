#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="$ROOT_DIR/.local/mobile-release"
CERT_PATH="${1:-}"
P12_PASSWORD="${2:-}"
KEY_PATH="$OUT_DIR/apple_distribution.key"
P12_PATH="$OUT_DIR/apple_distribution.p12"
SECRETS_PATH="$OUT_DIR/secrets.env"

if [[ -z "$CERT_PATH" || -z "$P12_PASSWORD" ]]; then
  echo "Usage: $0 /path/to/apple_distribution.cer p12-password" >&2
  exit 1
fi

if [[ ! -f "$CERT_PATH" ]]; then
  echo "Certificate not found: $CERT_PATH" >&2
  exit 1
fi

if [[ ! -f "$KEY_PATH" ]]; then
  echo "Private key not found: $KEY_PATH" >&2
  echo "Run scripts/mobile-release/create-ios-csr.sh first." >&2
  exit 1
fi

CERT_PEM="$OUT_DIR/apple_distribution.pem"
openssl x509 -inform DER -in "$CERT_PATH" -out "$CERT_PEM"
openssl pkcs12 -export \
  -inkey "$KEY_PATH" \
  -in "$CERT_PEM" \
  -out "$P12_PATH" \
  -passout "pass:$P12_PASSWORD"

P12_BASE64="$(base64 < "$P12_PATH" | tr -d '\n')"

{
  printf '\n'
  printf 'CORTEX_CERTIFICATES_P12_BASE64=%q\n' "$P12_BASE64"
  printf 'CORTEX_CERTIFICATES_P12_PASSWORD=%q\n' "$P12_PASSWORD"
} >> "$SECRETS_PATH"

chmod 600 "$CERT_PEM" "$P12_PATH" "$SECRETS_PATH"

echo "Created Apple distribution p12: $P12_PATH"
echo "Appended p12 GitHub secret values to: $SECRETS_PATH"
