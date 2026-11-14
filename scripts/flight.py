"""Draws the flight-progress strip and the flight log from the repo's issues.

    python3 scripts/flight.py      # writes docs/flight.svg and docs/flight-log.md

Every milestone with a due date is a leg, flown in due-date order. Progress
counts every issue in the legs. Stretch has no due date, so its issues are a
bonus. Issues closed as not planned drop out, and issues opened after takeoff
(the moment the tracker launched) are headwind: scope that crept in on the way.

GitHub timestamps are ISO 8601 in UTC, so they compare correctly as strings.
"""

import json
import subprocess
import sys
from dataclasses import dataclass
from datetime import UTC, datetime
from html import escape
from pathlib import Path
from typing import Any
from xml.etree import ElementTree

TAKEOFF = "2026-11-12T17:25:24Z"  # the tracker launched with #39; anything newer is headwind
STAMPS = {
    11: "Built it by hand",
    12: "Survived quorum loss",
    13: "etcd restored",
    23: "First flight",
    27: "Zero frames lost",
    30: "Defended the design",
}
DOCS = Path(__file__).resolve().parent.parent / "docs"
SVG_NS = "http://www.w3.org/2000/svg"

ORANGE, SLATE, DIM, RED = "#f2662b", "#8b97a6", "#30363d", "#f07167"
BACKGROUND, TEXT, FAINT = "#0d1117", "#eaecef", "#6b7785"

Issue = dict[str, Any]  # an issue as the GitHub REST API returns it


@dataclass
class Leg:
    """One milestone with a due date, and its issues."""

    title: str
    due_on: str | None
    issues: list[Issue]


@dataclass
class Flight:
    legs: list[Leg]
    bonus: list[Issue]  # Stretch and unplanned issues
    closed: set[int]  # every closed issue number, for the stamps
    now: str

    @property
    def tracked(self) -> list[Issue]:
        return [i for leg in self.legs for i in leg.issues]

    @property
    def done(self) -> int:
        return closed_count(self.tracked)

    @property
    def total(self) -> int:
        return len(self.tracked)

    @property
    def progress(self) -> float:
        return self.done / self.total if self.total else 0.0

    @property
    def headwind(self) -> int:
        return sum(i["created_at"] > TAKEOFF for i in self.tracked)


def closed_count(items: list[Issue]) -> int:
    return sum(i["state"] == "closed" for i in items)


def fetch() -> str:
    command = ["gh", "api", "--paginate", "--slurp", "repos/{owner}/{repo}/issues?state=all&per_page=100"]
    try:
        return subprocess.run(command, check=True, capture_output=True, text=True).stdout
    except FileNotFoundError:
        sys.exit("flight: gh is not installed")
    except subprocess.CalledProcessError as error:
        sys.exit(f"flight: gh failed: {error.stderr.strip()}")


def parse(out: str) -> list[Issue]:
    """Countable issues from `gh api --paginate --slurp`, which returns a list of pages."""
    issues = [i for page in json.loads(out) for i in page]
    return [i for i in issues if "pull_request" not in i and i.get("state_reason") != "not_planned"]


def plan(issues: list[Issue], now: str) -> Flight:
    legs: dict[int, Leg] = {}
    bonus = []
    for i in issues:
        m = i.get("milestone")
        if m and m.get("due_on"):
            legs.setdefault(m["number"], Leg(m["title"], m["due_on"], [])).issues.append(i)
        else:
            bonus.append(i)
    closed = {i["number"] for i in issues if i["state"] == "closed"}
    order = sorted(legs, key=lambda n: (legs[n].due_on, n))
    return Flight([legs[n] for n in order], bonus, closed, now)


def status(leg: Leg, now: str) -> tuple[str, str]:
    if leg.issues and closed_count(leg.issues) == len(leg.issues):
        return "landed", ORANGE
    if leg.due_on and leg.due_on[:10] < now[:10]:  # late only once the due day is over
        return "late", RED
    return "on course", SLATE


def main() -> None:
    flight = plan(parse(fetch()), datetime.now(UTC).strftime("%Y-%m-%dT%H:%M:%SZ"))
    (DOCS / "flight.svg").write_text(strip(flight))
    (DOCS / "flight-log.md").write_text(log(flight))
    print(f"flight: {flight.done} of {flight.total} closed, headwind {flight.headwind}")


def strip(flight: Flight) -> str:
    w, y, x0, x1 = 900, 112, 70, 830
    done, total = flight.done, flight.total
    px = x0 + (x1 - x0) * flight.progress
    wind = f"+{flight.headwind} since takeoff" if flight.headwind else "no headwind yet"
    out = [
        f'<svg xmlns="{SVG_NS}" viewBox="0 0 {w} 230" width="{w}" height="230" role="img" '
        f'aria-label="Flight progress: {done} of {total} issues closed">',
        "<style>text{font-family:ui-sans-serif,system-ui,-apple-system,'Segoe UI',sans-serif}</style>",
        f'<rect x="1" y="1" width="{w - 2}" height="228" rx="14" fill="{BACKGROUND}" stroke="{DIM}" stroke-width="2"/>',
        f'<text x="28" y="38" fill="{SLATE}" font-size="13" font-weight="600" letter-spacing="1.5">'
        "FLIGHT PROGRESS</text>",
        f'<text x="872" y="38" fill="{TEXT}" font-size="16" font-weight="600" text-anchor="end">'
        f"{done} of {total} issues · {round(100 * flight.progress)}%</text>",
        f'<text x="872" y="58" fill="{SLATE}" font-size="12" text-anchor="end">'
        f"{wind} · stretch {closed_count(flight.bonus)}/{len(flight.bonus)}</text>",
        f'<line x1="{x0}" y1="{y}" x2="{x1}" y2="{y}" stroke="{DIM}" stroke-width="6" stroke-linecap="round"/>',
        f'<line x1="{x0}" y1="{y}" x2="{px:.1f}" y2="{y}" stroke="{ORANGE}" stroke-width="6" stroke-linecap="round"/>',
    ]
    step = (x1 - x0) / max(len(flight.legs) - 1, 1)
    for n, leg in enumerate(flight.legs):
        cx = x0 + n * step
        label, colour = status(leg, flight.now)
        fill = colour if label == "landed" else BACKGROUND
        out.append(f'<circle cx="{cx:.1f}" cy="{y}" r="9" fill="{fill}" stroke="{colour}" stroke-width="3"/>')
        out.append(
            f'<text x="{cx:.1f}" y="{y + 32}" fill="{TEXT}" font-size="13" font-weight="600" '
            f'text-anchor="middle">{escape(leg.title.split(" ·")[0])}</text>'
        )
        out.append(
            f'<text x="{cx:.1f}" y="{y + 50}" fill="{colour}" font-size="12" text-anchor="middle">'
            f"{label} · {closed_count(leg.issues)}/{len(leg.issues)}</text>"
        )
    out.append(f'<g transform="translate({px - 22:.1f} {y - 62}) scale(0.5)">{plane()}</g>')
    out += stamps(flight.closed, w)
    return "\n".join(out) + "\n</svg>\n"


def stamps(closed: set[int], w: int) -> list[str]:
    """A row of pills, filled in once their issue closes, centred under the strip."""
    widths = {n: 6 * len(name) + 22 for n, name in STAMPS.items()}  # roughly 6 px per character at 12 px
    sx = (w - sum(widths.values()) - 8 * (len(STAMPS) - 1)) / 2
    out = []
    for number, name in STAMPS.items():
        won = number in closed
        width = widths[number]
        out.append(
            f'<rect x="{sx}" y="190" width="{width}" height="24" rx="12" '
            f'fill="{ORANGE if won else "none"}" stroke="{ORANGE if won else DIM}" stroke-width="1.5"/>'
        )
        out.append(
            f'<text x="{sx + width / 2}" y="206" fill="{BACKGROUND if won else FAINT}" font-size="12" '
            f'font-weight="600" text-anchor="middle">{"✓ " if won else ""}{escape(name)}</text>'
        )
        sx += width + 8
    return out


def plane() -> str:
    """The Horizon mark, borrowed from the brand assets without its outer <svg> and <title>."""
    ElementTree.register_namespace("", SVG_NS)
    root = ElementTree.parse(DOCS / "brand" / "mark-dark.svg").getroot()
    return "".join(ElementTree.tostring(el, encoding="unicode") for el in root if el.tag != f"{{{SVG_NS}}}title")


def log(flight: Flight) -> str:
    lines = [
        "# Flight log",
        "",
        f"**{flight.done} of {flight.total} issues closed ({round(100 * flight.progress)}%).** "
        + (f"{flight.headwind} joined after takeoff. " if flight.headwind else "")
        + f"Stretch: {closed_count(flight.bonus)} of {len(flight.bonus)}.",
        "",
        "![Flight progress](flight.svg)",
        "",
        f"Rebuilt whenever an issue changes. Last update: {flight.now[:16].replace('T', ' ')} UTC.",
    ]
    for leg in flight.legs:
        label, _ = status(leg, flight.now)
        due = f", due {leg.due_on[:10]}" if leg.due_on else ""
        lines += section(leg.title, label + due, leg.issues)
    if flight.bonus:
        lines += section("Stretch", "bonus", flight.bonus)
    return "\n".join(lines) + "\n"


def section(title: str, note: str, items: list[Issue]) -> list[str]:
    """A heading, then landed issues newest first, then waiting issues in number order."""
    lines = ["", f"## {title}", "", f"*{note}*", ""]
    landed = sorted((i for i in items if i["state"] == "closed"), key=lambda i: i["closed_at"], reverse=True)
    waiting = sorted((i for i in items if i["state"] == "open"), key=lambda i: i["number"])
    lines += [f"- [x] #{i['number']} {escape(i['title'])} (landed {i['closed_at'][:10]})" for i in landed]
    lines += [f"- [ ] #{i['number']} {escape(i['title'])}" for i in waiting]
    return lines


if __name__ == "__main__":
    main()
