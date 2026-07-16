#!/usr/bin/env python3
"""Update App Store Connect TestFlight whatsNew for the latest build."""
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
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
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

    apps = api_get(token, f"apps?filter%5BbundleId%5D={BUNDLE_ID}&limit=1")
    app_id = apps["data"][0]["id"]
    print(f"App ID: {app_id}")

    builds = api_get(token, f"builds?filter%5Bapp%5D={app_id}&sort=-uploadedDate&limit=1")
    if not builds.get("data"):
        fatal("No builds found")
    build_id = builds["data"][0]["id"]
    version_str = builds["data"][0]["attributes"]["version"]
    print(f"Latest build: {build_id} (version {version_str})")

    locs = api_get(token, f"builds/{build_id}/betaBuildLocalizations?limit=10")
    existing = {l["attributes"]["locale"]: l["id"] for l in locs.get("data", [])}
    print(f"Existing locales: {list(existing.keys())}")

    updated = 0
    for file_locale, api_locale in LOCALES.items():
        file_path = os.path.join(whatsnew_dir, f"whatsnew-{file_locale}")
        text = read_whatsnew(file_path)
        if text is None:
            print(f"  {file_locale}: file not found, skipping")
            continue

        if api_locale in existing:
            loc_id = existing[api_locale]
            body = {"data": {"type": "betaBuildLocalizations", "id": loc_id, "attributes": {"whatsNew": text}}}
            status = api_patch(token, f"betaBuildLocalizations/{loc_id}", body)
            print(f"  {file_locale} ({api_locale}): PATCH HTTP {status} ({len(text)} chars)")
        else:
            body = {"data": {"type": "betaBuildLocalizations", "attributes": {"locale": api_locale, "whatsNew": text}, "relationships": {"build": {"data": {"type": "builds", "id": build_id}}}}}
            data = json.dumps(body).encode()
            req = urllib.request.Request("https://api.appstoreconnect.apple.com/v1/betaBuildLocalizations", data=data, headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"}, method="POST")
            resp = urllib.request.urlopen(req)
            status = resp.status
            print(f"  {file_locale} ({api_locale}): POST HTTP {status} ({len(text)} chars)")

        if status not in (200, 201):
            fatal(f"Failed to update {file_locale}: HTTP {status}")
        updated += 1

    if updated == 0:
        fatal("No localizations were updated")
    print(f"\nDone. Updated {updated} localization(s).")

if __name__ == "__main__":
    main()
