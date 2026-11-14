"""Bounded configure-only checks: no builds, downloads, app launch or live data."""
import base64
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]


class PreviewModeTest(unittest.TestCase):
    def configure(self, values):
        cmake = os.environ.get("NEURA_TEST_CMAKE") or shutil.which("cmake")
        self.assertIsNotNone(cmake, "Use the installed CMake; do not install one for this check")
        encoded = ",".join(base64.b64encode(v.encode()).decode() for v in values)
        # Retain only these tiny task-owned fixtures for inspection; no cleanup.
        directory = Path(tempfile.mkdtemp(prefix="neura-preview-config-"))
        script = directory / "check.cmake"
        script.write_text(
            f'include("{(ROOT / "windows/cmake/NeuraDemo.cmake").as_posix()}")\n'
            f'neura_demo_from_environment(mode "DART_DEFINES={encoded}")\n'
            'message(STATUS "NEURA_PREVIEW=${mode}")\n', encoding="utf-8")
        return subprocess.run([cmake, "-P", str(script)], capture_output=True,
                              text=True, timeout=15, check=False)

    def test_normal_and_unrelated_defines_do_not_enable_preview(self):
        for values in ([], ["SOMETHING=true"], ["NEURA_DEMO=false"]):
            result = self.configure(values)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("NEURA_PREVIEW=FALSE", result.stdout)

    def test_explicit_true_enables_the_isolated_host(self):
        result = self.configure(["SOMETHING=true", "NEURA_DEMO=true"])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("NEURA_PREVIEW=TRUE", result.stdout)

    def test_conflicting_duplicate_or_malformed_defines_fail(self):
        for values in (["NEURA_DEMO=true", "NEURA_DEMO=false"],
                       ["NEURA_DEMO=true", "NEURA_DEMO=true"],
                       ["NEURA_DEMO=invalid"], ["NEURA_DEMO="]):
            result = self.configure(values)
            self.assertNotEqual(result.returncode, 0, result.stdout)

    def test_preview_target_has_no_production_services(self):
        runner = (ROOT / "windows/runner/CMakeLists.txt").read_text()
        preview = runner.split("if(NEURA_ISOLATED_DEMO)", 1)[1].split("return()", 1)[0]
        self.assertIn('"neura_demo_main.cpp"', preview)
        for forbidden in ("generated_plugin_registrant", "neura_native_diagnostics",
                          "neura_windows_tts", "neura_swarm_rust", "neura_local_speech"):
            self.assertNotIn(forbidden, preview)
        native = (ROOT / "windows/runner/neura_demo_main.cpp").read_text()
        self.assertIn('"sample-data-no-plugins-v1"', native)
        self.assertNotIn("RegisterPlugins", native)
        self.assertNotIn("InitializeNeuraNativeDiagnostics", native)


if __name__ == "__main__":
    unittest.main()
