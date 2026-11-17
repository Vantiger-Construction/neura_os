"""Record verified debug APK identity; compare permissions without installing it."""

import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'release'))
from check_android_update import inspect_apk, sdk_output  # noqa: E402


def inspect(apk, build_tools, source):
    identity = inspect_apk(apk, build_tools)
    aapt = build_tools / ('aapt.exe' if sys.platform == 'win32' else 'aapt')
    badging = sdk_output([aapt, 'dump', 'badging', apk])
    permissions = sdk_output([aapt, 'dump', 'permissions', apk])
    granted = sorted(set(re.findall(r"^uses-permission(?:-sdk-\d+)?: name='([^']+)'", permissions, re.MULTILINE)))
    if identity['package'] != 'com.neurocompanion.app' or 'android.permission.RECORD_AUDIO' not in granted:
        raise ValueError('APK identity or required microphone declaration is missing')
    with zipfile.ZipFile(apk) as archive:
        abis = sorted({p.split('/')[1] for p in archive.namelist() if p.startswith('lib/') and p.endswith('.so')})
    if 'arm64-v8a' not in abis:
        raise ValueError('Required Samsung ARM64 native libraries are absent')
    identity.update(permissions=granted, native_abis=abis,
                    min_sdk=int(re.search(r"^sdkVersion:'(\d+)'", badging, re.MULTILINE)[1]),
                    target_sdk=int(re.search(r"^targetSdkVersion:'(\d+)'", badging, re.MULTILINE)[1]),
                    source_commit=sdk_output(['git', '-C', source, 'rev-parse', 'HEAD']).strip(),
                    source_tree=sdk_output(['git', '-C', source, 'rev-parse', 'HEAD^{tree}']).strip(),
                    acceptance='UNVERIFIED: no installation, data-preservation or physical Samsung result')
    identity['input_sha256'] = {
        p: hashlib.sha256((source / p).read_bytes()).hexdigest()
        for p in ('pubspec.lock', 'android/build.gradle.kts', 'android/gradle.properties',
                  'android/settings.gradle.kts', 'android/app/build.gradle.kts',
                  'android/gradle/wrapper/gradle-wrapper.properties', 'android/app/src/main/AndroidManifest.xml')
    }
    return identity


def compare(previous, candidate):
    if any(report.get('status') != 'signature-verified' for report in (previous, candidate)):
        raise ValueError('Both APK receipts must have verified signatures')
    differences = {key: dict(previous=previous[key], candidate=candidate[key])
                   for key in ('package', 'permissions', 'min_sdk', 'target_sdk', 'native_abis')
                   if previous[key] != candidate[key]}
    if differences:
        raise ValueError('APK identity/permission/platform regression: ' + json.dumps(differences))
    return dict(status='identity-and-permissions-unchanged',
                acceptance='UNVERIFIED: static artifact comparison only')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', required=True, type=Path)
    commands = parser.add_subparsers(dest='command', required=True)
    artifact = commands.add_parser('inspect')
    artifact.add_argument('--build-tools', required=True, type=Path)
    artifact.add_argument('--source', required=True, type=Path)
    artifact.add_argument('apk', type=Path)
    comparison = commands.add_parser('compare')
    comparison.add_argument('previous', type=Path)
    comparison.add_argument('candidate', type=Path)
    args = parser.parse_args()
    receipt = dict(status='incomplete')
    code = 2
    try:
        if args.command == 'inspect':
            receipt.update(inspect(args.apk.resolve(), args.build_tools.resolve(), args.source.resolve()))
            receipt['status'] = 'signature-verified'
        else:
            receipt.update(compare(json.loads(args.previous.read_text()), json.loads(args.candidate.read_text())))
        code = 0
    except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError, zipfile.BadZipFile) as error:
        receipt['error'] = str(error)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps(receipt, indent=2))
    return code


if __name__ == '__main__':
    sys.exit(main())
