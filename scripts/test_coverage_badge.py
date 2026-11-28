import json
import subprocess
import sys

import coverage_badge
import pytest


def rust(covered, count):
    return {"data": [{"totals": {"lines": {"covered": covered, "count": count}}}]}


def python(covered, statements):
    return {"totals": {"covered_lines": covered, "num_statements": statements}}


def test_badge_combines_both_languages_by_line():
    result = coverage_badge.badge([rust(90, 100)], python(0, 100))
    assert result == {"schemaVersion": 1, "label": "coverage", "message": "45%", "color": "red"}


def test_badge_adds_every_rust_workspace():
    result = coverage_badge.badge([rust(90, 100), rust(100, 100)], python(80, 100))
    assert result["message"] == "90%"


def test_cli_reads_every_rust_report_before_the_python_one(tmp_path):
    paths = []
    for name, report in [("rust.json", rust(30, 40)), ("firmware.json", rust(10, 10)), ("python.json", python(5, 50))]:
        paths.append(tmp_path / name)
        paths[-1].write_text(json.dumps(report))
    out = tmp_path / "coverage.json"
    subprocess.run([sys.executable, coverage_badge.__file__, *paths, out], check=True, capture_output=True)
    assert json.loads(out.read_text())["message"] == "45%"


@pytest.mark.parametrize(
    ("percent", "expected"),
    [(100, "brightgreen"), (90, "brightgreen"), (89, "green"), (75, "green"), (60, "yellow"), (59, "red")],
)
def test_colour_steps_down_with_coverage(percent, expected):
    assert coverage_badge.colour(percent) == expected


def test_badge_refuses_an_empty_measurement():
    with pytest.raises(ValueError):
        coverage_badge.badge([rust(0, 0)], python(0, 0))
