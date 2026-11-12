# Contributing

These are the rules I follow when I work on this repo. It's public while I
build it, so they keep the history clean and the site honest.

## Before I start

- Pick an issue. Every change belongs to one, and the issue says when it's done.
- `mise install` brings the pinned tools, and `just bench` checks the rest.
- `just` lists every recipe.

## While I work

- One issue, one small change. If it grows, I split it.
- Real logic lives in programs and scripts. The justfile only calls them.
- If I change a diagram, I edit the `.d2` file and run `just diagrams`.
- If I learn something worth keeping, it goes in an ADR or a runbook, in my own
  words.

## Before I push

- `just audit` scans for secrets and blocked terms. CI repeats it, but a
  problem caught here never reaches the public history.
- `just docs` builds the site, so I know it still works.
- I read the diff once more before it goes public.

## Branches and pull requests

- `main` is the only long-lived branch. It always builds, releases are cut
  from it and the site deploys from it.
- Every change starts on a branch from `main`, named
  `<type>/<issue>-<slug>`, for example `feat/14-mavlink-framer`.
- Branches live hours, not days. If `main` moves, I rebase onto it.
- Every change reaches `main` through a pull request. Nothing is pushed to it
  directly.
- A pull request merges once the audit, the docs build and the title check
  pass. It's squashed into one commit and the branch is deleted.
- There's no `develop` branch and there are no release branches. A fix goes
  to `main` and ships in the next patch release.
- Release tags (`v*`) are never moved or deleted.

## Commits

- [Conventional Commits](https://www.conventionalcommits.org):
  `type(scope): summary`, for example `feat(gateway): resync after a bad CRC`.
- The summary says what changed. The body, if there is one, says why.
- The pull request title follows the same rule, because it becomes the commit
  on `main`. CI checks it.

## Closing an issue

- I tick every "Done when" box first. If one no longer makes sense, I say why.
- Work I've dropped is closed as not planned, so it leaves the progress count.
- Closing an issue rebuilds the site and moves the flight strip.

## Writing

- First person, British English, short sentences, no Oxford comma.
- Concise. If a reader wouldn't miss a sentence, it goes.
