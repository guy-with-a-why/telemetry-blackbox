/**
 * The flight plan: every milestone with a due date is a leg, flown in due-date
 * order. Progress counts every issue in the legs. Stretch has no due date, so
 * its issues are a bonus. Issues closed as not planned or as duplicates drop
 * out, and issues opened after takeoff (the moment the tracker launched) are
 * headwind: scope that crept in on the way.
 *
 * GitHub timestamps are ISO 8601 in UTC, so they compare correctly as strings.
 */

export const TAKEOFF = "2026-11-12T17:25:24Z"; // the tracker launched with #39; anything newer is headwind

export const STAMPS: Record<number, string> = {
  11: "Built it by hand",
  12: "Survived quorum loss",
  13: "etcd restored",
  23: "First flight",
  27: "Zero frames lost",
  30: "Defended the design",
};

/** The fields used from an issue as the GitHub REST API returns it. */
export interface Issue {
  number: number;
  title: string;
  state: string;
  state_reason?: string | null;
  created_at: string;
  closed_at: string | null;
  milestone: { number: number; title: string; due_on: string | null } | null;
  pull_request?: unknown;
}

export interface Leg {
  title: string;
  dueOn: string;
  issues: Issue[];
}

export interface Flight {
  legs: Leg[];
  bonus: Issue[]; // Stretch and unplanned issues
  closed: Set<number>; // every closed issue number, for the stamps
  now: string;
}

export type Status = "landed" | "late" | "in flight" | "started early" | "not started";

const DROPPED = new Set(["not_planned", "duplicate"]);
const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

export const closedCount = (issues: Issue[]) => issues.filter((i) => i.state === "closed").length;

const isLanded = (leg: Leg) => leg.issues.length > 0 && closedCount(leg.issues) === leg.issues.length;

/** Drops pull requests and work closed as not planned or as a duplicate. */
export const countable = (issues: Issue[]) =>
  issues.filter((i) => i.pull_request === undefined && !DROPPED.has(i.state_reason ?? ""));

export function plan(issues: Issue[], now: string): Flight {
  const legs = new Map<number, Leg>();
  const bonus: Issue[] = [];
  for (const issue of issues) {
    const m = issue.milestone;
    if (m?.due_on) {
      if (!legs.has(m.number)) legs.set(m.number, { title: m.title, dueOn: m.due_on, issues: [] });
      legs.get(m.number)!.issues.push(issue);
    } else {
      bonus.push(issue);
    }
  }
  const order = [...legs.entries()].sort(([an, a], [bn, b]) => a.dueOn.localeCompare(b.dueOn) || an - bn);
  const closed = new Set(issues.filter((i) => i.state === "closed").map((i) => i.number));
  return { legs: order.map(([, leg]) => leg), bonus, closed, now };
}

export function totals(flight: Flight) {
  const tracked = flight.legs.flatMap((leg) => leg.issues);
  const done = closedCount(tracked);
  return {
    done,
    total: tracked.length,
    percent: tracked.length ? Math.floor((100 * done) / tracked.length) : 0, // 100% only once it's all done
    headwind: tracked.filter((i) => i.created_at > TAKEOFF).length,
  };
}

/** The leg being flown: the first one that hasn't landed, or -1 once they all have. */
export const activeLeg = (flight: Flight) => flight.legs.findIndex((leg) => !isLanded(leg));

export function status(flight: Flight, index: number): Status {
  const leg = flight.legs[index];
  if (isLanded(leg)) return "landed";
  if (day(leg.dueOn) < day(flight.now)) return "late"; // late only once the due day is over
  if (index === activeLeg(flight)) return "in flight";
  return closedCount(leg.issues) > 0 ? "started early" : "not started";
}

/**
 * How far through a leg the plan says I should be today, from 0 to 1. A leg
 * runs from the previous leg's due date (or takeoff) to its own. Null when the
 * leg has landed or its window hasn't opened.
 */
export function planned(flight: Flight, index: number): number | null {
  const leg = flight.legs[index];
  const start = day(index === 0 ? TAKEOFF : flight.legs[index - 1].dueOn);
  const end = day(leg.dueOn);
  const today = day(flight.now);
  if (isLanded(leg) || today < start) return null;
  return end > start ? Math.min(1, (today - start) / (end - start)) : 1;
}

/** Days since the epoch from the date alone, so a leg due on 20 Nov is on time all of 20 Nov. */
const day = (timestamp: string) => Date.parse(timestamp.slice(0, 10)) / 864e5;

/** "Leg 1 · A cluster I built myself" becomes "A cluster I built myself". */
export const legName = (title: string) => title.split(" · ").slice(1).join(" · ") || title;

/** The number in "Leg 1 · …", or the leg's place in the route if the title has none. */
export const legNumber = (title: string, index: number) => Number(/^Leg (\d+)/.exec(title)?.[1] ?? index);

/** "20 Nov", the same on every machine whatever its time zone or locale data. */
export function shortDate(timestamp: string) {
  const date = new Date(timestamp);
  return `${date.getUTCDate()} ${MONTHS[date.getUTCMonth()]}`;
}

export const plural = (count: number, noun: string) => `${count} ${noun}${count === 1 ? "" : "s"}`;
