import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("test_results", ROOT / "scripts/check-test-results.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class TestResultsGateTests(unittest.TestCase):
    def summary(self, **overrides):
        return dict(result="Passed", totalTestCount=309, passedTests=309,
                    failedTests=0, skippedTests=0, expectedFailures=0) | overrides

    def test_complete_success_is_accepted(self):
        self.assertEqual(module.require_complete(self.summary()), 309)

    def test_success_with_skipped_tests_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "2 skipped"):
            module.require_complete(self.summary(passedTests=307, skippedTests=2))

    def test_empty_run_is_rejected(self):
        with self.assertRaises(ValueError):
            module.require_complete(self.summary(totalTestCount=0, passedTests=0))

    def test_failures_and_expected_failures_are_rejected(self):
        for field in ["failedTests", "expectedFailures"]:
            with self.subTest(field=field), self.assertRaises(ValueError):
                module.require_complete(self.summary(passedTests=308, **{field: 1}))

    def test_malformed_or_missing_counts_are_rejected(self):
        for value in [None, [], {}, self.summary(skippedTests="0"), self.summary(failedTests=-1),
                      self.summary(expectedFailures=False)]:
            with self.subTest(value=value), self.assertRaises(ValueError):
                module.require_complete(value)

    def test_inconsistent_status_or_counts_are_rejected(self):
        for value in [self.summary(result="Failed"), self.summary(passedTests=308)]:
            with self.subTest(value=value), self.assertRaises(ValueError):
                module.require_complete(value)
