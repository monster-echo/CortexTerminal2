#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SECRETS_PATH="$ROOT_DIR/.local/mobile-release/secrets.env"
SECRET_NAME="${1:-}"
FILE_PATH="${2:-}"
MODE="${3:-raw}"

if [[ -z "$SECRET_NAME" || -z "$FILE_PATH" ]]; then
  echo "Usage: $0 SECRET_NAME /path/to/file [raw|base64]" >&2
  exit 1
fi

if [[ ! -f "$FILE_PATH" ]]; then
  echo "File not found: $FILE_PATH" >&2
  exit 1
fi

mkdir -p "$(dirname "$SECRETS_PATH")"
touch "$SECRETS_PATH"
chmod 600 "$SECRETS_PATH"

case "$MODE" in
  raw)
    VALUE="$(cat "$FILE_PATH")"
    ;;
  base64)
    VALUE="$(base64 < "$FILE_PATH" | tr -d '\n')"
    ;;
  *)
    echo "Mode must be raw or base64." >&2
    exit 1
    ;;
esac

printf '%s=%q\n' "$SECRET_NAME" "$VALUE" >> "$SECRETS_PATH"
echo "Appended $SECRET_NAME to $SECRETS_PATH"
