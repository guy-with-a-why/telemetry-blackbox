import json

import flight

NOW = "2026-11-13T09:00:00Z"
DAY_0 = {"number": 1, "title": "Day 0 · The bench", "due_on": "2026-11-12T00:00:00Z"}
DAY_1 = {"number": 2, "title": "Day 1 · Firmware and the wire", "due_on": "2026-11-13T00:00:00Z"}
STRETCH = {"number": 6, "title": "Stretch", "due_on": None}


def issue(number, state="open", milestone=None, created="2026-11-12T10:00:00Z", closed=None, **extra):
    return {
        "number": number,
        "title": f"Issue {number}",
        "state": state,
        "milestone": milestone,
        "created_at": created,
        "closed_at": closed,
        **extra,
    }


def test_parse_keeps_text_that_looks_like_a_page_break():
    pages = [[issue(1, title="[a][b]")], [issue(2)]]
    issues = flight.parse(json.dumps(pages))
    assert [i["title"] for i in issues] == ["[a][b]", "Issue 2"]


def test_parse_drops_pull_requests_and_dropped_work():
    pages = [[issue(1), issue(2, pull_request={}), issue(3, state="closed", state_reason="not_planned")]]
    assert [i["number"] for i in flight.parse(json.dumps(pages))] == [1]


def test_plan_orders_legs_and_sets_aside_the_bonus():
    issues = [issue(1, milestone=DAY_1), issue(2, milestone=DAY_0), issue(3, milestone=STRETCH), issue(4)]
    plan = flight.plan(issues, NOW)
    assert [leg.title for leg in plan.legs] == [DAY_0["title"], DAY_1["title"]]
    assert [i["number"] for i in plan.bonus] == [3, 4]


def test_headwind_counts_issues_opened_after_takeoff():
    issues = [issue(1, milestone=DAY_0), issue(2, milestone=DAY_0, created="2026-11-12T18:00:00Z")]
    assert flight.plan(issues, NOW).headwind == 1


def test_status():
    def leg(due, *states):
        return flight.Leg("Day", due, [issue(n, state=s) for n, s in enumerate(states)])

    assert flight.status(leg("2026-11-12T00:00:00Z", "closed", "closed"), NOW)[0] == "landed"
    assert flight.status(leg("2026-11-12T00:00:00Z", "closed", "open"), NOW)[0] == "late"
    assert flight.status(leg("2026-11-13T00:00:00Z", "open"), NOW)[0] == "on course"  # due today
    assert flight.status(leg(None), NOW)[0] == "on course"  # an empty leg hasn't landed


def test_an_empty_flight_still_draws():
    plan = flight.plan([], NOW)
    assert "0 of 0 issues · 0%" in flight.strip(plan)
    assert "**0 of 0 issues closed (0%).**" in flight.log(plan)


def test_log_lists_landed_issues_newest_first_then_the_bonus():
    issues = [
        issue(1, "closed", DAY_0, closed="2026-11-12T11:00:00Z"),
        issue(2, "closed", DAY_0, closed="2026-11-12T15:00:00Z"),
        issue(3, milestone=DAY_0),
        issue(4, milestone=STRETCH),
    ]
    lines = flight.log(flight.plan(issues, NOW)).splitlines()
    tasks = [line[:9] for line in lines if line.startswith("- [")]
    assert tasks == ["- [x] #2 ", "- [x] #1 ", "- [ ] #3 ", "- [ ] #4 "]
    assert "*bonus*" in lines


def test_plane_is_the_mark_without_its_title():
    mark = flight.plane()
    assert "clipPath" in mark
    assert "<title" not in mark and "<svg" not in mark
