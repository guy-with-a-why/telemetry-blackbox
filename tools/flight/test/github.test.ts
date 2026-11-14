import { mkdtemp, readFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { pathToFileURL } from "node:url";
import { describe, expect, it } from "vitest";
import { build } from "../src/build";
import { describeError, fetchIssues } from "../src/github";
import { LEG_1, NOW, issue } from "./fixtures";

const API = "https://api.github.com/repos/guy-with-a-why/telemetry-blackbox/issues";

/** A fetch that answers each URL with a canned response. */
function fakeFetch(pages: Record<string, () => Response>): typeof fetch {
  return async (input) => {
    const url = String(input instanceof Request ? input.url : input);
    const page = Object.entries(pages).find(([prefix]) => url.startsWith(prefix));
    if (!page) throw new Error(`unexpected request to ${url}`);
    return page[1]();
  };
}
const json = (body: unknown, init: ResponseInit = {}) =>
  new Response(JSON.stringify(body), { ...init, headers: { "content-type": "application/json", ...init.headers } });

describe("fetchIssues", () => {
  it("follows the next link across pages", async () => {
    const fetch = fakeFetch({
      [`${API}?page=2`]: () => json([issue(2, "open", null, { pull_request: {} })]),
      [API]: () => json([issue(1)], { headers: { link: `<${API}?page=2>; rel="next"` } }),
    });
    const issues = await fetchIssues("guy-with-a-why/telemetry-blackbox", { fetch });
    expect(issues.map((i) => i.number)).toEqual([1, 2]);
  });

  it("refuses a repository that isn't owner/repo", async () => {
    await expect(fetchIssues("telemetry-blackbox")).rejects.toThrow('expected owner/repo, got "telemetry-blackbox"');
  });
});

describe("describeError", () => {
  it.each([
    [401, "Bad credentials"],
    [403, "API rate limit exceeded"],
  ])("turns a %i into one line", async (status, message) => {
    const fetch = fakeFetch({
      [API]: () => json({ message, documentation_url: "https://docs.github.com" }, { status }),
    });
    const error = await fetchIssues("guy-with-a-why/telemetry-blackbox", { fetch }).catch((e: unknown) => e);
    expect(describeError(error)).toBe(`GitHub answered ${status}: ${message}`);
  });

  it("passes other errors through", () => {
    expect(describeError(new Error("disk full"))).toBe("disk full");
    expect(describeError("odd")).toBe("odd");
  });
});

describe("build", () => {
  it("writes the strips and the log, leaving out pull requests", async () => {
    const dir = pathToFileURL(join(await mkdtemp(join(tmpdir(), "flight-")), "/"));
    const totals = await build(
      [issue(1, "closed", LEG_1), issue(2, "open", LEG_1), issue(3, "open", LEG_1, { pull_request: {} })],
      NOW,
      dir,
    );
    expect(totals).toMatchObject({ done: 1, total: 2 });
    expect(await readFile(new URL("flight.svg", dir), "utf8")).toContain("<svg");
    expect(await readFile(new URL("flight-log.md", dir), "utf8")).not.toContain("#3");
  });
});
