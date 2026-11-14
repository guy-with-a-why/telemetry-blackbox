import { mkdtemp, readdir, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { pathToFileURL } from "node:url";
import { describe, expect, it, test, vi } from "vitest";
import { build } from "../src/build";
import { log, markdown } from "../src/log";
import { plan } from "../src/plan";
import { render, summary } from "../src/rack";
import { LEG_0, LEG_1, NOW, STRETCH, issue, leg, legs } from "./fixtures";

const height = (svg: string) => Number(/height="(\d+)"/.exec(svg)?.[1]);
const width = (svg: string) => Number(/width="(\d+)"/.exec(svg)?.[1]);
const inWords = (svg: string) => /<title>.*<\/desc>/.exec(svg)?.[0];

describe("render", () => {
  it("uses only Tailwind classes Satori understands, since it drops the rest with a warning", async () => {
    const warn = vi.spyOn(console, "warn").mockImplementation(() => {});
    const late = plan(
      [...leg(LEG_0, 1, "closed", "open"), ...leg(LEG_1, 10, "closed", "open")],
      "2026-11-14T09:00:00Z",
    );
    const landed = plan([...leg(LEG_0, 1, "closed"), issue(12, "closed")], NOW);
    for (const narrow of [false, true]) {
      await render(late, { narrow });
      await render(landed, { narrow });
    }
    expect(warn).not.toHaveBeenCalled();
    warn.mockRestore();
  });

  it("draws an empty flight", async () => {
    expect(await render(plan([], NOW))).toContain('aria-label="Flight progress: 0 of 0 issues closed (0%)"');
  });

  it("carries the Horizon mark and a description of every leg", async () => {
    const svg = await render(
      plan([...leg(LEG_0, 1, "closed"), ...leg(LEG_1, 10, "closed", "open")], "2026-11-14T20:00:00Z"),
    );
    expect(svg).toContain("data:image/svg+xml;base64,");
    expect(svg).toContain(
      "<desc>TBX0 The bench: landed, 1 of 1 closed, due 12 Nov. " +
        "TBX1 A cluster I built myself: in flight, 1 of 2 closed, due 20 Nov, the plan says 25% by today.",
    );
  });

  it("grows a strip at a time, so nothing is clipped however many legs there are", async () => {
    const [five, ten] = await Promise.all([render(plan(legs(5), NOW)), render(plan(legs(10), NOW))]);
    expect(height(ten) - height(five)).toBe(5 * (34 + 6));
  });

  it("draws legs with no bonus and a leg with many issues", async () => {
    const many = Array.from({ length: 40 }, (_, n) => issue(n, "open", LEG_1));
    await expect(render(plan(many, NOW))).resolves.toContain("<desc>TBX1 A cluster I built myself: in flight, 0 of 40");
  });

  it("escapes the title and description as XML", async () => {
    const odd = { ...LEG_1, title: 'Leg 1 · Wires & "plugs" <here>' };
    const svg = await render(plan([issue(1, "open", odd)], NOW));
    expect(svg).toContain("TBX1 Wires &amp; &quot;plugs&quot; &lt;here&gt;: in flight");
  });

  it("says when every leg has landed, with no plan left to follow", () => {
    const { desc } = summary(plan([...leg(LEG_0, 1, "closed"), ...leg(LEG_1, 10, "closed")], NOW));
    expect(desc).not.toContain("plan says");
    expect(desc).toContain("TBX1 A cluster I built myself: landed");
  });
});

describe("render narrow", () => {
  const flight = plan(
    [...leg(LEG_0, 1, "closed"), ...leg(LEG_1, 10, "closed", "open"), ...leg(STRETCH, 20, "open")],
    NOW,
  );

  it("draws a 420px card for phones and keeps the wide one at 900px", async () => {
    const [wide, narrow] = await Promise.all([render(flight), render(flight, { narrow: true })]);
    expect(width(wide)).toBe(900);
    expect(width(narrow)).toBe(420);
  });

  it("says the same in words as the wide card, ETAs included", async () => {
    const [wide, narrow] = await Promise.all([render(flight), render(flight, { narrow: true })]);
    expect(inWords(narrow)).toBe(inWords(wide));
    expect(narrow).toContain("due 20 Nov");
  });

  it("stacks each strip on two rows, so it is taller than the wide strip", async () => {
    const [five, ten, wide] = await Promise.all([
      render(plan(legs(5), NOW), { narrow: true }),
      render(plan(legs(10), NOW), { narrow: true }),
      render(plan(legs(5), NOW)),
    ]);
    expect(height(ten) - height(five)).toBe(5 * (56 + 6));
    expect(height(five)).toBeGreaterThan(height(wide));
  });

  it("draws a leg with many issues", async () => {
    const many = Array.from({ length: 40 }, (_, n) => issue(n, "open", LEG_1));
    await expect(render(plan(many, NOW), { narrow: true })).resolves.toContain(
      "<desc>TBX1 A cluster I built myself: in flight, 0 of 40",
    );
  });
});

describe("build", () => {
  it("writes the wide card, the narrow card and the log", async () => {
    const dir = await mkdtemp(join(tmpdir(), "flight-"));
    try {
      await build([issue(1, "open", LEG_1)], NOW, pathToFileURL(dir + "/"));
      expect((await readdir(dir)).sort()).toEqual(["flight-log.md", "flight-narrow.svg", "flight.svg"]);
    } finally {
      await rm(dir, { recursive: true });
    }
  });
});

describe("log", () => {
  it("serves the narrow card to phones and the wide one to everything else", () => {
    const page = log(plan([issue(1, "open", LEG_1)], NOW));
    expect(page).toContain('<source media="(max-width: 600px)" srcset="flight-narrow.svg">');
    expect(page).toContain('<img src="flight.svg" alt="Flight progress strips');
  });

  it("lists landed issues newest first, then the waiting ones, then the bonus", () => {
    const issues = [
      issue(1, "closed", LEG_0, { closed_at: "2026-11-12T11:00:00Z" }),
      issue(2, "closed", LEG_0, { closed_at: "2026-11-12T15:00:00Z" }),
      issue(3, "open", LEG_0),
      issue(4, "open", STRETCH),
    ];
    const lines = log(plan(issues, NOW)).split("\n");
    expect(lines.filter((l) => l.startsWith("- [")).map((l) => l.slice(0, 9))).toEqual([
      "- [x] #2 ",
      "- [x] #1 ",
      "- [ ] #3 ",
      "- [ ] #4 ",
    ]);
    expect(lines).toContain("*late, due 2026-11-12*");
    expect(lines).toContain("*bonus*");
  });

  it("reports the totals and headwind", () => {
    const issues = [issue(1, "closed", LEG_1), issue(2, "open", LEG_1, { created_at: "2026-11-13T08:00:00Z" })];
    expect(log(plan(issues, NOW))).toContain(
      "**1 of 2 issues closed (50%).** 1 joined after takeoff. Stretch: 0 of 0.",
    );
    expect(log(plan([], NOW))).toContain("**0 of 0 issues closed (0%).** Stretch: 0 of 0.");
  });

  it("leaves out the Stretch section when there's no bonus", () => {
    expect(log(plan([issue(1, "open", LEG_1)], NOW))).not.toContain("## Stretch");
  });

  it("copes with a closed issue that has no close date", () => {
    const lines = log(plan([issue(1, "closed", LEG_1, { closed_at: null })], NOW)).split("\n");
    expect(lines).toContain("- [x] #1 Issue 1");
  });

  test.each([
    ["[click](https://example.com)", "\\[click\\]\\(https\\:\\/\\/example\\.com\\)"],
    ["![pixel](https://example.com/p.gif)", "\\!\\[pixel\\]\\(https\\:\\/\\/example\\.com\\/p\\.gif\\)"],
    ["*stars* and `code`", "\\*stars\\* and \\`code\\`"],
    ["<script>", "\\<script\\>"],
    ["Plain words · and a middle dot", "Plain words · and a middle dot"],
  ])("shows %s literally", (title, escaped) => {
    expect(markdown(title)).toBe(escaped);
  });
});
