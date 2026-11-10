"""Exercise the real CMake correction against the locked notification source.

Run after flutter pub get, or pass --source /path/to/package/src/plugin.cpp.
This checks source composition only; the Windows CI build validates MSVC.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tempfile
import unittest
from urllib.parse import urljoin, urlsplit
from urllib.request import url2pathname

ROOT = Path(__file__).resolve().parents[1]


def package_source(config):
    packages = json.loads(config.read_text(encoding='utf-8'))['packages']
    package = next(p for p in packages
                   if p['name'] == 'flutter_local_notifications_windows')
    uri = urlsplit(urljoin(config.resolve().as_uri(), package['rootUri']))
    if uri.scheme != 'file' or uri.netloc:
        raise ValueError('Expected a local notification package')
    return Path(url2pathname(uri.path)) / 'src/plugin.cpp'


class NotificationSourceTests(unittest.TestCase):
    source = None

    @classmethod
    def setUpClass(cls):
        cls.original = cls.source.read_bytes().replace(b'\r\n', b'\n')

    def run_correction(self, contents):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        root = Path(temp.name)
        source = root / 'plugin.cpp'
        source.write_bytes(contents)
        output = root / 'out'
        module = ROOT / 'windows/cmake/NeuraWinrtPlugins.cmake'
        script = root / 'check.cmake'
        script.write_text(
            f'include([==[{module.as_posix()}]==])\n'
            f'neura_prepare_notification_source([==[{source.as_posix()}]==] '
            f'[==[{output.as_posix()}]==])\n', encoding='utf-8')
        result = subprocess.run(['cmake', '-P', str(script)],
                                capture_output=True, text=True)
        self.assertEqual(source.read_bytes(), contents, 'Upstream must stay untouched')
        return result, output

    def assert_corrected(self, contents):
        result, output = self.run_correction(contents)
        self.assertEqual(result.returncode, 0, result.stderr)
        # CMake file(WRITE) uses text mode: Windows emits CRLF. The CMake
        # receipt hashes the normalized in-memory string, so compare the
        # complete source and its receipt in that same representation.
        compiled = (output / 'plugin.cpp').read_bytes().replace(b'\r\n', b'\n')
        # Removing only the two complete COM identity specializations must
        # recover the entire reviewed source, including the new conversions.
        stripped = compiled
        for implementation, interface in (
                ('NotificationActivationCallback', 'INotificationActivationCallback'),
                ('NotificationActivationCallbackFactory', 'IClassFactory')):
            specialization = (
                'namespace winrt {\ntemplate <>\n'
                f'inline hstring implements<{implementation}, {interface}>'
                '::GetRuntimeClassName() const {\n'
                f'  return neura::NativeComRuntimeName<{interface}>();\n'
                '}\n}  // namespace winrt\n\n').encode()
            self.assertEqual(compiled.count(specialization), 1)
            stripped = stripped.replace(specialization, b'')
        self.assertEqual(stripped, self.original)
        receipt = (output / 'notification_source_receipt.txt').read_text()
        lock = (ROOT / 'pubspec.lock').read_text(encoding='utf-8')
        version = re.search(
            r'(?ms)^  flutter_local_notifications_windows:\n.*?^    version: "([^"]+)"',
            lock).group(1)
        self.assertEqual(receipt,
                         f'flutter_local_notifications_windows {version}\n'
                         f'upstream_sha256={hashlib.sha256(self.original).hexdigest()}\n'
                         f'build_sha256={hashlib.sha256(compiled).hexdigest()}\n')

    def test_locked_source_retains_complete_code_and_accurate_receipt(self):
        self.assert_corrected(self.original)

    def test_crlf_package_source_is_normalized_without_mutating_cache(self):
        self.assert_corrected(self.original.replace(b'\n', b'\r\n'))

    def test_unreviewed_source_is_rejected_without_emitting_build_source(self):
        result, output = self.run_correction(self.original + b'// unreviewed change\n')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Native COM source changed', result.stderr)
        self.assertFalse(output.exists())

    def test_previous_package_source_is_rejected(self):
        previous = self.original.replace(
            b'const std::string key(CW2A(item.Key, CP_UTF8));',
            b'const std::string key = CW2A(item.Key, CP_UTF8);').replace(
            b'const std::string value(CW2A(item.Value, CP_UTF8));',
            b'const std::string value = CW2A(item.Value, CP_UTF8);')
        self.assertEqual(hashlib.sha256(previous).hexdigest(),
                         'e56a6c1939fad6656f136cc7e31803b8544637af78002e275921888ca46ecb65')
        result, output = self.run_correction(previous)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Native COM source changed', result.stderr)
        self.assertFalse(output.exists())


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path)
    parser.add_argument('--package-config', type=Path,
                        default=ROOT / '.dart_tool/package_config.json')
    args = parser.parse_args()
    NotificationSourceTests.source = args.source or package_source(args.package_config)
    unittest.main(argv=['test_windows_notification_source'], verbosity=2)
