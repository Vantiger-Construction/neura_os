"""Guard coverage accuracy, path boundaries, and incomplete-run reporting."""

import json
from pathlib import Path
import tempfile
import unittest

from report import line_ranges, make_report, parse_lcov, source_path, write_report


class CoverageReportTest(unittest.TestCase):
    def test_duplicate_records_and_lines_merge_without_inflating_denominator(self):
        result = parse_lcov(
            "SF:lib/memory.dart\nDA:1,0\nDA:2,1\nDA:2,3\nend_of_record\n"
            "SF:lib/memory.dart\nDA:1,2,checksum\nDA:3,0\nend_of_record\n",
            "/repo", "flutter")
        self.assertEqual(result, {"lib/memory.dart": {1: 2, 2: 4, 3: 0}})

    def test_actual_zero_coverage_is_valid_and_has_no_threshold(self):
        files = parse_lcov("SF:lib/untested.dart\nDA:1,0\nend_of_record", "/repo", "flutter")
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            report = make_report(files, root, "flutter", "Flutter", "abc", "success")
            markdown = write_report(report, root / "output")
            self.assertIn("0.00%", markdown)
            self.assertTrue(report["complete_test_run"])
            self.assertEqual(report["total"], 1)

    def test_absolute_windows_paths_match_case_insensitively(self):
        result = parse_lcov(
            "SF:d:\\a\\neura\\neura\\rust\\src\\engine_session.rs\r\n"
            "DA:12,4\r\nend_of_record\r\n", "D:/a/neura/neura", "rust")
        self.assertEqual(result, {"rust/src/engine_session.rs": {12: 4}})

    def test_integration_source_aliases_merge_into_the_production_module(self):
        result = parse_lcov(
            "SF:/repo/rust/src/engine_session.rs\nDA:12,0\nend_of_record\n"
            "SF:/repo/rust/tests/../src/engine_session.rs\nDA:12,4\nend_of_record\n",
            "/repo", "rust")
        self.assertEqual(result, {"rust/src/engine_session.rs": {12: 4}})
        self.assertEqual(source_path("D:\\repo\\rust\\tests\\..\\src\\engine_process.rs",
                                     "d:/repo", "rust"), "rust/src/engine_process.rs")

    def test_sources_outside_checkout_and_parent_traversal_are_excluded(self):
        for path in ("/repo-other/lib/a.dart", "/external/lib/a.dart",
                     "lib/../test/a.dart", "../lib/a.dart"):
            with self.subTest(path=path):
                self.assertIsNone(source_path(path, "/repo", "flutter"))
        self.assertEqual(source_path("/repo/lib/a.dart", "/repo", "flutter"), "lib/a.dart")

    def test_generated_and_test_helpers_do_not_enter_production_totals(self):
        for path in ("lib/a.g.dart", "lib/a.freezed.dart", "lib/rust_bridge/frb_generated.dart",
                     "test/a.dart"):
            self.assertIsNone(source_path(path, "/repo", "flutter"))
        for path in ("rust/src/frb_generated.rs", "rust/src/ipc_tests.rs", "rust/tests/a.rs"):
            self.assertIsNone(source_path(path, "/repo", "rust"))
        self.assertEqual(source_path("src/bin/neura_api.rs", "/repo", "rust"),
                         "rust/src/bin/neura_api.rs")

    def test_missing_or_truncated_data_cannot_produce_a_successful_report(self):
        for content in ("", "SF:lib/a.dart\nend_of_record", "SF:lib/a.dart\nDA:1,1",
                        "DA:1,1", "end_of_record", "SF:lib/a.dart\nSF:lib/b.dart",
                        "SF:lib/a.dart\nDA:1,-1\nend_of_record",
                        "SF:lib/a.dart\nDA:0,1\nend_of_record",
                        "SF:lib/a.dart\nDA:1\nend_of_record",
                        "SF:lib/a.dart\nDA:bad,1\nend_of_record"):
            with self.subTest(content=content), self.assertRaises(ValueError):
                parse_lcov(content, "/repo", "flutter")

    def test_lcov_metadata_does_not_change_measured_line_counts(self):
        result = parse_lcov(
            "TN:\nSF:lib/a.dart\nFN:1,f\nFNDA:3,f\nDA:1,3\nDA:2,0\n"
            "BRDA:2,0,0,-\nLF:200\nLH:200\nend_of_record\n", "/repo", "flutter")
        self.assertEqual(result, {"lib/a.dart": {1: 3, 2: 0}})

    def test_unmeasured_sources_are_visible_without_invented_counts(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "lib").mkdir()
            for name in ("tested.dart", "unimported.dart", "generated.g.dart"):
                (root / "lib" / name).write_text("// source\n", encoding="utf-8")
            report = make_report({"lib/tested.dart": {1: 1, 2: 0}}, root,
                                 "flutter", "Flutter", "abc", "success")
            self.assertEqual(report["unmeasured_files"], ["lib/unimported.dart"])
            self.assertEqual((report["covered"], report["total"]), (1, 2))

    def test_partial_run_and_html_escaping_survive_export(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            report = make_report({"lib/<script>.dart": {1: 0, 2: 0, 3: 1}}, root,
                                 "flutter", "Flutter <test>", "abc", "failure")
            write_report(report, root)
            exported = json.loads((root / "summary.json").read_text(encoding="utf-8"))
            self.assertFalse(exported["complete_test_run"])
            page = (root / "index.html").read_text(encoding="utf-8")
            self.assertIn("PARTIAL", page)
            self.assertIn("lib/&lt;script&gt;.dart", page)
            self.assertNotIn("lib/<script>.dart", page)
            self.assertEqual(exported["files"][0]["uncovered_lines"], [1, 2])

    def test_ranges_preserve_every_uncovered_line(self):
        self.assertEqual(line_ranges([9, 3, 1, 2, 7]), "1-3, 7, 9")
        self.assertEqual(line_ranges([]), "")


if __name__ == "__main__":
    unittest.main()
