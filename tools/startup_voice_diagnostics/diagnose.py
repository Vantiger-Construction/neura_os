#!/usr/bin/env python3
"""Offline package checks and bounded, read-only Android evidence collection.

No install, launch, grant, revoke, reset, wipe, speech, audio recording or upload
operation is implemented. Only newly named report files are written.
"""

import argparse
import collections
import datetime as dt
import hashlib
import json
from pathlib import Path
import re
import shlex
import stat
import subprocess
import sys
import threading
import zipfile

ROOT = Path(__file__).resolve().parent
PACKAGE = "com.neurocompanion.app"
MAX_TEXT = 2 * 1024 * 1024
MAX_ZIP_BYTES = 2 * 1024 * 1024 * 1024
SCENARIOS = (
    "isolation_and_build_identity", "cold_start_opt_out", "permission_denied",
    "permission_dialog_resume", "cold_start_opt_in", "greeting_before_mic",
    "one_local_phrase", "airplane_or_disconnected", "missing_local_engine",
    "stop_during_greeting", "stop_during_listening", "mute_or_interruption",
    "route_cover_and_close", "background_during_greeting",
    "background_during_listening", "lock_or_suspend", "resume_without_gesture",
    "startup_opt_out", "permission_revoked", "silence_or_recognizer_error",
    "safe_mode_during_greeting", "safe_mode_during_listening",
    "recovery_restart_required", "cloud_approval_cancel", "no_background_cloud",
    "memory_consent_unchanged", "disposable_wipe_shutdown",
)


class DiagnosticError(Exception):
    """Sanitized error suitable for an evidence file."""


def utc_now():
    return dt.datetime.now(dt.timezone.utc).isoformat()


def sha256_file(path):
    digest = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def save_new(path, report):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    # An existing report (including a symlink) is never overwritten.
    with path.open("x", encoding="utf-8", newline="\n") as stream:
        json.dump(report, stream, indent=2, ensure_ascii=True)
        stream.write("\n")


def load_catalog():
    return json.loads((ROOT / "build-catalog.json").read_text(encoding="utf-8"))


def safe_member(name):
    """Canonical Windows/POSIX ZIP path; reject extraction ambiguities."""
    name = name.replace("\\", "/")
    if not name or name.startswith("/") or any(ord(c) < 32 for c in name):
        raise DiagnosticError("Unsafe archive member")
    parts = name.rstrip("/").split("/")
    reserved = {"CON", "PRN", "AUX", "NUL"}
    reserved.update("COM" + str(n) for n in range(1, 10))
    reserved.update("LPT" + str(n) for n in range(1, 10))
    for part in parts:
        if (part in ("", ".", "..") or ":" in part or part[-1:] in (" ", ".")
                or any(c in part for c in '<>"|?*')
                or part.split(".")[0].upper() in reserved):
            raise DiagnosticError("Unsafe or ambiguous archive member")
    return "/".join(parts)


def inspect_zip(path, platform):
    """Read/CRC/hash every member without extracting or executing anything."""
    members, total = {}, 0
    with zipfile.ZipFile(path) as archive:
        infos = archive.infolist()
        if not 1 <= len(infos) <= 20000:
            raise DiagnosticError("Archive member bound exceeded")
        for item in infos:
            name = safe_member(item.filename)
            canonical = name.casefold()
            if canonical in members:
                raise DiagnosticError("Duplicate archive member")
            if stat.S_ISLNK(item.external_attr >> 16) or item.flag_bits & 1:
                raise DiagnosticError("Linked or encrypted archive member")
            total += item.file_size
            if total > MAX_ZIP_BYTES:
                raise DiagnosticError("Archive byte bound exceeded")
            digest = hashlib.sha256()
            with archive.open(item) as stream:
                for block in iter(lambda: stream.read(1024 * 1024), b""):
                    digest.update(block)
            members[canonical] = {"name": name, "bytes": item.file_size,
                                  "sha256": digest.hexdigest()}
        required = (["neuro_companion.exe", "flutter_windows.dll", "data/icudtl.dat",
                     "data/app.so"] if platform == "windows" else
                    ["AndroidManifest.xml", "classes.dex", "resources.arsc"])
        if any(n.casefold() not in members or not members[n.casefold()]["bytes"]
               for n in required):
            raise DiagnosticError("Required package payload missing")
        if platform == "windows":
            if any(n.rsplit("/", 1)[-1] == "flutter_tts_plugin.dll" for n in members):
                raise DiagnosticError("Legacy Windows TTS plugin present")
            exe = archive.read(next(i for i in infos if
                                    safe_member(i.filename).casefold() == "neuro_companion.exe"))
            if len(exe) < 64 or exe[:2] != b"MZ":
                raise DiagnosticError("Invalid Windows executable header")
            offset = int.from_bytes(exe[60:64], "little")
            if exe[offset:offset+6] != b"PE\x00\x00\x64\x86":
                raise DiagnosticError("Windows executable is not x64 PE")
    return {"status": "PASS", "scope": "STATIC_BYTES_ONLY",
            "members": len(members), "uncompressed_bytes": total,
            "payload_sha256": [members[n] for n in sorted(members)]}


def parse_checksums(text):
    values = {}
    for line in text.lstrip("\ufeff").splitlines():
        if not line.strip():
            continue
        match = re.fullmatch(r"([a-fA-F0-9]{64}) [ *](.+)", line)
        if not match:
            raise DiagnosticError("Malformed checksum list")
        name = safe_member(match[2])
        if "/" in name or name.casefold() in values:
            raise DiagnosticError("Unexpected or duplicate checksum target")
        values[name.casefold()] = match[1].lower()
    return values


def verify_package(build, directory):
    verified = []
    for asset in build["assets"]:
        path = Path(directory) / asset["name"]
        if path.is_symlink() or not path.is_file():
            raise DiagnosticError("Required regular package asset unavailable")
        if path.stat().st_size != asset["bytes"] or sha256_file(path) != asset["sha256"]:
            raise DiagnosticError("Asset length or SHA-256 differs from pinned release")
        verified.append({"name": asset["name"], "bytes": asset["bytes"],
                         "sha256": asset["sha256"]})
    manifest_asset = next(a for a in build["assets"] if a["name"].endswith("manifest.json"))
    sums_asset = next(a for a in build["assets"] if a["name"].endswith("SUMS.txt"))
    binary = next(a for a in build["assets"] if a["name"].endswith((".zip", ".apk")))
    manifest = json.loads((Path(directory) / manifest_asset["name"]).read_text(encoding="utf-8-sig"))
    for field in ("source_commit", "head_commit", "platform", "run_id", "run_attempt", "release_tag"):
        if str(manifest.get(field)) != str(build[field]):
            raise DiagnosticError("Build manifest identity differs from pinned release")
    expected_sums = {a["name"].casefold(): a["sha256"] for a in (manifest_asset, binary)}
    if parse_checksums((Path(directory) / sums_asset["name"]).read_text(encoding="utf-8-sig")) != expected_sums:
        raise DiagnosticError("Checksum list does not match binary and manifest")
    result = {"status": "PASS", "scope": "PINNED_RELEASE_BYTE_IDENTITY_ONLY",
              "source_commit": build["source_commit"], "source_tree": build["source_tree"],
              "head_commit": build["head_commit"], "platform": build["platform"],
              "run_id": build["run_id"], "release_tag": build["release_tag"],
              "configured_backend": manifest.get("configuration") == "configured",
              "device_qa_in_manifest": manifest.get("device_qa"), "assets": verified,
              "archive": inspect_zip(Path(directory) / binary["name"], build["platform"]),
              "hardware_acceptance": "NOT RUN", "safe_to_upgrade_existing_data": "BLOCKED"}
    return result


def run_local(argv, timeout=20):
    try:
        proc = subprocess.run(argv, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                              stderr=subprocess.PIPE, timeout=timeout, check=False)
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise DiagnosticError("Tool unavailable or timed out") from exc
    if proc.returncode:
        raise DiagnosticError("Tool returned a nonzero exit code")
    if len(proc.stdout) > MAX_TEXT:
        raise DiagnosticError("Diagnostic output bound exceeded")
    return proc.stdout.decode("utf-8", "replace")


def inspect_apk(build, directory, java, jar, aapt):
    # Bind this inspection to the verified APK, manifest and checksum list first.
    package = verify_package(build, directory)
    binary = next(a for a in build["assets"] if a["name"].endswith(".apk"))
    path = str(Path(directory).resolve() / binary["name"])
    signed = run_local([java, "-jar", jar, "verify", "--verbose", "--print-certs", path], 45)
    certs = re.findall(r"Signer #\d+ certificate SHA-256 digest:\s*([a-fA-F0-9]{64})", signed)
    badging = run_local([aapt, "dump", "badging", path], 45)
    identity = re.search(r"^package: name='([^']+)' versionCode='(\d+)' versionName='([^']+)'",
                         badging, re.MULTILINE)
    if not identity or identity[1] != PACKAGE or not certs:
        raise DiagnosticError("APK application identity or signer certificate unavailable")
    if str(build.get("version_code")) != identity[2] or build.get("version_name") != identity[3]:
        raise DiagnosticError("APK version differs from inspected build")
    expected = build.get("signer_certificate_sha256")
    if not expected or [c.lower() for c in certs] != [expected]:
        raise DiagnosticError("APK signer differs from inspected build")
    if "android.permission.RECORD_AUDIO" not in badging:
        raise DiagnosticError("APK microphone permission is missing")
    return {"status": "PASS", "scope": "APK_SIGNATURE_AND_STATIC_IDENTITY_ONLY",
            "application_id": identity[1], "version_code": identity[2], "version_name": identity[3],
            "signer_certificate_sha256": [c.lower() for c in certs],
            "apk_sha256": binary["sha256"], "source_commit": package["source_commit"],
            "hardware_acceptance": "NOT RUN", "migration_acceptance": "BLOCKED"}


def adb_read(adb, serial, *args):
    # All callers use a fixed read-only command, with argv rather than a shell.
    return run_local([adb, "-s", serial, *args])


def package_present(text):
    return any(re.match(r"^package:" + re.escape(PACKAGE) + r"(?:\s|$)", line)
               for line in text.splitlines())


def safe_alias(value):
    if not re.fullmatch(r"[A-Za-z0-9_-]{1,48}", value):
        raise argparse.ArgumentTypeError("Use a synthetic alias of 1-48 letters, digits, - or _")
    return value


def user_number(value):
    try:
        number = int(value)
    except ValueError as exc:
        raise argparse.ArgumentTypeError("Android user must be an integer") from exc
    if not 0 <= number < 10000:
        raise argparse.ArgumentTypeError("Android user is outside the supported bound")
    return number


def permission_from_dump(text, user):
    # dumpsys includes every Android user; never attribute another user's grant.
    section = re.search(r"(?ms)^\s*User " + str(user) + r":.*?(?=^\s*User \d+:|\Z)", text)
    if not section:
        return "UNKNOWN"
    match = re.search(r"android\.permission\.RECORD_AUDIO: granted=(true|false)", section[0])
    return match[1] if match else "UNKNOWN"


def appop_metadata(text):
    match = re.search(r"\bRECORD_AUDIO:\s*(allow|deny|ignore|foreground|default|errored)\b", text)
    # 'time=' is historical. Only explicit running indicators are reported.
    active = bool(re.search(r"\b(running=true|active=true)\b|\(running\)", text, re.I))
    return {"mode": match[1] if match else "UNKNOWN", "explicit_running_marker": active,
            "limit": "No marker does not establish microphone shutdown"}


def audio_metadata(text, uid):
    references = []
    for line in text.splitlines():
        if PACKAGE in line or (uid is not None and re.search(r"\buid\s*[:=]\s*" + str(uid) + r"\b", line)):
            references.append(line)
    return {"matching_lines": len(references),
            "recording_section_present": bool(re.search(r"recording|RecordActivityMonitor", text, re.I)),
            "limit": "References may be historical; service-owned capture may use another UID. Inspect OS mic indicator too"}


def android_snapshot(adb, serial, user, alias, label):
    report = {"scope": "READ_ONLY_ANDROID_SNAPSHOT", "device_alias": alias,
              "label": label, "requested_user": user, "observed_utc": utc_now(),
              "hardware_acceptance": "NOT RUN", "collection": {}}
    commands = {
        "model": ("shell", "getprop", "ro.product.model"),
        "android_release": ("shell", "getprop", "ro.build.version.release"),
        "api": ("shell", "getprop", "ro.build.version.sdk"),
        "os_build": ("shell", "getprop", "ro.build.id"),
        "foreground_user": ("shell", "am", "get-current-user"),
        "packages": ("shell", "pm", "list", "packages", "--user", str(user), "-U", PACKAGE),
        "package_dump": ("shell", "dumpsys", "package", PACKAGE),
        "appops": ("shell", "cmd", "appops", "get", "--user", str(user), PACKAGE, "RECORD_AUDIO"),
        "audio": ("shell", "dumpsys", "audio"),
        "recognition_services": ("shell", "cmd", "package", "query-services", "--brief", "--user", str(user),
                                 "-a", "android.speech.RecognitionService"),
    }
    values = {}
    for key, command in commands.items():
        try:
            value = adb_read(adb, serial, *command)
            if re.search(r"Permission Denial|SecurityException|Unknown command|Unknown package|Error:", value, re.I):
                raise DiagnosticError("Diagnostic unavailable")
            values[key] = value
            report["collection"][key] = "AVAILABLE"
        except DiagnosticError:
            report["collection"][key] = "BLOCKED"
    for key in ("model", "android_release", "api", "os_build"):
        value = values.get(key, "").strip()
        # Fixed OS identifiers only; never serial, account, hostname or fingerprint.
        report[key] = value if re.fullmatch(r"[A-Za-z0-9_.+ -]{1,80}", value) else "UNKNOWN"
    current = values.get("foreground_user", "").strip()
    report["foreground_user"] = int(current) if current.isdecimal() else "UNKNOWN"
    report["user_matches"] = report["foreground_user"] == user
    report["installed_for_user"] = package_present(values.get("packages", ""))
    uid_match = re.search(r"^package:" + re.escape(PACKAGE) + r"\s+uid:(\d+)\b",
                          values.get("packages", ""), re.M)
    uid = int(uid_match[1]) if uid_match else None
    report["application_uid"] = uid
    dump = values.get("package_dump", "")
    version = re.search(r"\bversionCode=(\d+)\b", dump)
    report["version_code"] = version[1] if version else "UNKNOWN"
    version = re.search(r"\bversionName=([A-Za-z0-9_.+-]{1,40})\s", dump)
    report["version_name"] = version[1] if version else "UNKNOWN"
    report["microphone_granted"] = permission_from_dump(dump, user)
    report["appops"] = appop_metadata(values.get("appops", ""))
    report["audio"] = audio_metadata(values.get("audio", ""), uid)
    report["recognition_service_components_found"] = len(re.findall(
        r"^\s*[A-Za-z0-9_.]+/[A-Za-z0-9_.$]+\s*$", values.get("recognition_services", ""), re.M))
    report["local_engine_availability"] = "NOT_ESTABLISHED_BY_SERVICE_LIST"
    report["privacy"] = "No raw output, serial, transcript, audio, account, key or credential saved"
    return report


def sanitize_logcat(lines, known_pids=()):
    """Allowlist event classes after binding records to Neura's process(es).

    Catches pre-pid Java/native startup failures by learning pids from bounded
    package-associated lines. No raw line/message/stack is returned.
    """
    pids = set(known_pids)
    exact = re.escape(PACKAGE) + r"(?=[:\s,/>]|$)"
    for line in lines:
        for pattern in (r"Start proc (\d+):" + exact,
                        r"Process:\s*" + re.escape(PACKAGE) + r"(?:\s*,\s*PID:\s*)(\d+)",
                        r"pid:\s*(\d+).*>>>\s*" + re.escape(PACKAGE) + r"\s*<<<"):
            match = re.search(pattern, line)
            if match:
                pids.add(int(match[1]))
    events = []
    for line in lines:
        header = re.match(r"^(\d\d-\d\d\s+\d\d:\d\d:\d\d\.\d+)\s+(\d+)\s+\d+\s+[VDIWEF]\s+([^:]+):", line)
        own = bool(header and int(header[2]) in pids)
        associated = bool(re.search(exact, line))
        if not (own or associated):
            continue
        kind = None
        if re.search(r"FATAL EXCEPTION|Process:\s*" + re.escape(PACKAGE) + r"\s*,\s*PID:", line):
            kind = "java_crash_marker"
        elif re.search(r"Fatal signal \d+|>>>\s*" + re.escape(PACKAGE) + r"\s*<<<", line):
            kind = "native_crash_marker"
        elif re.search(r"ANR in\s+" + exact, line):
            kind = "anr_marker"
        elif re.search(r"Process\s+" + exact + r".*has died", line):
            kind = "process_died_marker"
        elif "Start proc" in line:
            kind = "process_start_marker"
        elif own and re.search(r"Unhandled Exception|\[ERROR:flutter", line):
            kind = "dart_error_marker"
        elif own and re.search(r"Permission Denial|SecurityException", line):
            kind = "permission_error_marker"
        if kind:
            events.append({"device_time": header[1] if header else "UNKNOWN", "event": kind,
                           "association": "APP_PID" if own else "EXACT_PACKAGE_LINE"})
    return {"events": events, "associated_process_count": len(pids),
            "limit": "No matching record is not a pass. Native/system/service logs can be absent or inaccessible"}


def android_capture(adb, serial, seconds, alias):
    known_pids = []
    try:
        current = adb_read(adb, serial, "shell", "pidof", PACKAGE).strip()
        if re.fullmatch(r"\d+(?:\s+\d+)*", current):
            known_pids = [int(value) for value in current.split()]
    except DiagnosticError:
        pass  # Not running yet is expected when collecting a cold startup.
    args = [adb, "-s", serial, "logcat", "-b", "main", "-b", "system", "-b", "crash",
            "-v", "threadtime", "-T", "1", "ActivityManager:I", "ActivityTaskManager:I",
            "AndroidRuntime:E", "libc:F", "DEBUG:F", "flutter:E", "*:S"]
    try:
        process = subprocess.Popen(args, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                   stderr=subprocess.DEVNULL)
    except OSError as exc:
        raise DiagnosticError("adb unavailable") from exc
    lines = collections.deque(maxlen=4000)
    counts = {"seen": 0, "truncated_lines": 0}

    def reader():
        while True:
            raw = process.stdout.readline(2048)
            if not raw:
                break
            counts["seen"] += 1
            if len(raw) >= 2048:
                counts["truncated_lines"] += 1
            lines.append(raw.decode("utf-8", "replace").rstrip())

    thread = threading.Thread(target=reader, daemon=True)
    start = utc_now()
    thread.start()
    ended_early = False
    try:
        process.wait(timeout=seconds)
        ended_early = True
    except subprocess.TimeoutExpired:
        process.terminate()  # Only this logcat client, never Neura or adb server.
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=5)
    thread.join(timeout=5)
    if thread.is_alive():
        raise DiagnosticError("Logcat collector did not finish")
    result = sanitize_logcat(list(lines), known_pids)
    result.update({"scope": "FILTERED_ANDROID_STARTUP_MARKERS", "device_alias": alias,
                   "start_utc": start, "end_utc": utc_now(), "requested_seconds": seconds,
                   "collection": "BLOCKED" if ended_early and process.returncode else "AVAILABLE",
                   "ended_early": ended_early, "retained_lines_in_memory": len(lines),
                   "discarded_lines": max(0, counts["seen"]-len(lines)),
                   "truncated_lines": counts["truncated_lines"], "hardware_acceptance": "NOT RUN"})
    return result


def emulator_install_command(adb, serial, user, directory, build):
    """Print, never execute, a first-install command for an empty emulator."""
    verify_package(build, directory)
    if not serial.startswith("emulator-") or user != 0:
        raise DiagnosticError("Install-command helper is restricted to emulator user 0")
    if adb_read(adb, serial, "shell", "getprop", "ro.kernel.qemu").strip() != "1":
        raise DiagnosticError("Selected target is not a confirmed emulator")
    if adb_read(adb, serial, "shell", "am", "get-current-user").strip() != "0":
        raise DiagnosticError("Emulator foreground user is not 0")
    users = adb_read(adb, serial, "shell", "pm", "list", "users")
    if re.findall(r"UserInfo\{(\d+):", users) != ["0"]:
        raise DiagnosticError("Use a fresh single-user emulator; package code is shared between Android users")
    # Android code is shared between users. -u also catches retained data.
    listing = adb_read(adb, serial, "shell", "pm", "list", "packages", "-u", PACKAGE)
    if re.search(r"error|denied|exception|unknown", listing, re.I):
        raise DiagnosticError("Cannot establish empty emulator package state")
    if package_present(listing):
        raise DiagnosticError("Package or retained data already exists; use another fresh AVD")
    name = next(a["name"] for a in build["assets"] if a["name"].endswith(".apk"))
    command = [adb, "-s", serial, "install", "--user", "0", str(Path(directory).resolve()/name)]
    return {"scope": "COMMAND_ONLY_NOT_EXECUTED", "status": "PASS",
            "argv": command, "posix_command": shlex.join(command),
            "note": "Use argv or the PowerShell command in README. No install/update occurred. Confirm this AVD contains only disposable data"}


def evidence_template(build_id, platform, alias):
    return {"schema": 1, "created_utc": utc_now(), "device_alias": alias,
            "platform": platform, "build_catalog_id": build_id,
            "source_commit": "COPY_FROM_VERIFIED_PACKAGE_REPORT",
            "source_tree": "COPY_FROM_VERIFIED_PACKAGE_REPORT",
            "package_sha256": "COPY_FROM_VERIFIED_PACKAGE_REPORT",
            "installed_identity_verified": False, "isolated_synthetic_profile": False,
            "device_os_build": "NOT RECORDED", "recognizer_and_language": "NOT RECORDED",
            "offline_output_voice": "NOT RECORDED", "network_condition": "NOT RECORDED",
            "overall_hardware_acceptance": "NOT RUN",
            "results": [{"id": key, "status": "NOT RUN", "observed_utc": None,
                         "repetitions": 0, "observer": "NONE", "observation": "",
                         "sanitized_refs": []} for key in SCENARIOS],
            "status_rules": {"PASS": "All stated observations actually completed on this device/build",
                             "FAIL": "Observed deviation, crash, early capture, late text/audio or unexpected request",
                             "BLOCKED": "Cannot safely execute or prerequisite/diagnostic access unavailable",
                             "NOT RUN": "No observation yet"},
            "privacy": "Synthetic phrases only; no real audio, transcripts, journals, keys, account IDs or credentials"}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    subs = parser.add_subparsers(dest="action", required=True)
    for name in ("verify-package", "apk-identity", "android-snapshot", "android-capture",
                 "emulator-install-command", "new-record"):
        sub = subs.add_parser(name)
        sub.add_argument("--output", required=True, help="New JSON file; existing files are refused")
        if name in ("verify-package", "apk-identity", "emulator-install-command", "new-record"):
            sub.add_argument("--build", choices=tuple(load_catalog()["builds"]), required=True)
        if name in ("verify-package", "apk-identity", "emulator-install-command"):
            sub.add_argument("--directory", required=True, help="Directory containing the three exact release asset names")
        if name in ("android-snapshot", "android-capture", "emulator-install-command"):
            sub.add_argument("--adb", default="adb")
            sub.add_argument("--serial", required=True)
        if name in ("android-snapshot", "emulator-install-command"):
            sub.add_argument("--user", type=user_number, default=0)
        if name in ("android-snapshot", "android-capture", "new-record"):
            sub.add_argument("--alias", type=safe_alias, required=True)
        if name == "android-snapshot":
            sub.add_argument("--label", type=safe_alias, required=True)
        if name == "android-capture":
            sub.add_argument("--seconds", type=int, default=45, choices=range(1, 121))
        if name == "apk-identity":
            sub.add_argument("--java", default="java")
            sub.add_argument("--apksigner-jar", required=True)
            sub.add_argument("--aapt", required=True)
    args = parser.parse_args(argv)
    report = {"created_utc": utc_now(), "action": args.action}
    code = 0
    try:
        if Path(args.output).exists() or Path(args.output).is_symlink():
            raise DiagnosticError("Choose a new output filename")
        build = load_catalog()["builds"][args.build] if hasattr(args, "build") else None
        if args.action in ("apk-identity", "emulator-install-command") and build["platform"] != "android":
            raise DiagnosticError("This action requires an Android build")
        if args.action == "verify-package":
            report.update(verify_package(build, args.directory))
        elif args.action == "apk-identity":
            report.update(inspect_apk(build, args.directory, args.java, args.apksigner_jar, args.aapt))
        elif args.action == "android-snapshot":
            report.update(android_snapshot(args.adb, args.serial, args.user, args.alias, args.label))
            code = 2 if "BLOCKED" in report["collection"].values() or not report["user_matches"] else 0
        elif args.action == "android-capture":
            report.update(android_capture(args.adb, args.serial, args.seconds, args.alias))
            code = 2 if report["collection"] == "BLOCKED" else 0
        elif args.action == "emulator-install-command":
            report.update(emulator_install_command(args.adb, args.serial, args.user, args.directory, build))
        elif args.action == "new-record":
            report.update(evidence_template(args.build, build["platform"], args.alias))
    except DiagnosticError as exc:
        report.update({"status": "BLOCKED" if "unavailable" in str(exc).lower() or "timed out" in str(exc).lower()
                       else "FAIL", "reason": str(exc), "hardware_acceptance": "NOT RUN"})
        code = 2
    except (OSError, ValueError, KeyError, zipfile.BadZipFile, RuntimeError):
        report.update({"status": "BLOCKED", "reason": "Input unreadable, malformed or unsupported; no raw error exported",
                       "hardware_acceptance": "NOT RUN"})
        code = 2
    try:
        save_new(args.output, report)
    except OSError:
        print("Report could not be created. Choose a new writable output filename.", file=sys.stderr)
        return 2
    print("Diagnostic report created. Device observations remain separate.")
    return code


if __name__ == "__main__":
    sys.exit(main())
