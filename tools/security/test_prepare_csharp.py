import hashlib
import io
from pathlib import Path
import tarfile
import tempfile
import unittest
from unittest.mock import patch

import prepare_csharp


class UnityReferenceExtractionTests(unittest.TestCase):
    def archive(self, root, members):
        path = root / 'fixture.tar.xz'
        with tarfile.open(path, 'w:xz') as archive:
            for name, data, link in members:
                member = tarfile.TarInfo(name)
                if link:
                    member.type = tarfile.SYMTYPE
                    member.linkname = link
                    archive.addfile(member)
                else:
                    member.size = len(data)
                    archive.addfile(member, io.BytesIO(data))
        return path

    def test_bad_archive_digest_fails_before_writing(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            archive = self.archive(root, [('Editor/Data/Managed/Test.dll', b'data', None)])
            output = root / 'sdk'
            with self.assertRaisesRegex(ValueError, 'SHA-256'):
                prepare_csharp.extract_sdk(archive, output)
            self.assertFalse(output.exists())

    def test_only_genuine_reference_package_files_are_selected_and_links_skipped(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            archive = self.archive(root, [
                ('Editor/Data/Managed/Test.dll', b'reference', None),
                ('Editor/Data/Resources/PackageManager/BuiltInPackages/com.unity.test-framework/LICENSE.md', b'license', None),
                ('Editor/Unity', b'never-launch-editor', None),
                ('Editor/Data/Managed/Link.dll', b'', '/outside'),
            ])
            output = root / 'sdk'
            with patch.object(prepare_csharp, 'SHA256', hashlib.sha256(archive.read_bytes()).hexdigest()):
                prepare_csharp.extract_sdk(archive, output)
            self.assertEqual((output / 'Editor/Data/Managed/Test.dll').read_bytes(), b'reference')
            self.assertFalse((output / 'Editor/Unity').exists())
            self.assertFalse((output / 'Editor/Data/Managed/Link.dll').exists())
            self.assertTrue(next(output.rglob('LICENSE.md')).is_file())

    def test_selected_traversal_entry_is_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            archive = self.archive(root, [('Editor/Data/Managed/../../escape.dll', b'bad', None)])
            with patch.object(prepare_csharp, 'SHA256', hashlib.sha256(archive.read_bytes()).hexdigest()):
                with self.assertRaisesRegex(ValueError, 'Unsafe'):
                    prepare_csharp.extract_sdk(archive, root / 'sdk')
            self.assertFalse((root / 'escape.dll').exists())


if __name__ == '__main__':
    unittest.main()
