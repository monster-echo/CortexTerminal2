# Mobile Release Secrets

This directory contains helper scripts for the existing `.github/workflows/mobile-release.yml` workflow.

## 1. Generate Android signing secrets

```bash
scripts/mobile-release/create-android-keystore.sh
```

The script writes local, git-ignored files under `.local/mobile-release/`:

- `cortexterminal-release.jks`
- `secrets.env`

Do not commit or paste these values into logs.

## 2. Append Google Play and Apple secrets

Add these values to `.local/mobile-release/secrets.env` after creating them in the developer consoles:

```bash
CORTEX_GOOGLE_PLAY_SERVICE_ACCOUNT_JSON='{"type":"service_account",...}'
CORTEX_CERTIFICATES_P12_BASE64='...'
CORTEX_CERTIFICATES_P12_PASSWORD='...'
CORTEX_IOS_PROVISIONING_PROFILE_BASE64='...'
CORTEX_APPLE_SIGNING_IDENTITY='Apple Distribution: ...'
CORTEX_APPLE_PROVISIONING_PROFILE_NAME='...'
CORTEX_APPSTORE_ISSUER_ID='...'
CORTEX_APPSTORE_API_KEY_ID='...'
CORTEX_APPSTORE_API_PRIVATE_KEY='-----BEGIN PRIVATE KEY-----...'
```

For file-based secrets, use:

```bash
scripts/mobile-release/append-secret-from-file.sh CORTEX_GOOGLE_PLAY_SERVICE_ACCOUNT_JSON ~/Downloads/google-service-account.json raw
scripts/mobile-release/append-secret-from-file.sh CORTEX_IOS_PROVISIONING_PROFILE_BASE64 ~/Downloads/profile.mobileprovision base64
scripts/mobile-release/append-secret-from-file.sh CORTEX_APPSTORE_API_PRIVATE_KEY ~/Downloads/AuthKey_XXXXXXXXXX.p8 raw
```

## 3. Sync to GitHub Actions Secrets

```bash
scripts/mobile-release/set-github-mobile-secrets.sh
```

The target repository defaults to `monster-echo/CortexTerminal2`. Override it with `GITHUB_REPOSITORY=owner/repo` if needed.

## Platform console checklist

- Android package name: `top.rwecho.cortexterminal`
- Google Play release track: `internal`
- iOS bundle id: `top.rwecho.cortexterminal`
- iOS upload target: TestFlight

The current workflow checks for `Xcode 26.2`. If the self-hosted runner uses another Xcode version, update the runner or workflow before triggering iOS release.

## Apple certificate helpers

Generate a CSR before creating the Apple Distribution certificate:

```bash
scripts/mobile-release/create-ios-csr.sh
```

After downloading the `.cer` file from Apple Developer, convert it to a `.p12` and append the p12 secrets:

```bash
scripts/mobile-release/import-ios-certificate.sh ~/Downloads/distribution.cer 'strong-p12-password'
```
