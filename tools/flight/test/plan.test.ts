import { describe, expect, it, test } from "vitest";
import {
  activeLeg,
  countable,
  legName,
  legNumber,
  plan,
  planned,
  plural,
  shortDate,
  status,
  totals,
} from "../src/plan";
import { LEG_0, LEG_1, LEG_2, NOW, STRETCH, issue, leg } from "./fixtures";

describe("countable", () => {
  test.each([
    ["an open issue", issue(1), true],
    ["a closed issue with no reason", issue(1, "closed", null, { state_reason: null }), true],
    ["a completed issue", issue(1, "closed", null, { state_reason: "completed" }), true],
    ["a pull request", issue(1, "open", null, { pull_request: {} }), false],
    ["work closed as not planned", issue(1, "closed", null, { state_reason: "not_planned" }), false],
    ["a duplicate", issue(1, "closed", null, { state_reason: "duplicate" }), false],
  ])("%s counts: %s", (_, item, kept) => {
    expect(countable([item])).toHaveLength(kept ? 1 : 0);
  });
});

describe("plan", () => {
  it("flies legs in due-date order and sets aside the bonus", () => {
    const issues = [
      issue(1, "open", LEG_2),
      issue(2, "open", LEG_0),
      issue(3, "open", STRETCH),
      issue(4),
      issue(5, "open", LEG_1),
    ];
    const flight = plan(issues, NOW);
    expect(flight.legs.map((l) => l.title)).toEqual([LEG_0.title, LEG_1.title, LEG_2.title]);
    expect(flight.bonus.map((i) => i.number)).toEqual([3, 4]);
  });

  it("breaks a tie on due date by milestone number", () => {
    const sameDay = { ...LEG_2, due_on: LEG_1.due_on };
    expect(plan([issue(1, "open", LEG_1), issue(2, "open", sameDay)], NOW).legs.map((l) => l.title)).toEqual([
      LEG_2.title,
      LEG_1.title,
    ]);
  });

  it("counts issues opened after takeoff as headwind", () => {
    const issues = [issue(1, "open", LEG_0), issue(2, "open", LEG_0, { created_at: "2026-11-12T18:00:00Z" })];
    expect(totals(plan(issues, NOW)).headwind).toBe(1);
  });

  test.each([
    [0, 0, 0],
    [1, 3, 33],
    [199, 200, 99],
    [200, 200, 100],
  ])("%i of %i closed reads %i%%", (done, total, percent) => {
    const issues = Array.from({ length: total }, (_, n) => issue(n, n < done ? "closed" : "open", LEG_1));
    expect(totals(plan(issues, NOW)).percent).toBe(percent);
  });
});

describe("status", () => {
  it("lands a leg once every issue closes", () => {
    expect(status(plan(leg(LEG_0, 1, "closed", "closed"), NOW), 0)).toBe("landed");
  });

  it("is late once the due day is over, but not on the day", () => {
    expect(status(plan(leg(LEG_0, 1, "closed", "open"), NOW), 0)).toBe("late");
    expect(status(plan(leg(LEG_0, 1, "open"), "2026-11-12T23:59:00Z"), 0)).toBe("in flight");
  });

  it("flies the first leg that hasn't landed and marks early work on later ones", () => {
    const f = plan(
      [...leg(LEG_0, 1, "closed"), ...leg(LEG_1, 10, "closed", "open"), ...leg(LEG_2, 20, "closed", "open")],
      NOW,
    );
    expect([0, 1, 2].map((i) => status(f, i))).toEqual(["landed", "in flight", "started early"]);
    expect(status(plan([...leg(LEG_1, 1, "open"), ...leg(LEG_2, 10, "open")], NOW), 1)).toBe("not started");
  });

  it("marks every overdue leg late, active or not", () => {
    const f = plan([...leg(LEG_1, 1, "open"), ...leg(LEG_2, 10, "open")], "2026-11-25T09:00:00Z");
    expect([status(f, 0), status(f, 1)]).toEqual(["late", "late"]);
  });

  it("has no active leg once every leg has landed", () => {
    const f = plan([...leg(LEG_0, 1, "closed"), ...leg(LEG_1, 10, "closed")], NOW);
    expect(activeLeg(f)).toBe(-1);
  });

  it("drops a leg whose only issues were dropped, rather than flying it empty", () => {
    const f = plan(
      countable([issue(1, "closed", LEG_0, { state_reason: "not_planned" }), issue(2, "open", LEG_1)]),
      NOW,
    );
    expect(f.legs.map((l) => l.title)).toEqual([LEG_1.title]);
  });
});

describe("planned", () => {
  const f = (now: string) =>
    plan([...leg(LEG_0, 1, "closed"), ...leg(LEG_1, 10, "open"), ...leg(LEG_2, 20, "open")], now);

  test.each([
    ["on the leg's first day", "2026-11-12T20:00:00Z", 0],
    ["a quarter of the way through 12 to 20 Nov", "2026-11-14T20:00:00Z", 0.25],
    ["on the due date", "2026-11-20T09:00:00Z", 1],
    ["past the due date", "2026-11-23T09:00:00Z", 1],
  ])("puts Leg 1 %s at %d", (_, now, expected) => {
    expect(planned(f(now), 1)).toBe(expected);
  });

  it("has nothing to say about a landed leg or one whose window hasn't opened", () => {
    expect(planned(f("2026-11-14T20:00:00Z"), 0)).toBeNull();
    expect(planned(f("2026-11-14T20:00:00Z"), 2)).toBeNull();
  });

  it("measures the first leg from takeoff, and not before it", () => {
    const first = plan(leg(LEG_1, 1, "open"), "2026-11-16T09:00:00Z");
    expect(planned(first, 0)).toBe(0.5);
    expect(planned(plan(leg(LEG_1, 1, "open"), "2026-11-11T09:00:00Z"), 0)).toBeNull();
  });

  it("is done by the day when two legs are due the same day", () => {
    const sameDay = { ...LEG_2, due_on: LEG_1.due_on };
    expect(planned(plan([...leg(LEG_1, 1, "open"), ...leg(sameDay, 10, "open")], "2026-11-20T09:00:00Z"), 1)).toBe(1);
  });
});

describe("words", () => {
  it("names and numbers a leg from its milestone title", () => {
    expect(legName(LEG_1.title)).toBe("A cluster I built myself");
    expect(legName("Stretch")).toBe("Stretch");
    expect(legNumber(LEG_2.title, 0)).toBe(2);
    expect(legNumber("Shakedown", 4)).toBe(4);
  });

  test.each([
    ["2026-11-20T00:00:00Z", "20 Nov"],
    ["2026-09-04T00:00:00Z", "4 Sep"],
    ["2026-12-31T23:30:00Z", "31 Dec"],
  ])("writes %s as %s", (timestamp, expected) => {
    expect(shortDate(timestamp)).toBe(expected);
  });

  it("uses the singular for one", () => {
    expect([plural(0, "issue"), plural(1, "issue"), plural(2, "issue")]).toEqual(["0 issues", "1 issue", "2 issues"]);
  });
});
