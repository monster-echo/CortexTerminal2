"""Upload an Android bundle or verify an App Store Connect upload in Actions.

Credentials are supplied through Actions secrets; never written to build artifacts.
"""
import argparse
import json
import os
import time
import urllib.parse
import urllib.request
from pathlib import Path


def apple_get(path):
    import jwt
    key = os.environ['APPSTORE_PRIVATE_KEY'].replace('\\n', '\n')
    now = int(time.time())
    token = jwt.encode({'iss': os.environ['APPSTORE_ISSUER'], 'iat': now,
                        'exp': now + 900, 'aud': 'appstoreconnect-v1'}, key,
                       algorithm='ES256', headers={'kid': os.environ['APPSTORE_KEY_ID']})
    request = urllib.request.Request('https://api.appstoreconnect.apple.com/v1/' + path,
                                     headers={'Authorization': 'Bearer ' + token})
    with urllib.request.urlopen(request, timeout=60) as response:
        return json.load(response)


def verify_ios(build_number):
    apps = apple_get('apps?' + urllib.parse.urlencode({'filter[bundleId]': 'top.rwecho.cortexterminal'}))['data']
    if len(apps) != 1:
        raise RuntimeError('Expected exactly one Corterm App Store Connect app')
    app_id = apps[0]['id']
    deadline = time.monotonic() + 1200
    while time.monotonic() < deadline:
        builds = apple_get('builds?' + urllib.parse.urlencode({
            'filter[app]': app_id, 'filter[version]': build_number, 'limit': 10}))['data']
        if builds:
            state = builds[0]['attributes']['processingState']
            print(f'App Store Connect build {build_number}: {state}', flush=True)
            if state == 'VALID':
                return
            if state in ('FAILED', 'INVALID'):
                raise RuntimeError('Apple rejected processing of the uploaded build')
        else:
            print(f'Waiting for build {build_number} to appear in App Store Connect', flush=True)
        time.sleep(30)
    raise TimeoutError('Upload completed but Apple processing is still pending after 20 minutes')


def publish_android(aab, version):
    from google.oauth2.service_account import Credentials
    from googleapiclient.discovery import build
    from googleapiclient.errors import HttpError
    from googleapiclient.http import MediaFileUpload
    credentials = Credentials.from_service_account_info(
        json.loads(os.environ['GOOGLE_PLAY_SERVICE_ACCOUNT_JSON']),
        scopes=['https://www.googleapis.com/auth/androidpublisher'])
    api = build('androidpublisher', 'v3', credentials=credentials, cache_discovery=False)
    package = 'top.rwecho.cortexterminal'
    edit = api.edits().insert(packageName=package, body={}).execute()['id']
    bundle = api.edits().bundles().upload(packageName=package, editId=edit,
        media_body=MediaFileUpload(aab, mimetype='application/octet-stream', resumable=True)).execute(num_retries=3)
    code = str(bundle['versionCode'])
    notes = [
        {'language': 'zh-CN', 'text': '优化登录、工作区、会话和文件浏览体验；改进连接恢复与文件传输稳定性；完善会员权益、购买恢复和订阅管理界面。'},
        {'language': 'en-US', 'text': 'Improved sign-in, workspace, session and file browsing. Enhanced connection recovery and file transfer reliability. Refined membership benefits, purchase restoration and subscription management.'}]
    api.edits().tracks().update(packageName=package, editId=edit, track='internal', body={
        'track': 'internal', 'releases': [{'name': version, 'versionCodes': [code],
                                         'status': 'completed', 'releaseNotes': notes}]}).execute()
    try:
        api.edits().commit(packageName=package, editId=edit, changesNotSentForReview=True).execute()
    except HttpError as error:
        if error.resp.status != 400 or 'changesNotSentForReview' not in str(error):
            raise
        api.edits().commit(packageName=package, editId=edit).execute()
    check = api.edits().insert(packageName=package, body={}).execute()['id']
    try:
        track = api.edits().tracks().get(packageName=package, editId=check, track='internal').execute()
        if not any(code in release.get('versionCodes', []) for release in track.get('releases', [])):
            raise RuntimeError('Committed bundle missing from internal track')
        print(f'Google Play internal: {version} ({code}) committed and verified')
    finally:
        api.edits().delete(packageName=package, editId=check).execute()


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('platform', choices=['android', 'ios'])
    parser.add_argument('--aab')
    parser.add_argument('--version')
    parser.add_argument('--build')
    args = parser.parse_args()
    if args.platform == 'android':
        publish_android(args.aab, args.version)
    else:
        verify_ios(args.build)
