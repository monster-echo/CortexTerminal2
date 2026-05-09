#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SECRETS_PATH="${1:-$ROOT_DIR/.local/mobile-release/secrets.env}"
REPO="${GITHUB_REPOSITORY:-monster-echo/CortexTerminal2}"

set -a
# shellcheck source=/dev/null
source "$SECRETS_PATH"
set +a

for name in \
  CORTEX_ANDROID_KEYSTORE_BASE64 \
  CORTEX_ANDROID_KEYSTORE_PASSWORD \
  CORTEX_ANDROID_KEY_PASSWORD \
  CORTEX_ANDROID_KEY_ALIAS
do
  if [[ -z "${!name:-}" ]]; then
    echo "Missing required secret: $name" >&2
    exit 1
  fi
  gh secret set "$name" --repo "$REPO" --body "${!name}"
  echo "Set GitHub secret: $name"
done
