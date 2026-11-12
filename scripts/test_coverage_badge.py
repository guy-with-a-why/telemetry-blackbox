import coverage_badge
import pytest


def rust(covered, count):
    return {"data": [{"totals": {"lines": {"covered": covered, "count": count}}}]}


def python(covered, statements):
    return {"totals": {"covered_lines": covered, "num_statements": statements}}


def test_badge_combines_both_languages_by_line():
    result = coverage_badge.badge(rust(90, 100), python(0, 100))
    assert result == {"schemaVersion": 1, "label": "coverage", "message": "45%", "color": "red"}


@pytest.mark.parametrize(
    ("percent", "expected"),
    [(100, "brightgreen"), (90, "brightgreen"), (89, "green"), (75, "green"), (60, "yellow"), (59, "red")],
)
def test_colour_steps_down_with_coverage(percent, expected):
    assert coverage_badge.colour(percent) == expected


def test_badge_refuses_an_empty_measurement():
    with pytest.raises(ValueError):
        coverage_badge.badge(rust(0, 0), python(0, 0))
