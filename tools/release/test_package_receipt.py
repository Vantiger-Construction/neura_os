import hashlib
import json
from pathlib import Path
import struct
import subprocess
import tempfile
import unittest
import zipfile

from package_receipt import archive_windows, source_identity, windows_manifest


class PackageReceiptTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.bundle = self.root / 'Release'
        (self.bundle / 'data' / 'flutter_assets').mkdir(parents=True)
        pe = bytearray(70)
        pe[:2] = b'MZ'
        struct.pack_into('<I', pe, 60, 64)
        pe[64:70] = b'PE\0\0\x64\x86'
        for name in ['neuro_companion.exe', 'flutter_windows.dll']:
            (self.bundle / name).write_bytes(pe)
        (self.bundle / 'data' / 'icudtl.dat').write_bytes(b'synthetic ICU')
        (self.bundle / 'data' / 'app.so').write_bytes(b'synthetic AOT')
        (self.bundle / 'data' / 'flutter_assets' / 'synthetic.txt').write_bytes(b'synthetic asset')

    def test_archive_contains_every_manifest_file_and_verifies_payload_hashes(self):
        files = windows_manifest(self.bundle)
        manifest = self.root / 'PACKAGE_MANIFEST.json'
        manifest.write_text(json.dumps({'files': files}), encoding='utf-8')
        archive = archive_windows(self.bundle, files, manifest, self.root)
        with zipfile.ZipFile(archive) as stream:
            self.assertEqual(len(stream.namelist()), len(files) + 1)
            for record in files:
                self.assertEqual(hashlib.sha256(stream.read(record['path'])).hexdigest(), record['sha256'])
        self.assertIn(hashlib.sha256(archive.read_bytes()).hexdigest(), (self.root / 'SHA256SUMS.txt').read_text())

    def test_missing_or_empty_aot_payload_is_rejected(self):
        (self.bundle / 'data' / 'app.so').write_bytes(b'')
        with self.assertRaisesRegex(ValueError, 'Missing Windows Release payload'):
            windows_manifest(self.bundle)

    def test_non_windows_executable_is_rejected(self):
        (self.bundle / 'neuro_companion.exe').write_bytes(b'synthetic text')
        with self.assertRaisesRegex(ValueError, 'Not a Windows PE'):
            windows_manifest(self.bundle)

    def test_wrong_machine_is_rejected(self):
        path = self.bundle / 'neuro_companion.exe'
        data = bytearray(path.read_bytes())
        data[68:70] = b'\x4c\x01'
        path.write_bytes(data)
        with self.assertRaisesRegex(ValueError, 'Not an x64 PE'):
            windows_manifest(self.bundle)

    def test_payload_drift_after_manifest_is_rejected(self):
        files = windows_manifest(self.bundle)
        (self.bundle / 'data' / 'app.so').write_bytes(b'changed synthetic AOT')
        manifest = self.root / 'PACKAGE_MANIFEST.json'
        manifest.write_text('{}', encoding='utf-8')
        with self.assertRaisesRegex(ValueError, 'changed during packaging'):
            archive_windows(self.bundle, files, manifest, self.root)

    def test_link_to_external_payload_is_rejected(self):
        (self.root / 'outside.txt').write_bytes(b'synthetic external file')
        (self.bundle / 'external.txt').symlink_to(self.root / 'outside.txt')
        with self.assertRaisesRegex(ValueError, 'cannot contain links'):
            windows_manifest(self.bundle)


class SourceReceiptTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        (self.root / 'rust').mkdir()
        (self.root / 'pubspec.lock').write_text('synthetic pub lock\n', encoding='utf-8')
        (self.root / 'rust' / 'Cargo.lock').write_text('synthetic cargo lock\n', encoding='utf-8')
        self.git('init')
        self.git('config', 'user.name', 'Synthetic receipt test')
        self.git('config', 'user.email', 'synthetic@example.invalid')
        self.git('config', 'commit.gpgsign', 'false')
        self.git('add', '.')
        self.git('commit', '-m', 'Synthetic baseline')

    def git(self, *args):
        return subprocess.check_output(['git', '-C', str(self.root), *args], text=True,
                                       stderr=subprocess.DEVNULL).strip()

    def test_receipt_records_checkout_tree_and_actual_consumed_lock_bytes(self):
        receipt = source_identity(self.root)
        self.assertEqual(receipt['commit'], self.git('rev-parse', 'HEAD'))
        self.assertEqual(receipt['tree'], self.git('rev-parse', 'HEAD^{tree}'))
        for name, digest in receipt['locks'].items():
            self.assertEqual(digest, hashlib.sha256((self.root / name).read_bytes()).hexdigest())

    def test_staged_and_unstaged_source_changes_cannot_claim_the_committed_identity(self):
        (self.root / 'pubspec.lock').write_text('changed synthetic lock\n', encoding='utf-8')
        with self.assertRaisesRegex(ValueError, 'differs from HEAD'):
            source_identity(self.root)
        self.git('add', 'pubspec.lock')
        with self.assertRaisesRegex(ValueError, 'differs from HEAD'):
            source_identity(self.root)


if __name__ == '__main__':
    unittest.main()
