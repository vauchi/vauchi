#!/usr/bin/env python3

"""
Coverage Check Script for CI/CD
Validates coverage against minimum thresholds and generates reports.
"""

import json
import sys
import os
import glob
from pathlib import Path


def load_coverage_data(pattern):
    """Load coverage data from JSON files matching pattern."""
    coverage_files = glob.glob(pattern)
    total_coverage = 0.0
    file_count = 0

    for file in coverage_files:
        try:
            with open(file, "r") as f:
                data = json.load(f)
                # Handle different coverage report formats
                if "percent" in data:
                    total_coverage += data["percent"]
                elif "total" in data:
                    total_coverage += data["total"].get("lines", {}).get("pct", 0)
                elif "coverage" in data:
                    total_coverage += data["coverage"]
                file_count += 1
        except (json.JSONDecodeError, FileNotFoundError) as e:
            print(f"Warning: Could not read coverage file {file}: {e}")
            continue

    return total_coverage, file_count


def check_minimum_coverage(minimum_percent):
    """Check if coverage meets minimum threshold."""

    # Rust coverage
    rust_patterns = [
        "coverage-reports/vauchi-core*/coverage.json",
        "coverage-reports/vauchi-relay*/coverage.json",
        "coverage-reports/vauchi-tui*/coverage.json",
        "coverage-reports/vauchi-mobile*/coverage.json",
    ]

    rust_results = []
    for pattern in rust_patterns:
        coverage, file_count = load_coverage_data(pattern)
        rust_results.append(
            {
                "component": pattern.split("/")[1].split("*")[0],
                "coverage": coverage,
                "file_count": file_count,
                "meets_minimum": coverage >= minimum_percent,
            }
        )

    # Frontend coverage
    frontend_pattern = "coverage-reports/desktop/coverage-summary.json"
    frontend_coverage, file_count = load_coverage_data(frontend_pattern)
    frontend_results = [
        {
            "component": "vauchi-desktop",
            "coverage": frontend_coverage,
            "file_count": file_count,
            "meets_minimum": frontend_coverage >= minimum_percent,
        }
    ]

    # Combine results
    all_results = rust_results + frontend_results

    # Generate report
    print(f"Coverage Check Results (Minimum: {minimum_percent}%):")
    print("=" * 50)

    failed_count = 0
    for result in all_results:
        status = "✅ PASS" if result["meets_minimum"] else "❌ FAIL"
        coverage_str = f"{result['coverage']:.1f}%"

        print(
            f"{result['component']:<15} {status:<10} {coverage_str:<10} ({result['file_count']} files)"
        )

        if not result["meets_minimum"]:
            failed_count += 1

    print("=" * 50)

    # Generate JSON for CI consumption
    report_data = {
        "minimum_percent": minimum_percent,
        "timestamp": os.environ.get("GITHUB_SHA", "local"),
        "results": all_results,
        "summary": {
            "total_components": len(all_results),
            "passed": len(all_results) - failed_count,
            "failed": failed_count,
            "overall_success": failed_count == 0,
        },
    }

    # Write report file
    with open("coverage-report.json", "w") as f:
        json.dump(report_data, f, indent=2)

    # Exit with appropriate code
    if failed_count > 0:
        print(
            f"\n❌ Coverage check failed: {failed_count} component(s) below {minimum_percent}%"
        )
        sys.exit(1)
    else:
        print(f"\n✅ All components meet minimum coverage of {minimum_percent}%")
        sys.exit(0)


def main():
    if len(sys.argv) != 2:
        print("Usage: python3 check-coverage.py <minimum_percent>")
        sys.exit(1)

    try:
        minimum_percent = float(sys.argv[1])
    except ValueError:
        print("Error: Minimum percent must be a number")
        sys.exit(1)

    if not 0 <= minimum_percent <= 100:
        print("Error: Minimum percent must be between 0 and 100")
        sys.exit(1)

    check_minimum_coverage(minimum_percent)


if __name__ == "__main__":
    main()
