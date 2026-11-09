"""Synthetic evidence validation only; never accesses an app, model or device."""
import copy
import csv
import datetime as dt
import json
from pathlib import Path
import tempfile
import unittest

import conversation_trial as c

IDENTITY = {"head_commit": "a"*40, "source_commit": "b"*40,
            "source_tree": "c"*40, "package_sha256": "d"*64,
            "executable_sha256": "e"*64}
START = dt.datetime(2026, 11, 8, 12, tzinfo=dt.timezone.utc)


def recorded(platform="windows"):
    record = c.new_trial(platform, "synthetic-device", dict(IDENTITY))
    record.update(isolation_confirmed=True, package_identity_confirmed=True,
                  operator_confirmed=True, started_utc=START.isoformat(),
                  ended_utc=(START+dt.timedelta(seconds=600)).isoformat(),
                  completed_turns=10, reply_complete_ms=list(range(1000, 11000, 1000)),
                  first_spoken_reply_ms=list(range(1100, 11100, 1000)))
    for result in record["results"]:
        result.update(status="PASS", observed_utc=START.isoformat())
    return record


def memory():
    return {"start_utc": START.isoformat(),
            "end_utc": (START+dt.timedelta(seconds=600)).isoformat(),
            "sample_span_seconds": 600}


class TrialTests(unittest.TestCase):
    def test_template_is_never_a_hardware_or_release_pass(self):
        result = c.assess(c.new_trial("windows", "synthetic", IDENTITY), IDENTITY)
        self.assertEqual(result["status"], "NOT RUN")
        self.assertEqual(result["release_approval"], "NOT GRANTED")
        self.assertFalse(result["physical_acceptance_independently_verified"])

    def test_complete_declaration_is_still_not_independent_acceptance(self):
        result = c.assess(recorded(), IDENTITY, memory())
        self.assertEqual(result["status"], "OPERATOR_RECORDED_PASS")
        self.assertEqual(result["reply_complete"]["median_ms"], 5500)
        self.assertEqual(result["reply_complete"]["p95_ms"], 10000)
        self.assertEqual(result["release_approval"], "NOT GRANTED")
        self.assertFalse(result["physical_acceptance_independently_verified"])

    def test_isolation_identity_and_operator_confirmation_are_separate(self):
        for flag in ("isolation_confirmed", "package_identity_confirmed", "operator_confirmed"):
            record = recorded(); record[flag] = False
            with self.subTest(flag=flag):
                self.assertEqual(c.assess(record, IDENTITY, memory())["status"], "NOT RUN")

    def test_first_failure_uses_observation_time_not_case_order(self):
        record = recorded()
        record["results"][0].update(status="FAIL", reason="WRONG_BUILD",
                                    observed_utc=(START+dt.timedelta(seconds=20)).isoformat())
        record["results"][5].update(status="FAIL", reason="NO_SPEECH",
                                    observed_utc=(START+dt.timedelta(seconds=10)).isoformat())
        result = c.assess(record, IDENTITY)
        self.assertEqual(result["first_failure"], {"case": "spoken_reply", "reason": "NO_SPEECH"})

    def test_failed_partial_trial_does_not_require_completed_measurements(self):
        record = c.new_trial("windows", "synthetic", IDENTITY)
        record["results"][0].update(status="FAIL", reason="NOT_ISOLATED",
                                    observed_utc=START.isoformat())
        self.assertEqual(c.assess(record, IDENTITY)["status"], "FAIL")

    def test_samsung_can_stay_blocked_without_an_install_or_false_pass(self):
        record = c.new_trial("android", "samsung-synthetic", IDENTITY)
        record["results"][0].update(status="BLOCKED", reason="NOT_ISOLATED",
                                    observed_utc=START.isoformat())
        self.assertEqual(c.assess(record, IDENTITY)["status"], "BLOCKED")

    def test_wrong_build_or_executable_is_rejected(self):
        for field in IDENTITY:
            record = recorded(); record["candidate"][field] = "f"*len(IDENTITY[field])
            with self.subTest(field=field), self.assertRaises(c.InvalidEvidence):
                c.assess(record, IDENTITY, memory())

    def test_missing_duplicate_and_unknown_cases_are_rejected(self):
        for mode in ("missing", "duplicate", "unknown"):
            record = recorded()
            if mode == "missing": record["results"].pop()
            elif mode == "duplicate": record["results"][1] = copy.deepcopy(record["results"][0])
            else: record["results"][0]["id"] = "not_a_case"
            with self.subTest(mode=mode), self.assertRaises(c.InvalidEvidence):
                c.assess(record, IDENTITY, memory())

    def test_short_reversed_and_unzoned_sessions_are_rejected(self):
        for end in ((START+dt.timedelta(seconds=599)).isoformat(),
                    (START-dt.timedelta(seconds=1)).isoformat(), "2026-11-08T12:10:00"):
            record = recorded(); record["ended_utc"] = end
            with self.subTest(end=end), self.assertRaises(c.InvalidEvidence):
                c.assess(record, IDENTITY, memory())

    def test_fewer_turns_and_mismatched_timing_count_are_rejected(self):
        for value in (9, 11, True):
            record = recorded(); record["completed_turns"] = value
            with self.subTest(value=value), self.assertRaises(c.InvalidEvidence):
                c.assess(record, IDENTITY, memory())

    def test_nonfinite_boolean_zero_and_outlier_timings_are_rejected(self):
        for value in (float("nan"), float("inf"), True, 0, 180001):
            record = recorded(); record["reply_complete_ms"][0] = value
            with self.subTest(value=value), self.assertRaises(c.InvalidEvidence):
                c.assess(record, IDENTITY, memory())

    def test_windows_requires_measurement_with_real_trial_overlap(self):
        self.assertEqual(c.assess(recorded(), IDENTITY)["status"], "BLOCKED")
        sample = memory(); sample["start_utc"] = (START+dt.timedelta(days=1)).isoformat()
        with self.assertRaises(c.InvalidEvidence):
            c.assess(recorded(), IDENTITY, sample)

    def test_private_freeform_fields_are_not_allowed(self):
        for location in ("root", "result"):
            record = recorded()
            target = record if location == "root" else record["results"][0]
            target["transcript"] = "SYNTHETIC_PRIVATE_TEXT"
            with self.subTest(location=location), self.assertRaises(c.InvalidEvidence):
                c.assess(record, IDENTITY, memory())

    def test_duplicate_json_keys_and_existing_reports_are_refused(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary)/"record.json"
            path.write_text('{"schema":1,"schema":2}')
            with self.assertRaises(c.InvalidEvidence): c.load_report(path)
            before = path.read_bytes()
            with self.assertRaises(FileExistsError): c.save_new(path, {})
            self.assertEqual(path.read_bytes(), before)


class MemoryTests(unittest.TestCase):
    def csv_file(self, directory, mutate=None):
        path = Path(directory)/"memory.csv"
        rows = []
        for seconds in range(0, 601, 2):
            row = [seconds*1000, (START+dt.timedelta(seconds=seconds)).isoformat(),
                   IDENTITY["executable_sha256"], 8*2**30, 4*2**30, 200*2**20, 2**30, 1]
            rows.append(row)
        if mutate: mutate(rows)
        with path.open("w", newline="") as stream:
            writer = csv.writer(stream); writer.writerow(c.CSV_FIELDS); writer.writerows(rows)
        return path

    def test_sampled_peak_and_available_memory_are_computed(self):
        with tempfile.TemporaryDirectory() as temporary:
            result = c.memory_summary(self.csv_file(temporary), IDENTITY["executable_sha256"])
            self.assertEqual(result["sample_span_seconds"], 600)
            self.assertEqual(result["lowest_available_bytes"], 4*2**30)
            self.assertEqual(result["sampled_peak_combined_working_set_bytes"], 200*2**20+2**30)

    def test_different_process_hash_backwards_time_and_long_gaps_fail(self):
        mutations = [lambda rows: rows[1].__setitem__(2, "f"*64),
                     lambda rows: rows[1].__setitem__(0, 0),
                     lambda rows: rows[1].__setitem__(1, START.isoformat()),
                     lambda rows: rows[1].__setitem__(0, 100000),
                     lambda rows: rows[1].__setitem__(4, 16*2**30)]
        for mutation in mutations:
            with tempfile.TemporaryDirectory() as temporary, self.subTest(mutation=mutation):
                with self.assertRaises(c.InvalidEvidence):
                    c.memory_summary(self.csv_file(temporary, mutation), IDENTITY["executable_sha256"])


if __name__ == "__main__":
    unittest.main()
