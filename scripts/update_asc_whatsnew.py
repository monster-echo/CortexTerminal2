#!/usr/bin/env python3
"""Update App Store Connect whatsNew for the latest app store version."""
import jwt, time, json, sys, urllib.request, os

BUNDLE_ID = "top.rwecho.cortexterminal"
LOCALES = {
    "zh-CN": "zh-Hans",
    "en-US": "en-US",
}

def fatal(msg):
    print(f"ERROR: {msg}", file=sys.stderr)
    sys.exit(1)

def make_jwt(issuer_id, key_id, key_path):
    with open(key_path) as f:
        private_key = f.read()
    now = int(time.time())
    return jwt.encode(
        {"iss": issuer_id, "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1"},
        private_key,
        algorithm="ES256",
        headers={"kid": key_id},
    )

def api_get(token, path):
    req = urllib.request.Request(
        f"https://api.appstoreconnect.apple.com/v1/{path}",
        headers={"Authorization": f"Bearer {token}"},
    )
    resp = urllib.request.urlopen(req)
    return json.loads(resp.read())

def api_patch(token, path, body):
    data = json.dumps(body).encode()
    req = urllib.request.Request(
        f"https://api.appstoreconnect.apple.com/v1/{path}",
        data=data,
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        },
        method="PATCH",
    )
    resp = urllib.request.urlopen(req)
    return resp.status

def read_whatsnew(file_path):
    if not os.path.exists(file_path):
        return None
    with open(file_path) as f:
        text = f.read().strip()
    return text if text else None

def main():
    issuer_id = os.environ["CORTEX_APPSTORE_ISSUER_ID"]
    key_id = os.environ["CORTEX_APPSTORE_API_KEY_ID"]
    key_path = os.environ.get("ASC_KEY_PATH", "/tmp/asc_key.p8")
    whatsnew_dir = sys.argv[1] if len(sys.argv) > 1 else "distribution/app-store"

    token = make_jwt(issuer_id, key_id, key_path)

    # Find app
    apps = api_get(token, f"apps?filter%5BbundleId%5D={BUNDLE_ID}&limit=1")
    app_id = apps["data"][0]["id"]
    print(f"App ID: {app_id}")

    # Find latest appStoreVersion
    versions = api_get(token, f"apps/{app_id}/appStoreVersions?limit=1&sort=-version")
    version_id = versions["data"][0]["id"]
    print(f"App Store Version ID: {version_id}")

    # Find localizations and update whatsNew
    locs = api_get(token, f"appStoreVersions/{version_id}/appStoreVersionLocalizations?limit=10")
    updated = 0
    for loc in locs["data"]:
        loc_id = loc["id"]
        loc_locale = loc["attributes"]["locale"]
        print(f"  Locale: {loc_locale} (id={loc_id})")

        # Find matching whatsnew file
        file_locale = None
        for fname, api_locale in LOCALES.items():
            if api_locale == loc_locale:
                file_locale = fname
                break

        if file_locale is None:
            print(f"    No whatsnew file for locale {loc_locale}, skipping")
            continue

        file_path = os.path.join(whatsnew_dir, f"whatsnew-{file_locale}")
        text = read_whatsnew(file_path)
        if text is None:
            print(f"    File {file_path} not found or empty, skipping")
            continue

        body = {
            "data": {
                "type": "appStoreVersionLocalizations",
                "id": loc_id,
                "attributes": {"whatsNew": text},
            }
        }
        status = api_patch(token, f"appStoreVersionLocalizations/{loc_id}", body)
        print(f"    Updated whatsNew ({file_locale}): HTTP {status} ({len(text)} chars)")
        updated += 1

    if updated == 0:
        fatal("No localizations were updated")
    print(f"\nDone. Updated {updated} localization(s).")

if __name__ == "__main__":
    main()
