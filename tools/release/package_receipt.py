"""Retain exact source, lock and native-payload identity without publishing it."""

import argparse
import hashlib
import json
from pathlib import Path
import struct
import subprocess
import zipfile

from check_android_update import inspect_apk


def sha256(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def source_identity(root):
    def git(*args):
        return subprocess.check_output(['git', '-C', str(root), *args], text=True).strip()
    # Do not attribute a generated/modified tracked source file to HEAD.
    if git('diff', 'HEAD', '--name-only'):
        raise ValueError('Tracked source differs from HEAD; package identity is incomplete.')
    locks = ['pubspec.lock', 'rust/Cargo.lock']
    return {
        'commit': git('rev-parse', 'HEAD'),
        'tree': git('rev-parse', 'HEAD^{tree}'),
        'locks': {name: sha256(root / name) for name in locks},
    }


def require_x64_pe(path):
    with path.open('rb') as stream:
        dos = stream.read(64)
        if len(dos) < 64 or dos[:2] != b'MZ':
            raise ValueError(f'Not a Windows PE executable: {path.name}')
        stream.seek(struct.unpack_from('<I', dos, 60)[0])
        header = stream.read(6)
        if header != b'PE\0\0\x64\x86':
            raise ValueError(f'Not an x64 PE executable: {path.name}')


def windows_manifest(bundle):
    required = ['neuro_companion.exe', 'flutter_windows.dll', 'data/icudtl.dat', 'data/app.so']
    for relative in required:
        path = bundle / relative
        if not path.is_file() or path.stat().st_size == 0:
            raise ValueError(f'Missing Windows Release payload: {relative}')
    require_x64_pe(bundle / required[0])
    require_x64_pe(bundle / required[1])
    files = []
    for path in sorted(bundle.rglob('*')):
        if path.is_symlink():
            raise ValueError('A package cannot contain links outside its payload.')
        if path.is_file():
            files.append({'path': path.relative_to(bundle).as_posix(),
                          'size_bytes': path.stat().st_size, 'sha256': sha256(path)})
    return files


def archive_windows(bundle, files, manifest, output):
    archive = output / 'neura-windows-release.zip'
    with zipfile.ZipFile(archive, 'w', compression=zipfile.ZIP_DEFLATED) as stream:
        for record in files:
            path = bundle / record['path']
            # Detect an intervening write before recording an archive as verified.
            if sha256(path) != record['sha256']:
                raise ValueError('Windows payload changed during packaging.')
            stream.write(path, record['path'])
        stream.write(manifest, 'PACKAGE_MANIFEST.json')
    # Independently read the ZIP bytes; uploaded packaging must preserve every file.
    with zipfile.ZipFile(archive) as stream:
        expected = {record['path'] for record in files} | {'PACKAGE_MANIFEST.json'}
        if set(stream.namelist()) != expected or stream.testzip() is not None:
            raise ValueError('Archive payload inventory or CRC verification failed.')
        for record in files:
            with stream.open(record['path']) as payload:
                if hashlib.file_digest(payload, 'sha256').hexdigest() != record['sha256']:
                    raise ValueError('Archived payload hash differs from its manifest.')
    (output / 'SHA256SUMS.txt').write_text(
        f'{sha256(archive)}  {archive.name}\n{sha256(manifest)}  {manifest.name}\n', encoding='utf-8')
    return archive


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--platform', choices=['windows', 'android'], required=True)
    parser.add_argument('--root', type=Path, default=Path.cwd())
    parser.add_argument('--bundle', type=Path)
    parser.add_argument('--apk', type=Path)
    parser.add_argument('--build-tools', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    source = source_identity(args.root.resolve())
    receipt = {'schema': 1, 'platform': args.platform, 'source': source,
               'physical_acceptance': 'UNVERIFIED', 'release_approved': False}
    if args.platform == 'windows':
        if args.bundle is None:
            parser.error('--bundle is required for Windows')
        bundle = args.bundle.resolve()
        if args.output.resolve() == bundle or bundle in args.output.resolve().parents:
            parser.error('Evidence output must be outside the native Release bundle')
        files = windows_manifest(bundle)
        receipt.update(configuration='Release', files=files, executable_format='PE x64')
    else:
        if args.apk is None or args.build_tools is None:
            parser.error('--apk and --build-tools are required for Android')
        receipt.update(configuration='debug', test_signing_only=True,
                       apk=inspect_apk(args.apk.resolve(), args.build_tools.resolve()),
                       installed_app_upgrade='UNVERIFIED: compare installed signer and version before installation')
    args.output.mkdir(parents=True, exist_ok=True)
    manifest = args.output / 'PACKAGE_MANIFEST.json'
    manifest.write_text(json.dumps(receipt, indent=2) + '\n', encoding='utf-8')
    if args.platform == 'windows':
        archive_windows(bundle, files, manifest, args.output)
    print(json.dumps(receipt, indent=2))


if __name__ == '__main__':
    main()
