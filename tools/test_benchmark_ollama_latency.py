import unittest

from benchmark_ollama_latency import percentile, quality_check, summarize


class BenchmarkSummaryTest(unittest.TestCase):
    def test_nearest_rank_and_absent_measurements(self):
        self.assertIsNone(percentile([], .95))
        self.assertEqual(percentile(list(range(1, 21)), .5), 10)
        self.assertEqual(percentile(list(range(1, 21)), .95), 19)

    def test_failures_never_improve_latency_or_quality_denominators(self):
        summary = summarize([
            {"status": "delivered", "total_ms": 100, "peak_bytes": 20,
             "quality_pass": True, "memory_sampling_complete": True},
            {"status": "failed", "total_ms": 1, "peak_bytes": 30},
            {"status": "admission_rejected", "total_ms": 0},
        ])
        self.assertEqual(summary["total_ms"], {"n": 1, "p50": 100, "p95": 100})
        self.assertEqual(summary["failures"]["failed"], 1)
        self.assertEqual(summary["failures"]["admission_rejected"], 1)
        self.assertEqual(summary["synthetic_quality_evaluated"], 1)
        self.assertEqual(summary["sampled_combined_peak_working_set_bytes"], 30)
        self.assertEqual(summary["incomplete_memory_samples"], 2)

    def test_no_success_is_not_zero_millisecond_performance(self):
        summary = summarize([{"status": "timeout"}])
        self.assertEqual(summary["total_ms"], {"n": 0, "p50": None, "p95": None})
        self.assertEqual(summary["failures"]["timeout"], 1)

    def test_even_sample_median_and_nearest_rank_p95(self):
        summary = summarize([{"status": "delivered", "total_ms": value}
                             for value in range(1, 21)])
        self.assertEqual(summary["total_ms"], {"n": 20, "p50": 10.5, "p95": 19})

    def test_quality_is_an_explicitly_limited_fixed_rubric(self):
        self.assertTrue(quality_check("arithmetic", "4."))
        self.assertFalse(quality_check("arithmetic", "5"))
        self.assertFalse(quality_check("uncertainty", "I guarantee success."))
        self.assertIsNone(quality_check("unknown", "anything"))


if __name__ == "__main__":
    unittest.main()
