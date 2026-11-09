#!/usr/bin/env python3
"""Local, operator-recorded acceptance. Never launches an app or opens a mic.

Reports are declarations, not device attestation. Synthetic CI must never be
presented as an observed laptop or Samsung result. No uploads are implemented.
"""
import argparse
import csv
import datetime as dt
import json
import math
from pathlib import Path
import re
import statistics
import sys

from diagnose import save_new

CASES = (
    "isolated_build_identity", "startup", "model_readiness", "local_text_reply",
    "microphone_input", "spoken_reply", "follow_up_context", "interrupt_reply",
    "recognition_failure_requires_retry", "stop_session", "background_no_restart",
    "safe_mode_microphone_off", "missing_model_no_cloud_fallback",
    "fresh_cloud_approval", "daily_plan", "journal_save_reopen",
    "memory_requires_separate_consent",
)
REASONS = {"NONE", "NO_START", "NO_MIC", "HEARS_NO_REPLY", "NO_SPEECH",
           "MODEL_UNAVAILABLE", "LOW_MEMORY", "CRASH", "UNEXPECTED_RESTART",
           "UNEXPECTED_CLOUD", "UNEXPECTED_MEMORY", "WRONG_BUILD",
           "NOT_ISOLATED", "DEVICE_ACCESS_UNAVAILABLE", "PLATFORM_UNSUPPORTED",
           "OTHER_WITHHELD"}
IDENTITY_KEYS = {"head_commit", "source_commit", "source_tree", "package_sha256",
                 "executable_sha256"}
CSV_FIELDS = ["elapsed_ms", "utc", "executable_sha256", "total_physical_bytes",
              "available_physical_bytes", "neura_working_set_bytes",
              "matching_ollama_working_set_bytes", "matching_ollama_processes"]


class InvalidEvidence(ValueError):
    pass


def require(condition):
    if not condition:
        raise InvalidEvidence("Invalid or incomplete evidence schema")


def keys(value, expected):
    require(isinstance(value, dict) and set(value) == set(expected))


def number(value, minimum=0, maximum=2**60):
    require(type(value) in (int, float) and math.isfinite(value)
            and minimum <= value <= maximum)
    return value


def timestamp(value):
    require(isinstance(value, str) and len(value) <= 40)
    try:
        result = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as exc:
        raise InvalidEvidence("Invalid timestamp") from exc
    require(result.tzinfo is not None)
    return result


def identity(value):
    keys(value, IDENTITY_KEYS)
    for field in IDENTITY_KEYS:
        size = 40 if field in ("head_commit", "source_commit", "source_tree") else 64
        require(isinstance(value[field], str)
                and re.fullmatch("[0-9a-f]{" + str(size) + "}", value[field]))


def new_trial(platform, alias, candidate):
    identity(candidate)
    require(platform in ("windows", "android"))
    require(re.fullmatch(r"[A-Za-z0-9_-]{1,48}", alias))
    return {
        "schema": 1, "kind": "OPERATOR_RECORDED_NOT_ATTESTED",
        "platform": platform, "device_alias": alias, "candidate": candidate,
        "isolation_confirmed": False, "package_identity_confirmed": False,
        "operator_confirmed": False, "started_utc": None, "ended_utc": None,
        "completed_turns": 0, "reply_complete_ms": [], "first_spoken_reply_ms": [],
        "results": [{"id": case, "status": "NOT RUN", "observed_utc": None,
                     "reason": "NONE"} for case in CASES],
    }


def unique_object(pairs):
    result = {}
    for name, value in pairs:
        require(name not in result)
        result[name] = value
    return result


def load_report(path):
    path = Path(path)
    require(path.is_file() and not path.is_symlink() and path.stat().st_size <= 65536)
    return json.loads(path.read_text(encoding="utf-8-sig"),
                      object_pairs_hook=unique_object,
                      parse_constant=lambda _: (_ for _ in ()).throw(InvalidEvidence()))


def memory_summary(path, expected_executable):
    path = Path(path)
    require(path.is_file() and not path.is_symlink() and path.stat().st_size <= 2**20)
    with path.open(encoding="utf-8-sig", newline="") as stream:
        reader = csv.DictReader(stream)
        require(reader.fieldnames == CSV_FIELDS)
        rows = []
        previous = -1
        for row in reader:
            require(len(rows) < 2000 and set(row) == set(CSV_FIELDS))
            require(row["executable_sha256"] == expected_executable)
            values = {}
            for field in CSV_FIELDS:
                if field in ("utc", "executable_sha256"):
                    continue
                require(re.fullmatch(r"\d{1,19}", row[field] or ""))
                values[field] = number(int(row[field]))
            require(values["elapsed_ms"] > previous)
            require(0 < values["total_physical_bytes"]
                    and values["available_physical_bytes"] <= values["total_physical_bytes"])
            values["time"] = timestamp(row["utc"])
            if rows:
                require(values["time"] > rows[-1]["time"])
                require(values["elapsed_ms"] - previous <= 30000)
                require((values["time"] - rows[-1]["time"]).total_seconds() <= 30)
            rows.append(values)
            previous = values["elapsed_ms"]
    require(len(rows) >= 2)
    span = (rows[-1]["elapsed_ms"] - rows[0]["elapsed_ms"]) / 1000
    wall_span = (rows[-1]["time"] - rows[0]["time"]).total_seconds()
    require(abs(span - wall_span) <= 10)
    return {
        "samples": len(rows), "sample_span_seconds": span,
        "start_utc": rows[0]["time"].isoformat(),
        "end_utc": rows[-1]["time"].isoformat(),
        "total_physical_bytes": min(r["total_physical_bytes"] for r in rows),
        "lowest_available_bytes": min(r["available_physical_bytes"] for r in rows),
        "sampled_peak_combined_working_set_bytes": max(
            r["neura_working_set_bytes"] + r["matching_ollama_working_set_bytes"]
            for r in rows),
        "limit": "Sampled working sets; excludes unrecognized model processes, GPU memory and peaks between samples",
    }


def latency_summary(values):
    require(isinstance(values, list) and 10 <= len(values) <= 100)
    for value in values:
        number(value, 1, 180000)
    ordered = sorted(values)
    return {"samples": len(values), "median_ms": statistics.median(values),
            "p95_ms": ordered[math.ceil(len(values) * .95) - 1],
            "method": "Operator-measured; timing method and reaction error require separate interpretation"}


def assess(report, expected, memory=None):
    keys(report, {"schema", "kind", "platform", "device_alias", "candidate",
                  "isolation_confirmed", "package_identity_confirmed", "operator_confirmed",
                  "started_utc", "ended_utc", "completed_turns", "reply_complete_ms",
                  "first_spoken_reply_ms", "results"})
    require(type(report["schema"]) is int and report["schema"] == 1
            and report["kind"] == "OPERATOR_RECORDED_NOT_ATTESTED")
    require(report["platform"] in ("windows", "android"))
    require(isinstance(report["device_alias"], str)
            and re.fullmatch(r"[A-Za-z0-9_-]{1,48}", report["device_alias"]))
    identity(report["candidate"])
    identity(expected)
    require(report["candidate"] == expected)
    for flag in ("isolation_confirmed", "package_identity_confirmed", "operator_confirmed"):
        require(type(report[flag]) is bool)
    require(type(report["completed_turns"]) is int and 0 <= report["completed_turns"] <= 100)
    require(isinstance(report["results"], list) and len(report["results"]) == len(CASES))
    seen, failures, outstanding = set(), [], []
    for row in report["results"]:
        keys(row, {"id", "status", "observed_utc", "reason"})
        require(isinstance(row["id"], str) and row["id"] in CASES and row["id"] not in seen)
        seen.add(row["id"])
        require(row["status"] in ("PASS", "FAIL", "BLOCKED", "NOT RUN"))
        require(row["reason"] in REASONS)
        if row["status"] != "NOT RUN":
            observed = timestamp(row["observed_utc"])
            if row["status"] == "FAIL":
                require(row["reason"] != "NONE")
                failures.append((observed, row["id"], row["reason"]))
        else:
            require(row["observed_utc"] is None and row["reason"] == "NONE")
        if row["status"] != "PASS":
            outstanding.append(row["id"])
    result = {"schema": 1, "basis": "OPERATOR_DECLARATIONS_NOT_DEVICE_ATTESTATION",
              "candidate": expected, "platform": report["platform"],
              "status": "NOT RUN", "first_failure": None, "outstanding": outstanding,
              "release_approval": "NOT GRANTED", "physical_acceptance_independently_verified": False}
    if failures:
        first = min(failures)
        result.update(status="FAIL", first_failure={"case": first[1], "reason": first[2]})
        return result
    if outstanding or not all(report[f] for f in (
            "isolation_confirmed", "package_identity_confirmed", "operator_confirmed")):
        result["status"] = "BLOCKED" if any(r["status"] == "BLOCKED" for r in report["results"]) else "NOT RUN"
        return result
    start, end = timestamp(report["started_utc"]), timestamp(report["ended_utc"])
    require(600 <= (end - start).total_seconds() <= 3600)
    require(report["completed_turns"] >= 10)
    result["reply_complete"] = latency_summary(report["reply_complete_ms"])
    result["first_spoken_reply"] = latency_summary(report["first_spoken_reply_ms"])
    require(len(report["reply_complete_ms"]) == report["completed_turns"]
            and len(report["first_spoken_reply_ms"]) == report["completed_turns"])
    if report["platform"] == "windows":
        if memory is None:
            result.update(status="BLOCKED", outstanding=["windows_memory_measurement"])
            return result
        overlap = (min(end, timestamp(memory["end_utc"]))
                   - max(start, timestamp(memory["start_utc"]))).total_seconds()
        require(memory["sample_span_seconds"] >= 540 and overlap >= 540)
        result["memory"] = memory
    # A recorded pass is never an independent approval or an automated hardware pass.
    result["status"] = "OPERATOR_RECORDED_PASS"
    return result


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("new", "assess"))
    parser.add_argument("--platform", choices=("windows", "android"), default="windows")
    parser.add_argument("--alias", default="synthetic-laptop")
    for field in sorted(IDENTITY_KEYS):
        parser.add_argument("--" + field.replace("_", "-"), required=True)
    parser.add_argument("--input")
    parser.add_argument("--memory-csv")
    parser.add_argument("--output", required=True)
    args = parser.parse_args(argv)
    expected = {field: getattr(args, field) for field in IDENTITY_KEYS}
    try:
        identity(expected)
        if args.action == "new":
            result = new_trial(args.platform, args.alias, expected)
        else:
            require(args.input is not None)
            memory = memory_summary(args.memory_csv, expected["executable_sha256"]) if args.memory_csv else None
            result = assess(load_report(args.input), expected, memory)
        save_new(args.output, result)
        return 0 if args.action == "new" or result["status"] == "OPERATOR_RECORDED_PASS" else 2
    except (OSError, ValueError, TypeError, KeyError, OverflowError):
        print("Evidence unavailable, malformed, mismatched or output already exists; no private input echoed.", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
