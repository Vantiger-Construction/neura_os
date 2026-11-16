"""Check two Neura APK files offline before attempting a same-signer upgrade."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys


def sdk_output(command):
    """Let the SDK verify each file before interpreting its output."""
    result = subprocess.run(command, capture_output=True, text=True, check=True)
    return result.stdout


def inspect_apk(path, build_tools):
    certificates = sdk_output([
        "java", "-jar", build_tools / "lib" / "apksigner.jar",
        "verify", "--print-certs", path,
    ])
    signers = re.findall(r"^Signer #\d+ certificate SHA-256 digest: ([0-9a-fA-F]{64})$",
                         certificates, re.MULTILINE)
    aapt = build_tools / ("aapt.exe" if os.name == "nt" else "aapt")
    badging = sdk_output([aapt, "dump", "badging", path])
    package = re.search(r"^package: name='([^']+)' versionCode='(\d+)'", badging, re.MULTILINE)
    if not signers or not package:
        raise ValueError("Android Build Tools did not return the signer and package identity.")
    with path.open("rb") as stream:
        digest = hashlib.file_digest(stream, "sha256").hexdigest()
    return {
        "sha256": digest,
        "package": package[1],
        "version_code": int(package[2]),
        "signers_sha256": sorted(value.lower() for value in signers),
    }


def upgrade_blockers(previous, candidate):
    blockers = []
    if previous["package"] != "com.neurocompanion.app" or candidate["package"] != previous["package"]:
        blockers.append("Both APKs must use the Neura application ID.")
    if candidate["version_code"] <= previous["version_code"]:
        blockers.append("Candidate version code must increase for an upgrade.")
    if candidate["signers_sha256"] != previous["signers_sha256"]:
        blockers.append("Signer certificates differ. A same-signer upgrade is unavailable.")
    return blockers


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build-tools", type=Path, required=True)
    parser.add_argument("previous", type=Path)
    parser.add_argument("candidate", type=Path)
    args = parser.parse_args()
    try:
        previous = inspect_apk(args.previous.resolve(), args.build_tools)
        candidate = inspect_apk(args.candidate.resolve(), args.build_tools)
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"APK verification incomplete: {error}", file=sys.stderr)
        return 2
    blockers = upgrade_blockers(previous, candidate)
    print(json.dumps({"previous": previous, "candidate": candidate, "blockers": blockers}, indent=2))
    return 1 if blockers else 0


if __name__ == "__main__":
    sys.exit(main())
