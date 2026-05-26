import jwt, time, requests, sys, os, hashlib

KEY_ID = 'WDXGY9WX55'
ISSUER = '2be0734f-943a-4d61-9dc9-5d9045c46fec'
APP_ID = '6773141126'

p8 = open('/tmp/asc_key.p8').read()

def make_token():
    return jwt.encode(
        {'iss': ISSUER, 'iat': int(time.time()), 'exp': int(time.time()) + 1200, 'aud': 'appstoreconnect-v1'},
        p8, algorithm='ES256', headers={'kid': KEY_ID}
    )

def headers():
    return {'Authorization': f'Bearer {make_token()}', 'Content-Type': 'application/json'}

def api(method, path, **kwargs):
    return requests.request(method, f'https://api.appstoreconnect.apple.com/v1{path}', headers=headers(), **kwargs)

def upload_screenshot(loc_id, display_type, filepath):
    file_size = os.path.getsize(filepath)
    file_name = os.path.basename(filepath)

    r = api('GET', f'/appStoreVersionLocalizations/{loc_id}/appScreenshotSets?filter[screenshotDisplayType]={display_type}')
    sets = r.json().get('data', [])
    if sets:
        set_id = sets[0]['id']
    else:
        r = api('POST', '/appScreenshotSets', json={
            'data': {
                'type': 'appScreenshotSets',
                'attributes': {'screenshotDisplayType': display_type},
                'relationships': {
                    'appStoreVersionLocalization': {'data': {'type': 'appStoreVersionLocalizations', 'id': loc_id}}
                }
            }
        })
        if r.status_code not in (200, 201):
            print(f'  Failed to create screenshot set: {r.status_code} {r.text[:200]}')
            return False
        set_id = r.json()['data']['id']

    with open(filepath, 'rb') as f:
        file_data = f.read()
    checksum = hashlib.md5(file_data).hexdigest()

    r = api('POST', '/appScreenshots', json={
        'data': {
            'type': 'appScreenshots',
            'attributes': {'fileName': file_name, 'fileSize': file_size},
            'relationships': {
                'appScreenshotSet': {'data': {'type': 'appScreenshotSets', 'id': set_id}}
            }
        }
    })
    if r.status_code not in (200, 201):
        print(f'  Failed to reserve screenshot: {r.status_code} {r.text[:200]}')
        return False

    screenshot_data = r.json()['data']
    screenshot_id = screenshot_data['id']
    upload_ops = screenshot_data['attributes']['uploadOperations']

    for op in upload_ops:
        upload_headers = {h['name']: h['value'] for h in op['requestHeaders']}
        offset = op['offset']
        length = op['length']
        chunk = file_data[offset:offset + length]
        r = requests.put(op['url'], headers=upload_headers, data=chunk)
        if r.status_code not in (200, 201):
            print(f'  Upload chunk failed: {r.status_code}')
            return False

    r = api('PATCH', f'/appScreenshots/{screenshot_id}', json={
        'data': {
            'type': 'appScreenshots',
            'id': screenshot_id,
            'attributes': {'uploaded': True, 'sourceFileChecksum': checksum}
        }
    })
    if r.status_code == 200:
        print(f'  Screenshot uploaded: {display_type}')
        return True
    else:
        print(f'  Commit failed: {r.status_code} {r.text[:200]}')
        return False

screenshot_dir = sys.argv[1] if len(sys.argv) > 1 else 'screenshots'

r = api('GET', f'/apps/{APP_ID}/appStoreVersions?filter[platform]=IOS&limit=1')
version_id = r.json()['data'][0]['id']

r = api('GET', f'/appStoreVersions/{version_id}/appStoreVersionLocalizations')
locs = r.json()['data']

for loc in locs:
    loc_id = loc['id']
    locale = loc['attributes']['locale']
    print(f'Processing locale: {locale}')
    path_67 = os.path.join(screenshot_dir, 'iphone_67.png')
    if os.path.exists(path_67):
        upload_screenshot(loc_id, 'APP_IPHONE_67', path_67)

print('Done!')
