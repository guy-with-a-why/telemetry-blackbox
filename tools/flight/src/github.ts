import { Octokit } from "@octokit/rest";
import type { Issue } from "./plan";

/** Every issue and pull request in "owner/repo", across all pages. */
export async function fetchIssues(repository: string, options: { token?: string; fetch?: typeof fetch } = {}) {
  const [owner, repo] = repository.split("/");
  if (!owner || !repo) throw new Error(`expected owner/repo, got "${repository}"`);
  const octokit = new Octokit({ auth: options.token, request: options.fetch ? { fetch: options.fetch } : {} });
  const issues = await octokit.paginate(octokit.rest.issues.listForRepo, { owner, repo, state: "all", per_page: 100 });
  return issues as Issue[];
}

/** One line for the build log: GitHub's status and message, or the error's own message. */
export function describeError(error: unknown): string {
  if (error instanceof Error && "status" in error) {
    const message = error.message.split(" - ")[0]; // Octokit appends the docs URL after " - "
    return `GitHub answered ${error.status}: ${message}`;
  }
  return error instanceof Error ? error.message : String(error);
}
