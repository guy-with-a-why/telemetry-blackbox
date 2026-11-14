import type { Issue } from "../src/plan";

export const NOW = "2026-11-13T09:00:00Z";
export const LEG_0 = { number: 1, title: "Leg 0 · The bench", due_on: "2026-11-12T00:00:00Z" };
export const LEG_1 = { number: 3, title: "Leg 1 · A cluster I built myself", due_on: "2026-11-20T00:00:00Z" };
export const LEG_2 = { number: 2, title: "Leg 2 · Firmware and the wire", due_on: "2026-11-24T00:00:00Z" };
export const STRETCH = { number: 6, title: "Stretch", due_on: null };

export function issue(
  number: number,
  state = "open",
  milestone: Issue["milestone"] = null,
  extra: Partial<Issue> = {},
): Issue {
  return {
    number,
    title: `Issue ${number}`,
    state,
    milestone,
    created_at: "2026-11-12T10:00:00Z",
    closed_at: state === "closed" ? "2026-11-12T12:00:00Z" : null,
    ...extra,
  };
}

/** A leg with the given issue states, numbered from `from`. */
export const leg = (milestone: NonNullable<Issue["milestone"]>, from: number, ...states: string[]) =>
  states.map((state, n) => issue(from + n, state, milestone));

/** `count` legs a day apart from 13 Nov, each with three open issues. */
export function legs(count: number) {
  return Array.from({ length: count }, (_, n) => {
    const due = new Date(Date.UTC(2026, 10, 13 + n)).toISOString();
    const milestone = { number: 100 + n, title: `Leg ${n} · Leg number ${n}`, due_on: due };
    return leg(milestone, 10 * n, "open", "open", "open");
  }).flat();
}
