#!/usr/bin/env python3
"""Run the repository's shell-based tests and return a CI-friendly status."""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
TEST_ROOT = ROOT / "tests"


def discover_tests() -> list[Path]:
    return sorted(TEST_ROOT.glob("**/test_*.sh"))


def run_test(test_path: Path) -> bool:
    relative_path = test_path.relative_to(ROOT)
    print(f"\n=== {relative_path} ===")
    result = subprocess.run(["bash", str(test_path)], cwd=ROOT, check=False)
    if result.returncode == 0:
        print(f"PASS: {relative_path}")
        return True
    print(f"FAIL: {relative_path} (exit {result.returncode})")
    return False


def main() -> int:
    test_paths = discover_tests()
    if not test_paths:
        print("No tests found.", file=sys.stderr)
        return 2

    passed_count = 0
    for test_path in test_paths:
        if run_test(test_path):
            passed_count += 1

    failed_count = len(test_paths) - passed_count
    print(f"\nSummary: {passed_count} passed, {failed_count} failed")
    return 0 if failed_count == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
