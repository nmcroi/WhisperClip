#!/usr/bin/env python3
"""Package an existing Release app for Developer ID distribution (no publication).
Credentials are arguments/environment only; never written into the DMG.
Notarizes/staples the app BEFORE creating, notarizing and stapling the DMG.
"""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess


def run(*args):
    return subprocess.run([str(a) for a in args], check=True, capture_output=True).stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--profile', required=True, type=Path)
    parser.add_argument('--identity', required=True)
    parser.add_argument('--team', required=True)
    args = parser.parse_args()
    auth = ['--key', os.environ['NOTARY_KEY_PATH'], '--key-id', os.environ['NOTARY_KEY_ID'],
            '--issuer', os.environ['NOTARY_ISSUER']]
    profile = plistlib.loads(run('security', 'cms', '-D', '-i', args.profile))
    assert profile.get('ProvisionsAllDevices'), 'Device-limited profile is not a distributable build'
    assert profile['ExpirationDate'] > datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None)
    grants = profile['Entitlements']
    assert grants['com.apple.developer.icloud-container-environment'] == 'Production'
    info = plistlib.loads((args.app / 'Contents/Info.plist').read_bytes())
    bundle = info['CFBundleIdentifier']
    assert grants['com.apple.application-identifier'] == args.team + '.' + bundle
    version, build = info['CFBundleShortVersionString'], info['CFBundleVersion']
    args.output.mkdir(parents=True, exist_ok=False)
    app = args.output / 'WhisperClip.app'
    run('ditto', args.app, app)
    shutil.copy2(args.profile, app / 'Contents/embedded.provisionprofile')
    entitlements = {
        'com.apple.security.device.audio-input': True,
        'com.apple.application-identifier': grants['com.apple.application-identifier'],
        'com.apple.developer.team-identifier': args.team,
        'com.apple.developer.icloud-services': ['CloudKit'],
        'com.apple.developer.icloud-container-identifiers': ['iCloud.' + bundle],
        'com.apple.developer.icloud-container-environment': 'Production',
        'com.apple.developer.ubiquity-kvstore-identifier': args.team + '.' + bundle,
    }
    ent = args.output / 'signing-entitlements.plist'
    ent.write_bytes(plistlib.dumps(entitlements))
    def sign(path, extra=()):
        run('codesign', '--force', '--timestamp', '--options', 'runtime', '--sign', args.identity, *extra, path)
    print('Signing nested code and app', flush=True)
    for p in app.rglob('*'):
        if p.is_file() and not p.is_symlink() and 'Mach-O' in run('file', '-b', p).decode():
            sign(p)
    bundles = [p for p in app.rglob('*') if p.is_dir() and not p.is_symlink() and p.suffix in ('.app', '.xpc', '.framework')]
    for p in sorted(bundles, key=lambda p: len(p.parts), reverse=True):
        sign(p)
    sign(app, ('--entitlements', ent))
    run('codesign', '--verify', '--deep', '--strict', app)
    def notarize(path, label):
        print('Apple notarization: ' + label, flush=True)
        result = json.loads(run('xcrun', 'notarytool', 'submit', path, *auth, '--wait', '--output-format', 'json'))
        (args.output / (label + '-notary.json')).write_text(json.dumps(result, indent=2))
        if result.get('status') != 'Accepted':
            log = run('xcrun', 'notarytool', 'log', result['id'], *auth)
            (args.output / (label + '-notary-log.json')).write_bytes(log)
            raise RuntimeError('Apple did not accept ' + label + '; inspect local log')
        run('xcrun', 'stapler', 'staple', path)
        run('xcrun', 'stapler', 'validate', path)
    archive = args.output / 'notarization.zip'
    run('ditto', '-c', '-k', '--keepParent', app, archive)
    # The upload is a ZIP; the notarization ticket belongs on its app.
    print('Apple notarization: app', flush=True)
    result = json.loads(run('xcrun', 'notarytool', 'submit', archive, *auth, '--wait', '--output-format', 'json'))
    (args.output / 'app-notary.json').write_text(json.dumps(result, indent=2))
    if result.get('status') != 'Accepted':
        (args.output / 'app-notary-log.json').write_bytes(run('xcrun', 'notarytool', 'log', result['id'], *auth))
        raise RuntimeError('Apple did not accept app')
    run('xcrun', 'stapler', 'staple', app)
    run('xcrun', 'stapler', 'validate', app)
    run('spctl', '--assess', '--type', 'execute', '--verbose=2', app)
    stage = args.output / 'dmg-content'
    stage.mkdir()
    run('ditto', app, stage / app.name)
    (stage / 'Applications').symlink_to('/Applications')
    shutil.copy2(Path(__file__).with_name('WERK_MAC_INSTALLATIE.txt'), stage / 'LEESMIJ.txt')
    shutil.copy2(Path(__file__).with_name('Controleer en maak backup.command'), stage / 'Controleer en maak backup.command')
    dmg = args.output / ('WhisperClip-' + version + '.dmg')
    run('hdiutil', 'create', '-volname', 'WhisperClip ' + version, '-srcfolder', stage, '-fs', 'HFS+', '-format', 'UDZO', dmg)
    run('codesign', '--force', '--timestamp', '--sign', args.identity, dmg)
    notarize(dmg, 'dmg')
    run('spctl', '--assess', '--type', 'open', '--context', 'context:primary-signature', '--verbose=2', dmg)
    (args.output / 'manifest.json').write_text(json.dumps({
        'version': version, 'build': build, 'configuration': 'Release',
        'database': 'history.db', 'cloudKitEnvironment': 'Production',
        'sha256': hashlib.sha256(dmg.read_bytes()).hexdigest(),
        'notarized': True, 'stapledAppInsideDMG': True,
    }, indent=2) + '\n')
    print('READY: ' + str(dmg), flush=True)

if __name__ == '__main__':
    main()
