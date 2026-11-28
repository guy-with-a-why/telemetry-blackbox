"""Turns the Rust and Python coverage reports into one badge.

    python3 scripts/coverage_badge.py RUST_JSON... PYTHON_JSON OUT_JSON

Each RUST_JSON comes from `cargo llvm-cov --json --summary-only`, one for each
Cargo workspace, and PYTHON_JSON from pytest-cov's JSON report. The badge
shows line coverage across all of them, as a shields.io endpoint that the docs
site serves next to the flight strip.
"""

import json
import sys
from pathlib import Path


def rust_lines(report: dict) -> tuple[int, int]:
    lines = report["data"][0]["totals"]["lines"]
    return lines["covered"], lines["count"]


def python_lines(report: dict) -> tuple[int, int]:
    totals = report["totals"]
    return totals["covered_lines"], totals["num_statements"]


def colour(percent: float) -> str:
    if percent >= 90:
        return "brightgreen"
    if percent >= 75:
        return "green"
    if percent >= 60:
        return "yellow"
    return "red"


def badge(rust: list[dict], python: dict) -> dict:
    counts = [rust_lines(report) for report in rust] + [python_lines(python)]
    covered = sum(lines for lines, _ in counts)
    total = sum(lines for _, lines in counts)
    if total == 0:
        raise ValueError("no lines measured")
    percent = 100 * covered / total
    return {"schemaVersion": 1, "label": "coverage", "message": f"{percent:.0f}%", "color": colour(percent)}


def main(rust_paths: list[str], python_path: str, out_path: str) -> None:
    rust = [json.loads(Path(path).read_text()) for path in rust_paths]
    python = json.loads(Path(python_path).read_text())
    result = badge(rust, python)
    Path(out_path).write_text(json.dumps(result) + "\n")
    print(f"coverage {result['message']}")


if __name__ == "__main__":
    if len(sys.argv) < 4:
        sys.exit(__doc__)
    main(sys.argv[1:-2], *sys.argv[-2:])
