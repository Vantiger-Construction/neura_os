"""Exercise the genuine locked window-manager correction with CMake.

These are source-composition checks. Native channel lifetime and real-device
acceptance remain separate from these tests and the Windows compiler lane.
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
MODULE = ROOT / 'windows/cmake/NeuraWindowManager.cmake'


def package_source(config):
    packages = json.loads(config.read_text(encoding='utf-8'))['packages']
    package = next(p for p in packages if p['name'] == 'window_manager_plus')
    uri = urlsplit(urljoin(config.resolve().as_uri(), package['rootUri']))
    if uri.scheme != 'file' or uri.netloc:
        raise ValueError('Expected a local window-manager package')
    return Path(url2pathname(uri.path)) / 'windows/window_manager_plus_plugin.cpp'


class WindowManagerSourceTests(unittest.TestCase):
    source = None

    @classmethod
    def setUpClass(cls):
        cls.original = cls.source.read_bytes().replace(b'\r\n', b'\n')

    def run_correction(self, contents):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        source = root / 'window_manager_plus_plugin.cpp'
        source.write_bytes(contents)
        output = root / 'generated'
        script = root / 'check.cmake'
        script.write_text(
            f'include([==[{MODULE.as_posix()}]==])\n'
            f'neura_prepare_window_manager_source([==[{source.as_posix()}]==] '
            f'[==[{output.as_posix()}]==])\n', encoding='utf-8')
        result = subprocess.run(['cmake', '-P', str(script)],
                                capture_output=True, text=True, timeout=30)
        self.assertEqual(source.read_bytes(), contents,
                         'The dependency source must remain untouched')
        return result, output

    def assert_corrected(self, contents):
        result, output = self.run_correction(contents)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        compiled = (output / 'window_manager_plus_plugin.cpp').read_bytes()
        compiled = compiled.replace(b'\r\n', b'\n')
        # Undo only the three reviewed edits. The entire remaining source must
        # match upstream, rather than merely containing selected good strings.
        member = b'  std::shared_ptr<WindowManagerPlus> window_manager;'
        original_channel = b'''  window_manager->channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "window_manager_plus",
          &flutter::StandardMethodCodec::GetInstance());
  window_manager->channel->SetMethodCallHandler('''
        bootstrap_channel = original_channel.replace(
            b'window_manager->channel', b'bootstrap_channel_')
        unregister = b'  registrar->UnregisterTopLevelWindowProcDelegate(window_proc_id);'
        transformations = (
            (member + b'\n  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> bootstrap_channel_;',
             member),
            (bootstrap_channel, original_channel),
            (b'''  bootstrap_channel_->SetMethodCallHandler(nullptr);
  if (window_manager->channel) {
    window_manager->channel->SetMethodCallHandler(nullptr);
  }
''' + unregister, unregister),
        )
        restored = compiled
        for generated, original in transformations:
            self.assertEqual(restored.count(generated), 1)
            restored = restored.replace(generated, original)
        self.assertEqual(restored, self.original)
        lock = (ROOT / 'pubspec.lock').read_text(encoding='utf-8')
        version = re.search(
            r'(?ms)^  window_manager_plus:\n.*?^    version: "([^"]+)"',
            lock).group(1)
        self.assertEqual(
            (output / 'window_manager_source_receipt.txt').read_text(),
            f'window_manager_plus {version}\n'
            f'upstream_sha256={hashlib.sha256(self.original).hexdigest()}\n'
            f'build_sha256={hashlib.sha256(compiled).hexdigest()}\n')

    def test_complete_source_and_receipt(self):
        self.assert_corrected(self.original)

    def test_crlf_normalization_does_not_mutate_dependency(self):
        self.assert_corrected(self.original.replace(b'\n', b'\r\n'))

    def test_source_drift_fails_before_emitting_generated_source(self):
        result, output = self.run_correction(self.original + b'// drift\n')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('window_manager_plus source changed', result.stderr)
        self.assertFalse(output.exists())

    def configure_target(self, relative_source=True):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        plugin = root / 'package/windows'
        plugin.mkdir(parents=True)
        upstream = plugin / 'window_manager_plus_plugin.cpp'
        upstream.write_bytes(self.original)
        license_bytes = self.source.parent.parent.joinpath('LICENSE').read_bytes()
        plugin.parent.joinpath('LICENSE').write_bytes(license_bytes)
        plugin.joinpath('other.cpp').write_text('// retained source\n')
        source = ('window_manager_plus_plugin.cpp' if relative_source else
                  '"${CMAKE_CURRENT_SOURCE_DIR}/window_manager_plus_plugin.cpp"')
        plugin.joinpath('CMakeLists.txt').write_text(
            'add_library(window_manager_plus_plugin STATIC '
            f'{source} other.cpp)\n')
        output = root / 'generated'
        root.joinpath('CMakeLists.txt').write_text(
            'cmake_minimum_required(VERSION 3.14)\n'
            'project(WindowManagerCorrectionFixture LANGUAGES CXX)\n'
            'add_subdirectory(package/windows)\n'
            f'include([==[{MODULE.as_posix()}]==])\n'
            f'neura_configure_window_manager([==[{output.as_posix()}]==])\n'
            'get_target_property(source_list window_manager_plus_plugin SOURCES)\n'
            'get_target_property(include_list window_manager_plus_plugin INCLUDE_DIRECTORIES)\n'
            'file(WRITE "${CMAKE_BINARY_DIR}/sources.txt" "${source_list}")\n'
            'file(WRITE "${CMAKE_BINARY_DIR}/includes.txt" "${include_list}")\n')
        build = root / 'build'
        result = subprocess.run(['cmake', '-S', str(root), '-B', str(build)],
                                capture_output=True, text=True, timeout=120)
        self.assertEqual(upstream.read_bytes(), self.original)
        return result, output, build, plugin, license_bytes

    def test_only_the_intended_target_source_is_replaced_and_license_retained(self):
        result, output, build, plugin, license_bytes = self.configure_target()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(set(build.joinpath('sources.txt').read_text().split(';')),
                         {'other.cpp', output.joinpath(
                             'window_manager_plus_plugin.cpp').as_posix()})
        self.assertIn(plugin.as_posix(),
                      build.joinpath('includes.txt').read_text().split(';'))
        self.assertEqual(output.joinpath('LICENSE').read_bytes(), license_bytes)

    def test_unreviewed_target_source_layout_is_rejected(self):
        result, _, _, _, _ = self.configure_target(relative_source=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('window_manager_plus source layout changed', result.stderr)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path)
    parser.add_argument('--package-config', type=Path,
                        default=ROOT / '.dart_tool/package_config.json')
    args = parser.parse_args()
    WindowManagerSourceTests.source = args.source or package_source(args.package_config)
    unittest.main(argv=['test_windows_window_manager_source'], verbosity=2)
