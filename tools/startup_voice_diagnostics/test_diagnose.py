"""Synthetic safety regressions. No device, audio, network or app is used."""
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile

import diagnose as d


class PackageTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.build = {"platform": "android", "source_commit": "a" * 40,
                      "head_commit": "b" * 40, "source_tree": "c" * 40,
                      "run_id": "1", "run_attempt": "1", "release_tag": "test"}
        with zipfile.ZipFile(self.root / "test.apk", "w") as archive:
            for name in ("AndroidManifest.xml", "classes.dex", "resources.arsc"):
                archive.writestr(name, b"synthetic")
        (self.root / "build-manifest.json").write_text(json.dumps(self.build))
        self.refresh()

    def refresh(self):
        names = ["test.apk", "build-manifest.json"]
        (self.root / "SHA256SUMS.txt").write_text("".join(
            d.sha256_file(self.root / n) + "  " + n + "\n" for n in names))
        self.build["assets"] = [{"name": n, "bytes": (self.root/n).stat().st_size,
                                 "sha256": d.sha256_file(self.root/n)}
                                for n in names + ["SHA256SUMS.txt"]]

    def test_complete_identity_does_not_accept_hardware_or_migration(self):
        report = d.verify_package(self.build, self.root)
        self.assertEqual(report["status"], "PASS")
        self.assertEqual(report["hardware_acceptance"], "NOT RUN")
        self.assertEqual(report["safe_to_upgrade_existing_data"], "BLOCKED")

    def test_tampered_binary_fails(self):
        with (self.root / "test.apk").open("ab") as stream:
            stream.write(b"changed")
        with self.assertRaises(d.DiagnosticError):
            d.verify_package(self.build, self.root)

    def test_wrong_manifest_rejected_even_with_matching_asset_hashes(self):
        manifest = dict(self.build, source_commit="d" * 40)
        (self.root / "build-manifest.json").write_text(json.dumps(manifest))
        self.refresh()
        with self.assertRaisesRegex(d.DiagnosticError, "manifest identity"):
            d.verify_package(self.build, self.root)

    def test_checksum_content_is_bound(self):
        (self.root / "SHA256SUMS.txt").write_text("0"*64 + "  test.apk\n")
        sums = self.build["assets"][-1]
        sums.update(bytes=(self.root/"SHA256SUMS.txt").stat().st_size,
                    sha256=d.sha256_file(self.root/"SHA256SUMS.txt"))
        with self.assertRaisesRegex(d.DiagnosticError, "Checksum list"):
            d.verify_package(self.build, self.root)

    def test_symlink_asset_refused(self):
        (self.root / "original.apk").write_bytes((self.root / "test.apk").read_bytes())
        (self.root / "test.apk").unlink()
        (self.root / "test.apk").symlink_to(self.root / "original.apk")
        with self.assertRaises(d.DiagnosticError):
            d.verify_package(self.build, self.root)

    def test_unknown_archive_paths_links_and_duplicates_refused(self):
        unsafe = ["../escape", "C:\\escape", "/absolute", "data/../secret", "x:stream",
                  "data//a", "data/a.", "CON.txt", "data/a\nsecret", "data/x?y"]
        for value in unsafe:
            with self.subTest(value=value), self.assertRaises(d.DiagnosticError):
                d.safe_member(value)
        self.assertEqual(d.safe_member("data\\app.so"), "data/app.so")
        for mode in ("duplicate", "link", "missing"):
            path = self.root / (mode + ".zip")
            with zipfile.ZipFile(path, "w") as archive:
                if mode == "duplicate":
                    archive.writestr("a", b"a")
                    archive.writestr("A", b"b")
                elif mode == "link":
                    entry = zipfile.ZipInfo("linked")
                    entry.create_system = 3
                    entry.external_attr = 0o120777 << 16
                    archive.writestr(entry, "target")
                else:
                    archive.writestr("only", b"a")
            with self.subTest(mode=mode), self.assertRaises(d.DiagnosticError):
                d.inspect_zip(path, "windows")

    def test_checksum_escape_duplicate_and_malformed_refused(self):
        for text in ("not a checksum", "0"*64+"  ../escape", "0"*64+"  x\n"+"1"*64+"  X"):
            with self.subTest(text=text), self.assertRaises(d.DiagnosticError):
                d.parse_checksums(text)

    def test_apk_signer_mismatch_fails(self):
        build = dict(self.build, signer_certificate_sha256="1"*64, version_code="2", version_name="1.5.1")
        fake = ["Signer #1 certificate SHA-256 digest: " + "2"*64,
                "package: name='com.neurocompanion.app' versionCode='2' versionName='1.5.1'\n"
                "uses-permission: name='android.permission.RECORD_AUDIO'"]
        with patch.object(d, "run_local", side_effect=fake), self.assertRaises(d.DiagnosticError):
            d.inspect_apk(build, self.root, "java", "jar", "aapt")


class PrivacyTests(unittest.TestCase):
    def test_crash_before_pid_poll_is_associated_without_private_text(self):
        lines = [
            "11-06 10:00:00.001  500  501 I ActivityManager: Start proc 123:com.neurocompanion.app/u0a1 for top-activity",
            "11-06 10:00:00.002  123  124 E AndroidRuntime: FATAL EXCEPTION: secret speech words",
            "11-06 10:00:00.003  123  124 E AndroidRuntime: Process: com.neurocompanion.app, PID: 123",
            "11-06 10:00:00.004  123  124 E AndroidRuntime: java.lang.Exception: PRIVATE_JOURNAL token=SECRET",
            "11-06 10:00:00.005  999  999 E AndroidRuntime: FATAL EXCEPTION: unrelated",
            "11-06 10:00:00.006  500  501 I ActivityManager: Start proc 987:com.neurocompanion.app.evil/u0a2",
        ]
        report = d.sanitize_logcat(lines)
        self.assertEqual(report["associated_process_count"], 1)
        self.assertEqual(len(report["events"]), 3)
        text = json.dumps(report)
        for forbidden in ("secret", "PRIVATE_JOURNAL", "SECRET", "unrelated", "987", "evil"):
            self.assertNotIn(forbidden, text)

    def test_native_crash_association_and_no_false_pass_on_empty(self):
        lines = ["11-06 10:00:00.001  50  51 F DEBUG: pid: 123, tid: 125, name: main >>> com.neurocompanion.app <<<",
                 "11-06 10:00:00.002  123  125 F libc: Fatal signal 11 (SIGSEGV) at private-address"]
        report = d.sanitize_logcat(lines)
        self.assertEqual(len(report["events"]), 2)
        self.assertNotIn("private-address", json.dumps(report))
        self.assertNotIn("status", d.sanitize_logcat([]))

    def test_already_running_pid_can_supply_filtered_error_markers(self):
        line = "11-06 10:00:00.001  123  125 E flutter: [ERROR:flutter/runtime] Unhandled Exception: PRIVATE"
        self.assertEqual(d.sanitize_logcat([line])["events"], [])
        result = d.sanitize_logcat([line], [123])
        self.assertEqual(result["events"][0]["event"], "dart_error_marker")
        self.assertNotIn("PRIVATE", json.dumps(result))

    def test_grant_does_not_cross_android_users(self):
        text = """  User 0: installed=true
      runtime permissions:
        android.permission.RECORD_AUDIO: granted=true
  User 10: installed=true
      runtime permissions:
        android.permission.RECORD_AUDIO: granted=false
"""
        self.assertEqual(d.permission_from_dump(text, 0), "true")
        self.assertEqual(d.permission_from_dump(text, 10), "false")
        self.assertEqual(d.permission_from_dump(text, 11), "UNKNOWN")

    def test_historical_appop_is_not_active(self):
        self.assertFalse(d.appop_metadata("RECORD_AUDIO: allow; time=+2m10s ago; duration=3s")["explicit_running_marker"])
        self.assertTrue(d.appop_metadata("RECORD_AUDIO: foreground (running)")["explicit_running_marker"])

    def test_audio_other_uid_and_private_text_are_excluded(self):
        result = d.audio_metadata("RecordingActivityMonitor:\n uid: 1234 secret audio\n uid: 91234 other\n pack: com.neurocompanion.app PRIVATE", 1234)
        self.assertEqual(result["matching_lines"], 2)
        self.assertNotIn("secret", json.dumps(result))
        self.assertNotIn("PRIVATE", json.dumps(result))

    def test_read_only_snapshot_never_exports_raw_output_or_serial(self):
        def fake(adb, serial, *args):
            command = " ".join(args)
            if command == "shell am get-current-user": return "0\n"
            if "list packages" in command: return "package:com.neurocompanion.app uid:10123\n"
            if "dumpsys package" in command:
                return "versionCode=596 minSdk=24\n versionName=1.5.1\n User 0: installed=true\n android.permission.RECORD_AUDIO: granted=false\nPRIVATE KEY SECRET"
            if "appops" in command: return "RECORD_AUDIO: deny; time=1s; PRIVATE"
            if "dumpsys audio" in command: return "uid: 10123 PRIVATE"
            return "UNKNOWN"
        with patch.object(d, "adb_read", side_effect=fake) as calls:
            report = d.android_snapshot("adb", "PRIVATE_SERIAL", 0, "test-device", "before")
        text = json.dumps(report)
        for forbidden in ("PRIVATE", "SECRET", "KEY"):
            self.assertNotIn(forbidden, text)
        for call in calls.call_args_list:
            self.assertFalse(set(call.args) & {"install", "uninstall", "clear", "grant", "revoke", "force-stop", "start"})
        self.assertEqual(report["microphone_granted"], "false")
        self.assertEqual(report["hardware_acceptance"], "NOT RUN")


class GuardTests(unittest.TestCase):
    def test_install_command_blocks_physical_device_and_existing_or_retained_app(self):
        with patch.object(d, "verify_package"):
            for serial, user in (("samsung-private", 0), ("emulator-5554", 10)):
                with self.assertRaises(d.DiagnosticError):
                    d.emulator_install_command("adb", serial, user, ".", {})
            with patch.object(d, "adb_read", side_effect=["1", "0", "Users: UserInfo{0:Owner:13}", "package:com.neurocompanion.app\n"]):
                with self.assertRaisesRegex(d.DiagnosticError, "retained data"):
                    d.emulator_install_command("adb", "emulator-5554", 0, ".", {})

    def test_install_helper_only_prints_command(self):
        build = {"assets": [{"name": "test.apk"}]}
        with patch.object(d, "verify_package"), patch.object(d, "adb_read", side_effect=["1", "0", "Users: UserInfo{0:Owner:13}", ""]) as read:
            result = d.emulator_install_command("adb", "emulator-5554", 0, ".", build)
            self.assertEqual(read.call_count, 4)
            self.assertEqual(result["scope"], "COMMAND_ONLY_NOT_EXECUTED")
            self.assertEqual(result["argv"][3:6], ["install", "--user", "0"])

    def test_new_record_never_uses_automated_passes(self):
        report = d.evidence_template("177-android", "android", "synthetic")
        self.assertTrue(all(r["status"] == "NOT RUN" for r in report["results"]))
        self.assertFalse(report["installed_identity_verified"])
        self.assertEqual(set(report["status_rules"]), {"PASS", "FAIL", "BLOCKED", "NOT RUN"})

    def test_report_cannot_replace_existing_file(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "evidence.json"
            d.save_new(path, {"first": True})
            with self.assertRaises(FileExistsError):
                d.save_new(path, {"changed": True})
            self.assertEqual(json.loads(path.read_text()), {"first": True})


if __name__ == "__main__":
    unittest.main(verbosity=2)
