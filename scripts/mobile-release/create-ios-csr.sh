#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="$ROOT_DIR/.local/mobile-release"
KEY_PATH="$OUT_DIR/apple_distribution.key"
CSR_PATH="$OUT_DIR/apple_distribution.csr"
SUBJECT="${CORTEX_APPLE_CERT_SUBJECT:-/CN=CortexTerminal Apple Distribution/O=CortexTerminal/C=CN}"

if [[ -e "$KEY_PATH" || -e "$CSR_PATH" ]] && [[ "${FORCE:-0}" != "1" ]]; then
  echo "CSR assets already exist under $OUT_DIR" >&2
  echo "Set FORCE=1 to overwrite them." >&2
  exit 1
fi

mkdir -p "$OUT_DIR"
chmod 700 "$OUT_DIR"

openssl genrsa -out "$KEY_PATH" 2048 >/dev/null 2>&1
openssl req -new -key "$KEY_PATH" -out "$CSR_PATH" -subj "$SUBJECT"
chmod 600 "$KEY_PATH" "$CSR_PATH"

echo "Created Apple private key: $KEY_PATH"
echo "Created Apple certificate signing request: $CSR_PATH"
echo "Upload the CSR when creating an Apple Distribution certificate."
