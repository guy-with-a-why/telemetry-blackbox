import { writeFile } from "node:fs/promises";
import { log } from "./log";
import { type Issue, countable, plan, totals } from "./plan";
import { render } from "./rack";

/** Writes flight.svg and flight-log.md into a directory and returns the totals. */
export async function build(issues: Issue[], now: string, outDir: URL) {
  const flight = plan(countable(issues), now);
  await writeFile(new URL("flight.svg", outDir), await render(flight));
  await writeFile(new URL("flight-log.md", outDir), log(flight));
  return totals(flight);
}
