"""Execute the production install rules for all three build configurations.

A tiny C++ target and synthetic payload isolate CMake's generated install
behavior. They do not test Flutter, native plugins, speech, or a real device.
"""
from pathlib import Path
import os
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class WindowsBundleLayoutTests(unittest.TestCase):
    def checked(self, *command):
        result = subprocess.run(command, capture_output=True, text=True, timeout=120)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_each_configuration_installs_and_cleans_only_its_own_payload(self):
        production = (ROOT / 'windows/CMakeLists.txt').read_text(encoding='utf-8')
        self.assertEqual(production.count('# === Installation ==='), 1)
        install_rules = production.split('# === Installation ===', 1)[1]
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            build = root / 'build'
            project = build / 'project'
            assets = project / 'flutter_assets'
            native = project / 'native_assets/windows'
            assets.mkdir(parents=True)
            native.mkdir(parents=True)
            native.joinpath('synthetic_native.dll').write_text('synthetic native')
            for name in ('icudtl.dat', 'flutter_windows.dll', 'plugin.dll', 'app.so'):
                root.joinpath(name).write_text('synthetic ' + name)
            root.joinpath('main.cpp').write_text('int main() { return 0; }\n')
            root.joinpath('CMakeLists.txt').write_text(
                'cmake_minimum_required(VERSION 3.14)\n'
                'project(BundleInstallFixture LANGUAGES CXX)\n'
                'set(CMAKE_CONFIGURATION_TYPES "Debug;Profile;Release" CACHE STRING "" FORCE)\n'
                'set(CMAKE_CXX_FLAGS_PROFILE "${CMAKE_CXX_FLAGS_RELEASE}")\n'
                'set(CMAKE_EXE_LINKER_FLAGS_PROFILE "${CMAKE_EXE_LINKER_FLAGS_RELEASE}")\n'
                'set(BINARY_NAME neuro_companion)\n'
                'add_executable(${BINARY_NAME} main.cpp)\n'
                'set_target_properties(${BINARY_NAME} PROPERTIES '
                'RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/runner")\n'
                f'set(PROJECT_BUILD_DIR [==[{project.as_posix()}/]==])\n'
                'set(FLUTTER_ICU_DATA_FILE "${CMAKE_CURRENT_SOURCE_DIR}/icudtl.dat")\n'
                'set(FLUTTER_LIBRARY "${CMAKE_CURRENT_SOURCE_DIR}/flutter_windows.dll")\n'
                'set(PLUGIN_BUNDLED_LIBRARIES "${CMAKE_CURRENT_SOURCE_DIR}/plugin.dll")\n'
                'set(AOT_LIBRARY "${CMAKE_CURRENT_SOURCE_DIR}/app.so")\n' + install_rules)
            generator = [] if os.name == 'nt' else ['-G', 'Ninja Multi-Config']
            self.checked('cmake', '-S', str(root), '-B', str(build), *generator)
            installed = []
            for configuration in ('Debug', 'Profile', 'Release'):
                with self.subTest(configuration=configuration):
                    assets.joinpath('marker.txt').write_text(configuration)
                    bundle = build / 'runner' / configuration
                    old_assets = bundle / 'data/flutter_assets'
                    old_assets.mkdir(parents=True, exist_ok=True)
                    old_assets.joinpath('stale.txt').write_text('remove this')
                    self.checked('cmake', '--build', str(build), '--config', configuration)
                    self.checked('cmake', '--install', str(build), '--config', configuration)
                    executable = 'neuro_companion.exe' if os.name == 'nt' else 'neuro_companion'
                    self.assertTrue(bundle.joinpath(executable).is_file())
                    for path in ('data/icudtl.dat', 'flutter_windows.dll', 'plugin.dll',
                                 'synthetic_native.dll'):
                        self.assertTrue(bundle.joinpath(path).is_file(), path)
                    self.assertEqual(old_assets.joinpath('marker.txt').read_text(), configuration)
                    self.assertFalse(old_assets.joinpath('stale.txt').exists())
                    self.assertEqual(bundle.joinpath('data/app.so').exists(),
                                     configuration != 'Debug')
                    for previous in installed:
                        self.assertEqual(build.joinpath(
                            'runner', previous, 'data/flutter_assets/marker.txt').read_text(),
                            previous, 'Installing another configuration must not alter this bundle')
                    installed.append(configuration)


if __name__ == '__main__':
    unittest.main(verbosity=2)
