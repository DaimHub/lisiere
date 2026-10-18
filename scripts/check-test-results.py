#!/usr/bin/env python3
"""Require a nonempty XCTest run with every test passed, including animation tests."""
import argparse
import json
from pathlib import Path
import subprocess


def require_complete(summary: dict) -> int:
    counts = ["totalTestCount", "passedTests", "failedTests", "skippedTests", "expectedFailures"]
    if not isinstance(summary, dict) or any(
        type(summary.get(key)) is not int or summary[key] < 0 for key in counts
    ):
        raise ValueError("XCTest summary is missing valid test counts")
    total = summary["totalTestCount"]
    if (summary.get("result") != "Passed" or total == 0 or summary["passedTests"] != total
            or any(summary[key] != 0 for key in ["failedTests", "skippedTests", "expectedFailures"])):
        raise ValueError(
            f"Incomplete XCTest run: {summary['passedTests']}/{total} passed, "
            f"{summary['failedTests']} failed, {summary['skippedTests']} skipped, "
            f"{summary['expectedFailures']} expected failures"
        )
    return total


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("result_bundle", type=Path)
    args = parser.parse_args()
    try:
        result = subprocess.run(
            ["xcrun", "xcresulttool", "get", "test-results", "summary",
             "--path", str(args.result_bundle), "--compact"],
            check=True, capture_output=True, text=True,
        )
        summary = json.loads(result.stdout)
        args.result_bundle.with_suffix(".summary.json").write_text(json.dumps(summary, indent=2) + "\n")
        total = require_complete(summary)
        print(f"XCTest gate: {total} passed, 0 failed, 0 skipped, 0 expected failures")
    except (OSError, subprocess.CalledProcessError, ValueError) as error:
        parser.error(str(error))
