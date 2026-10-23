"""Execute the real CMake filter with regenerated and changed plugin fixtures."""
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class WindowsPluginFilterTests(unittest.TestCase):
    def run_filter(self, source, plugins):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        root = Path(temp.name)
        reg = root / 'registrant.cc'
        listing = root / 'plugins.cmake'
        reg.write_bytes(source.encode())
        listing.write_bytes(plugins.encode())
        module = (ROOT / 'windows/cmake/NeuraWindowsPlugins.cmake').as_posix()
        script = root / 'check.cmake'
        script.write_text(f'include("{module}")\nneura_prepare_windows_plugins("{reg.as_posix()}" "{listing.as_posix()}" "{root.as_posix()}/out")\n')
        result = subprocess.run(['cmake', '-P', str(script)], capture_output=True, text=True)
        self.assertEqual(reg.read_bytes(), source.encode())
        self.assertEqual(listing.read_bytes(), plugins.encode())
        return result, root / 'out'

    def sources(self):
        return ((ROOT / 'windows/flutter/generated_plugin_registrant.cc').read_text(),
                (ROOT / 'windows/flutter/generated_plugins.cmake').read_text())

    def test_regenerated_plugins_keep_every_other_registration_and_ffi_entry(self):
        source, plugins = self.sources()
        result, output = self.run_filter(source, plugins)
        self.assertEqual(result.returncode, 0, result.stderr)
        registered = (output / 'generated_plugin_registrant.cc').read_text()
        listing = (output / 'generated_plugins.cmake').read_text()
        self.assertNotIn('FlutterTts', registered)
        self.assertNotIn('flutter_tts', registered)
        self.assertNotIn('flutter_tts', listing)
        for line in source.splitlines():
            if 'flutter_tts' not in line and 'FlutterTts' not in line and 'registry->GetRegistrarForPlugin' in line:
                self.assertIn(line, registered)
        self.assertIn('flutter_local_notifications_windows', listing)
        self.assertIn('jni', listing)
        self.assertIn('foreach(plugin ${FLUTTER_PLUGIN_LIST})', listing)

    def test_changed_upstream_registration_fails_instead_of_reenabling_tts(self):
        source, plugins = self.sources()
        source = source.replace('FlutterTtsPluginRegisterWithRegistrar', 'FlutterTtsPluginRegisterV2')
        result, _ = self.run_filter(source, plugins)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Unrecognized legacy Windows TTS registration', result.stderr)

    def test_crlf_regeneration_is_supported(self):
        source, plugins = self.sources()
        result, _ = self.run_filter(source.replace('\n', '\r\n'), plugins.replace('\n', '\r\n'))
        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == '__main__':
    unittest.main()
