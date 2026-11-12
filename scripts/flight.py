"""Draws the flight-progress strip and the flight log from the repo's issues.

    python3 scripts/flight.py      # writes docs/flight.svg and docs/flight-log.md

Progress counts every issue in the Day milestones. Stretch issues are a bonus,
issues closed as not planned drop out, and issues opened after takeoff are
headwind: scope that crept in on the way.
"""

import json
import subprocess
from datetime import UTC, datetime
from html import escape
from pathlib import Path

TAKEOFF = "2026-11-13T00:00:00Z"
STAMPS = {
    11: "Built it by hand",
    12: "Survived quorum loss",
    13: "etcd restored",
    23: "First flight",
    27: "Zero frames lost",
    30: "Defended the design",
}
DOCS = Path(__file__).resolve().parent.parent / "docs"
ORANGE, SLATE, DIM, RED, GREEN = "#f2662b", "#8b97a6", "#30363d", "#f07167", "#4cb37a"


def issues():
    out = subprocess.run(
        ["gh", "api", "--paginate", "repos/{owner}/{repo}/issues?state=all&per_page=100"],
        check=True, capture_output=True, text=True,
    ).stdout
    # --paginate concatenates one JSON array per page.
    pages = json.loads("[" + out.replace("][", "],[") + "]")
    return [i for page in pages for i in page
            if "pull_request" not in i and i.get("state_reason") != "not_planned"]


def status(milestone, items, now):
    done = sum(i["state"] == "closed" for i in items)
    if items and done == len(items):
        return "landed", ORANGE
    due = milestone.get("due_on")
    if due and due[:10] < now[:10]:  # late only once the due day is over
        return "late", RED
    return "on course", SLATE


def main():
    now = datetime.now(UTC).strftime("%Y-%m-%dT%H:%M:%SZ")
    every = issues()
    days, bonus = {}, []
    for i in every:
        m = i.get("milestone")
        if m and m["title"].startswith("Day"):
            days.setdefault(m["number"], (m, []))[1].append(i)
        else:
            bonus.append(i)
    legs = [days[n] for n in sorted(days)]
    tracked = [i for _, items in legs for i in items]
    done = sum(i["state"] == "closed" for i in tracked)
    total = len(tracked) or 1
    headwind = sum(i["created_at"] > TAKEOFF for i in tracked)
    closed = {i["number"] for i in every if i["state"] == "closed"}
    (DOCS / "flight.svg").write_text(strip(legs, done, total, headwind, bonus, closed, now))
    (DOCS / "flight-log.md").write_text(log(legs, done, total, headwind, bonus, now))
    print(f"flight: {done} of {total} closed, headwind {headwind}")


def strip(legs, done, total, headwind, bonus, closed, now):
    w, y, x0, x1 = 900, 112, 70, 830
    px = x0 + (x1 - x0) * done / total
    wind = f"+{headwind} since takeoff" if headwind else "no headwind yet"
    extra = sum(i["state"] == "closed" for i in bonus)
    out = [
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} 230" width="{w}" height="230" role="img" '
        f'aria-label="Flight progress: {done} of {total} issues closed">',
        "<style>text{font-family:ui-sans-serif,system-ui,-apple-system,'Segoe UI',sans-serif}</style>",
        f'<rect x="1" y="1" width="{w - 2}" height="228" rx="14" fill="#0d1117" stroke="{DIM}" stroke-width="2"/>',
        f'<text x="28" y="38" fill="{SLATE}" font-size="13" font-weight="600" letter-spacing="1.5">FLIGHT PROGRESS</text>',
        f'<text x="872" y="38" fill="#eaecef" font-size="16" font-weight="600" text-anchor="end">'
        f'{done} of {total} issues · {round(100 * done / total)}%</text>',
        f'<text x="872" y="58" fill="{SLATE}" font-size="12" text-anchor="end">'
        f'{wind} · stretch {extra}/{len(bonus)}</text>',
        f'<line x1="{x0}" y1="{y}" x2="{x1}" y2="{y}" stroke="{DIM}" stroke-width="6" stroke-linecap="round"/>',
        f'<line x1="{x0}" y1="{y}" x2="{px:.1f}" y2="{y}" stroke="{ORANGE}" stroke-width="6" stroke-linecap="round"/>',
    ]
    step = (x1 - x0) / max(len(legs) - 1, 1)
    for n, (m, items) in enumerate(legs):
        cx = x0 + n * step
        label, colour = status(m, items, now)
        fill = colour if label == "landed" else "#0d1117"
        out.append(f'<circle cx="{cx:.1f}" cy="{y}" r="9" fill="{fill}" stroke="{colour}" stroke-width="3"/>')
        out.append(f'<text x="{cx:.1f}" y="{y + 32}" fill="#eaecef" font-size="13" font-weight="600" '
                   f'text-anchor="middle">{escape(m["title"].split(" ·")[0])}</text>')
        got = sum(i["state"] == "closed" for i in items)
        out.append(f'<text x="{cx:.1f}" y="{y + 50}" fill="{colour}" font-size="12" text-anchor="middle">'
                   f'{label} · {got}/{len(items)}</text>')
    out.append(f'<g transform="translate({px - 22:.1f} {y - 62}) scale(0.5)">{plane()}</g>')
    widths = {n: 6 * len(name) + 22 for n, name in STAMPS.items()}
    sx = (w - sum(widths.values()) - 8 * (len(STAMPS) - 1)) / 2
    for number, name in STAMPS.items():
        won = number in closed
        width = widths[number]
        out.append(f'<rect x="{sx}" y="190" width="{width}" height="24" rx="12" '
                   f'fill="{ORANGE if won else "none"}" stroke="{ORANGE if won else DIM}" stroke-width="1.5"/>')
        out.append(f'<text x="{sx + width / 2}" y="206" fill="{"#0d1117" if won else "#6b7785"}" font-size="12" '
                   f'font-weight="600" text-anchor="middle">{"✓ " if won else ""}{escape(name)}</text>')
        sx += width + 8
    return "\n".join(out) + "\n</svg>\n"


def plane():
    """The Horizon mark, borrowed from the brand assets."""
    mark = (DOCS / "brand" / "mark-dark.svg").read_text()
    return mark.split("</title>\n", 1)[1].rsplit("</svg>", 1)[0]


def log(legs, done, total, headwind, bonus, now):
    lines = [
        "# Flight log",
        "",
        f"**{done} of {total} issues closed ({round(100 * done / total)}%).** "
        + (f"{headwind} joined after takeoff. " if headwind else "")
        + f"Stretch: {sum(i['state'] == 'closed' for i in bonus)} of {len(bonus)}.",
        "",
        "![Flight progress](flight.svg)",
        "",
        f"Rebuilt whenever an issue changes. Last update: {now[:16].replace('T', ' ')} UTC.",
    ]
    for m, items in legs + ([({"title": "Stretch", "due_on": None}, bonus)] if bonus else []):
        label, _ = status(m, items, now) if m["title"] != "Stretch" else ("bonus", None)
        due = f", due {m['due_on'][:10]}" if m.get("due_on") else ""
        lines += ["", f"## {m['title']}", "", f"*{label}{due}*", ""]
        landed = sorted((i for i in items if i["state"] == "closed"), key=lambda i: i["closed_at"], reverse=True)
        waiting = sorted((i for i in items if i["state"] == "open"), key=lambda i: i["number"])
        for i in landed:
            lines.append(f"- [x] #{i['number']} {escape(i['title'])} (landed {i['closed_at'][:10]})")
        for i in waiting:
            lines.append(f"- [ ] #{i['number']} {escape(i['title'])}")
    return "\n".join(lines) + "\n"


if __name__ == "__main__":
    main()
