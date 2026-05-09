#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SECRETS_PATH="${1:-$ROOT_DIR/.local/mobile-release/secrets.env}"
REPO="${GITHUB_REPOSITORY:-monster-echo/CortexTerminal2}"

if [[ ! -f "$SECRETS_PATH" ]]; then
  echo "Secret file not found: $SECRETS_PATH" >&2
  exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "GitHub CLI is required: https://cli.github.com/" >&2
  exit 1
fi

set -a
# shellcheck source=/dev/null
source "$SECRETS_PATH"
set +a

required=(
  CORTEX_ANDROID_KEYSTORE_BASE64
  CORTEX_ANDROID_KEYSTORE_PASSWORD
  CORTEX_ANDROID_KEY_PASSWORD
  CORTEX_ANDROID_KEY_ALIAS
  CORTEX_GOOGLE_PLAY_SERVICE_ACCOUNT_JSON
  CORTEX_CERTIFICATES_P12_BASE64
  CORTEX_CERTIFICATES_P12_PASSWORD
  CORTEX_IOS_PROVISIONING_PROFILE_BASE64
  CORTEX_APPLE_SIGNING_IDENTITY
  CORTEX_APPLE_PROVISIONING_PROFILE_NAME
  CORTEX_APPSTORE_ISSUER_ID
  CORTEX_APPSTORE_API_KEY_ID
  CORTEX_APPSTORE_API_PRIVATE_KEY
)

missing=()
for name in "${required[@]}"; do
  if [[ -z "${!name:-}" ]]; then
    missing+=("$name")
  fi
done

if (( ${#missing[@]} > 0 )); then
  echo "Missing required secrets in $SECRETS_PATH:" >&2
  printf '  %s\n' "${missing[@]}" >&2
  exit 1
fi

for name in "${required[@]}"; do
  gh secret set "$name" --repo "$REPO" --body "${!name}"
  echo "Set GitHub secret: $name"
done

echo "All mobile release secrets were written to $REPO."
