# Day 0: Laying out the bench

## What was done

No firmware today, and that was the plan. By the evening the repo was public and every push was checked for secrets and blocked terms. The docs site rebuilds whenever an issue changes, and a flight strip on it shows how far through the plan I am. The Rust workspace, bbcheck and CI were scaffolded by half nine, so Day 1 starts on firmware straight away.

## Why was it done that way

The repo went public before any code, so the checks had to come first. gitleaks scans the whole history. A blocked-terms check covers files, commit messages and issue text, and GitHub's push protection sits behind both. That's cheap on day one and expensive to retrofit.

The diagrams are D2 because they stay as text I can diff and they render in light and dark themes. Tasks go through `just`, since they're commands with arguments rather than builds.

Half an hour after takeoff I moved takeoff, so the issues I'd added that afternoon now count against me on the flight strip. Technically it is scope creep.

## What challenges were faced

Two small things. Five minutes after the site went live, the dark logo turned out to be unreadable on the light theme, so that was the first fix.

The more interesting one was in the flight log. `flight.py` stitched `gh`'s pages of issues together by swapping `][` for `],[`, which would also have mangled any issue title containing `][`. Editing JSON as text is a shortcut I know better than to take. `gh api --slurp` already returns a single array, so the stitching went and a test with the title `[a][b]` keeps it that way ([#43](https://github.com/guy-with-a-why/telemetry-blackbox/pull/43)). Nobody hit it.

## What's next

Tomorrow is firmware. The riskiest part is getting Embassy and Renode to agree on the board, so that goes first. Every day of the plan has a fallback if it runs long.
