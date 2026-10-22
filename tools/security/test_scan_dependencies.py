"""Regression cases for false-green scan results; no network or application data."""

import copy
from pathlib import Path
import unittest

from scan_dependencies import LOCKFILES, classify, inspect_results


class ScanEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.root = Path("/synthetic/neura")
        self.report = {"results": [
            {"source": {"path": str(self.root / path), "type": "lockfile"},
             "packages": [{"package": {"name": "synthetic", "version": "1.0.0", "ecosystem": ecosystem}}]}
            for path, ecosystem in LOCKFILES.items()
        ]}

    def test_complete_clean_report(self):
        counts, findings = inspect_results(self.report, self.root)
        self.assertEqual(set(counts), set(LOCKFILES))
        self.assertEqual(classify(0, findings), "no-known-findings")

    def test_findings_still_fail(self):
        self.report["results"][0]["packages"][0]["vulnerabilities"] = [
            {"id": "SYNTHETIC-1", "aliases": ["SYNTHETIC-ALIAS"]}
        ]
        _, findings = inspect_results(self.report, self.root)
        self.assertEqual(findings[0]["advisory"], "SYNTHETIC-1")
        self.assertEqual(classify(1, findings), "findings")
        with self.assertRaises(ValueError):
            classify(0, findings)

    def test_partial_or_empty_extraction_is_incomplete(self):
        for report in [{"results": []}, {"results": self.report["results"][:-1]}]:
            with self.subTest(report=report), self.assertRaises(ValueError):
                inspect_results(report, self.root)
        self.report["results"][0]["packages"] = []
        with self.assertRaises(ValueError):
            inspect_results(self.report, self.root)

    def test_wrong_ecosystem_is_incomplete(self):
        self.report["results"][0]["packages"][0]["package"]["ecosystem"] = "npm"
        with self.assertRaises(ValueError):
            inspect_results(self.report, self.root)

    def test_duplicate_source_is_incomplete(self):
        self.report["results"].append(copy.deepcopy(self.report["results"][0]))
        with self.assertRaises(ValueError):
            inspect_results(self.report, self.root)

    def test_outside_source_is_rejected(self):
        self.report["results"][0]["source"]["path"] = "/unrelated/pubspec.lock"
        with self.assertRaises(ValueError):
            inspect_results(self.report, self.root)

    def test_scanner_errors_and_empty_finding_exit_are_not_clean(self):
        for code in (1, 2, 127, 128, -9):
            with self.subTest(code=code), self.assertRaises(ValueError):
                classify(code, [])


if __name__ == "__main__":
    unittest.main()
