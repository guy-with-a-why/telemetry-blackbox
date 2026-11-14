/**
 * Draws the flight-progress strips and the flight log from the repo's issues.
 *
 *     npm run build    # writes docs/flight.svg and docs/flight-log.md
 *
 * Reads GH_TOKEN when it's set, as in CI. Without it the public API still
 * answers, at a lower rate limit. GITHUB_REPOSITORY picks the repo, so a fork
 * draws its own issues.
 */
import { build } from "./build";
import { describeError, fetchIssues } from "./github";

const repository = process.env.GITHUB_REPOSITORY ?? "guy-with-a-why/telemetry-blackbox";
const docs = new URL("../../../docs/", import.meta.url);

try {
  const issues = await fetchIssues(repository, { token: process.env.GH_TOKEN });
  const { done, total, headwind } = await build(issues, new Date().toISOString().slice(0, 19) + "Z", docs);
  console.log(`flight: ${done} of ${total} closed, headwind ${headwind}`);
} catch (error) {
  console.error(`flight: ${describeError(error)}`);
  process.exitCode = 1;
}
