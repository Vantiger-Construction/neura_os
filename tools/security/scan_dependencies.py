#!/usr/bin/env python3
"""Audit committed lockfiles; preserve evidence and fail closed on incomplete scans."""

import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys


LOCKFILES = {
    "pubspec.lock": "Pub",
    "rust/Cargo.lock": "crates.io",
    "tools/sync_tests/package-lock.json": "npm",
}


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def git(root, *args):
    return subprocess.check_output(["git", "-C", str(root), *args], text=True).strip()


def inspect_results(report, root):
    """A missing ecosystem, empty extraction or malformed result is not a pass."""
    counts = {}
    findings = []
    for result in report["results"]:
        source = result["source"]
        if source["type"] != "lockfile":
            raise ValueError("Unexpected non-lockfile input")
        path = Path(source["path"])
        relative = (root / path).resolve().relative_to(root).as_posix()
        expected = LOCKFILES[relative]
        packages = result["packages"]
        if relative in counts or not packages:
            raise ValueError("Duplicate or empty lockfile extraction: " + relative)
        counts[relative] = len(packages)
        if not any(p["package"]["ecosystem"] == expected for p in packages):
            raise ValueError("Expected ecosystem missing: " + relative)
        for package in packages:
            identity = package["package"]
            if not identity["name"] or not identity["version"]:
                raise ValueError("Package identity is incomplete")
            for advisory in package.get("vulnerabilities", []):
                findings.append({
                    "lockfile": relative,
                    "package": identity,
                    "advisory": advisory["id"],
                    "aliases": advisory.get("aliases", []),
                })
    if set(counts) != set(LOCKFILES):
        raise ValueError("Not all required lockfiles were analyzed")
    return counts, findings


def classify(exit_code, findings):
    if exit_code not in (0, 1):
        raise ValueError(f"Scanner did not complete successfully (exit {exit_code})")
    if bool(findings) != (exit_code == 1):
        raise ValueError("Scanner exit code and complete finding report disagree")
    return "findings" if findings else "no-known-findings"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scanner", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    receipt = {
        "started_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "status": "incomplete",
        "event": os.environ.get("GITHUB_EVENT_NAME", "local"),
        "event_sha": os.environ.get("GITHUB_SHA"),
        "run_id": os.environ.get("GITHUB_RUN_ID"),
        "run_attempt": os.environ.get("GITHUB_RUN_ATTEMPT"),
    }
    code = 2
    try:
        receipt["checkout_commit"] = git(root, "rev-parse", "HEAD")
        receipt["checkout_tree"] = git(root, "rev-parse", "HEAD^{tree}")
        receipt["working_tree_changes"] = git(root, "status", "--porcelain").splitlines()
        event_file = os.environ.get("GITHUB_EVENT_PATH")
        if event_file:
            pr = json.loads(Path(event_file).read_text()).get("pull_request", {})
            receipt["pr_head"] = pr.get("head", {}).get("sha")
            receipt["pr_base"] = pr.get("base", {}).get("sha")
        receipt["lockfile_sha256"] = {p: sha256(root / p) for p in LOCKFILES}
        scanner = args.scanner.resolve()
        receipt["scanner_sha256"] = sha256(scanner)
        receipt["scanner_version"] = subprocess.check_output(
            [str(scanner), "--version"], text=True, timeout=30
        ).strip()
        # Explicit empty config overrides inherited ignore rules. Keep every finding.
        config = output / "osv-scanner.toml"
        config.write_text("# No ignores, severity filters or reachability suppressions.\n")
        command = [
            str(scanner), "scan", "source", "--config=" + str(config),
            "--no-resolve", "--no-call-analysis=go", "--no-call-analysis=rust",
            "--all-vulns", "--all-packages", "--format=json",
            *("--lockfile=" + p for p in LOCKFILES),
        ]
        receipt["command"] = command
        with (output / "osv.json").open("w") as stdout, (output / "osv.stderr").open("w") as stderr:
            process = subprocess.run(command, cwd=root, stdout=stdout, stderr=stderr, timeout=600)
        receipt["scanner_exit_code"] = process.returncode
        report = json.loads((output / "osv.json").read_text())
        counts, findings = inspect_results(report, root)
        receipt["packages_per_lockfile"] = counts
        receipt["advisory_matches"] = findings
        if any(sha256(root / p) != h for p, h in receipt["lockfile_sha256"].items()):
            raise ValueError("Lockfile changed during analysis")
        receipt["status"] = classify(process.returncode, findings)
        code = process.returncode
    except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError) as error:
        receipt["error"] = str(error)
    finally:
        receipt["finished_at"] = datetime.datetime.now(datetime.timezone.utc).isoformat()
        (output / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
        summary = (
            "### Locked dependency vulnerability scan\n\n"
            f"Status: **{receipt['status']}**; checkout: `{receipt.get('checkout_commit', 'unavailable')}`.\n\n"
            f"Package counts: `{json.dumps(receipt.get('packages_per_lockfile', {}))}`.\n\n"
            f"Advisory/package matches: {len(receipt.get('advisory_matches', []))}. "
            "Full versions, advisories, errors and input hashes are in the audit artifact. "
            "No finding is automatically suppressed; runtime reachability is not established.\n"
        )
        (output / "summary.md").write_text(summary)
        if os.environ.get("GITHUB_STEP_SUMMARY"):
            with Path(os.environ["GITHUB_STEP_SUMMARY"]).open("a") as stream:
                stream.write(summary)
        print(summary)
    return code


if __name__ == "__main__":
    sys.exit(main())
