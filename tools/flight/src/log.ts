import { type Flight, type Issue, closedCount, plural, status, totals } from "./plan";

/** The flight log page: the totals, the strips, then every leg's issues as text. */
export function log(flight: Flight): string {
  const { done, total, percent, headwind } = totals(flight);
  const lines = [
    "# Flight log",
    "",
    `**${done} of ${plural(total, "issue")} closed (${percent}%).** ` +
      (headwind ? `${headwind} joined after takeoff. ` : "") +
      `Stretch: ${closedCount(flight.bonus)} of ${flight.bonus.length}.`,
    "",
    // phones get the narrow card, which keeps the text readable at full size
    "<picture>",
    '  <source media="(max-width: 600px)" srcset="flight-narrow.svg">',
    '  <img src="flight.svg" alt="Flight progress strips, one per leg. The lists below give the same detail as text.">',
    "</picture>",
    "",
    `Rebuilt whenever an issue changes. Last update: ${flight.now.slice(0, 16).replace("T", " ")} UTC.`,
  ];
  flight.legs.forEach((leg, i) => {
    lines.push(...section(leg.title, `${status(flight, i)}, due ${leg.dueOn.slice(0, 10)}`, leg.issues));
  });
  if (flight.bonus.length) lines.push(...section("Stretch", "bonus", flight.bonus));
  lines.push(
    "",
    "## How this page is drawn",
    "",
    "![CI runs just docs on a push to main, when an issue changes and daily at 06:00. " +
      "tools/flight fetches the issues, groups them into legs and draws a wide and a narrow card. " +
      "mdbook builds the site and Pages serves the cards to the README and this page.](diagrams/flight-tracker.svg)",
    "",
    "The diagram is wide, so here it is [full size](diagrams/flight-tracker.svg).",
  );
  return lines.join("\n") + "\n";
}

/** A heading, then landed issues newest first, then waiting issues in number order. */
function section(title: string, note: string, issues: Issue[]): string[] {
  const landed = issues
    .filter((i) => i.state === "closed")
    .sort((a, b) => (b.closed_at ?? "").localeCompare(a.closed_at ?? ""));
  const waiting = issues.filter((i) => i.state === "open").sort((a, b) => a.number - b.number);
  return [
    "",
    `## ${markdown(title)}`,
    "",
    `*${note}*`,
    "",
    ...landed.map(
      (i) => `- [x] #${i.number} ${markdown(i.title)}` + (i.closed_at ? ` (landed ${i.closed_at.slice(0, 10)})` : ""),
    ),
    ...waiting.map((i) => `- [ ] #${i.number} ${markdown(i.title)}`),
  ];
}

/**
 * Shows text literally: anyone can open an issue on a public repo, so a title
 * must never become a link, an image or HTML. CommonMark lets a backslash
 * escape any ASCII punctuation.
 */
export const markdown = (text: string) => text.replace(/[!-/:-@[-`{-~]/g, "\\$&");
