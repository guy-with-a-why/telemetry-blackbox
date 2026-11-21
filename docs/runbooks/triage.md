# Triage a vulnerability alert

This takes one finding from the alert to closed. Findings arrive in three
places. OSV-Scanner, CodeQL and zizmor raise code scanning alerts. Dependabot
raises its own. The image scans report in each workflow run's summary. I triage
each one within 7 days, and the deadlines run from triage, as
[ADR 7](../adr/0007-osv-scanner-and-a-triage-routine.md) sets out.

The first run was heapless on 20 November 2026. I found nine advisories and
shipped the fix the same morning. Everything runs from the repo, in one
terminal.

## Before I start

- `gh auth status` shows I'm signed in with access to the security alerts.
- `mise install` has run, so `osv-scanner`, `cargo-deny`, `node` and `uv` are
  there. `jq` is installed.
- I'm on `main`, up to date.
- I have the alert's link or number.

## Steps

### 1. Find the alert

```bash
gh api "repos/guy-with-a-why/telemetry-blackbox/code-scanning/alerts?state=open" --jq '.[]|[.number,.tool.name,.rule.id]|@tsv'
gh api "repos/guy-with-a-why/telemetry-blackbox/dependabot/alerts?state=open" --jq '.[]|[.number,.dependency.package.name,.security_advisory.ghsa_id]|@tsv'
```

Image findings are in the summary of the latest `images` run, or the release's
`manifest` job. I open an issue only if the fix spans more than one pull
request or waits on upstream. It goes in the Security milestone with a
`security:` label, and a `cwe:` label if the advisory names one.

### 2. Read the advisory

```bash
curl -fsS https://api.osv.dev/v1/vulns/<ID> | jq '{id, aliases, severity, affected}'
```

I note the aliases, the CWE and the affected functions where RustSec lists
them. If there's no CVSS score, I say so. A fix only counts for this ecosystem
and release. A Debian 14 fix doesn't help a Debian 13 base.

### 3. Ours or a dependency's

A dependency goes through steps 4 and 5. A weakness in my own code goes to
step 6.

### 4. Check whether it's reachable

Reachable means the flawed code is in something I ship, on a path it runs.

```bash
cargo tree -i <crate> --locked -e normal
cargo tree -i <crate> --locked -e normal --manifest-path firmware/Cargo.toml --target thumbv7em-none-eabihf
npm ls <package> --prefix tools/flight --package-lock-only
uv tree --directory tools/bbcheck --locked --invert --package <package>
```

Each runs from the repo root. An empty tree means it isn't there.

For the firmware I check the binary that shipped. Fat LTO inlines most crates,
so `llvm-nm` misses them, but the debug info keeps their names. Zero means none
of the crate shipped.

```bash
gh release download <tag> --pattern 'firmware-*.elf'
gh attestation verify firmware-<tag>.elf --repo guy-with-a-why/telemetry-blackbox
"$(rustc --print sysroot)"/lib/rustlib/x86_64-unknown-linux-gnu/bin/llvm-readobj --string-dump=.debug_str firmware-<tag>.elf | grep -c <crate_name>
```

Severity is the advisory's CVSS score. Where there isn't one, I write my own
estimate in the issue.

### 5. Pick the outcome

| Outcome | What I do |
|---|---|
| Fix | Bump it: `cargo update -p <crate> --precise <version>`, `uv lock --upgrade-package <package>` or an npm `overrides` entry when a parent pins it exactly. A fix to something I ship is `fix(...)`, so it cuts a release. I retitle a Dependabot `chore(deps)` to `fix(deps)` before I squash it. |
| Not affected | An entry in the nearest `osv-scanner.toml`, below. I dismiss a Dependabot alert with the same reason. A CodeQL finding gets a dismissal with a comment, and a zizmor finding a `# zizmor: ignore[<rule>]` comment. |
| Upstream | I search first: `gh search issues --repo <owner>/<name> <ID>`. A public issue only for a public advisory. Anything new goes to the maintainer privately. I carry a workaround that links the issue. |
| Accepted | Recorded like not affected, with the risk as the reason. |

```toml
[[IgnoredVulns]]
id = "<ID>"
ignoreUntil = 2027-05-21 # no more than 6 months out
reason = "Why it doesn't reach anything I ship."
```

Scorecard only reads `ignoreUntil`, so I keep it over `effectiveUntil`.

| Finding | Fixed and released within, from triage |
|---|---|
| High or Critical, and reachable | 7 days |
| High or Critical but not reachable, or Medium | 30 days |
| Low or informational | the next weekly sweep |

### 6. Fix a weakness in my own code

1. I open a draft security advisory and request a CVE on it. If it came in as
   a private report, I accept the report as that draft.
2. I start a temporary private fork from the advisory and fix it there, with a
   regression test that fails before the fix.
3. CI doesn't run in the fork and the ruleset isn't enforced on its merge, so I
   run the checks myself:

   ```bash
   just lint && just test && just vulns
   ```

4. I merge from the advisory with a `fix(...)` title, and release-please cuts
   the release.
5. I publish the advisory, and the CVE goes public with it. The directive comes
   after that.

### 7. Prove it

```bash
just vulns
gh api "repos/guy-with-a-why/telemetry-blackbox/code-scanning/alerts/<n>" --jq .state
gh api "repos/guy-with-a-why/telemetry-blackbox/dependabot/alerts/<n>" --jq .state
```

OSV-Scanner prints `No issues found` and the alert is `fixed` or `dismissed`.
For an image finding, the next release's `manifest` job is green.

### 8. Clean up

I close the issue with the outcome and check every new ignore has a date and
a reason. Then I add the run below.

## What I saw

### heapless, 20 November 2026

Scorecard's Vulnerabilities check dropped to 0. Dependabot had nothing,
because none of the nine has a GitHub alias.

```text
| https://osv.dev/RUSTSEC-2026-0574 | | crates.io | heapless | 0.9.3 | 0.9.4 | firmware/Cargo.lock |
```

`cargo tree -i heapless` showed it came in through embassy-stm32, embassy-sync
and embassy-time-queue-utils. Their requirement already allowed 0.9.4, so I
bumped it in #159. OSV-Scanner then printed `No issues found`, the firmware
booted in Renode and v0.10.1 shipped it.

### fflate, 20 November 2026

Dependabot raised GHSA-px8p-9vwx-vf98 on 14 November, and it sat for six days
with no pull request. satori pins fflate exactly:

```text
└─┬ satori@0.63.2
  └── fflate@0.7.3
```

The flaw is in `unzipSync`, and satori only calls `inflateSync`, so it wasn't
reachable. I fixed it anyway with an `overrides` entry in #160, while
upstream's fix was still open.

### The distroless base, 21 November 2026

```text
| `tb-gateway:auditable` | linux-amd64 | 45 | 16 | 0 | 0 |
```

45 advisories, 16 High or Critical, none with a Debian 13 fix and none in Rust
crates. Reported, not blocked.

## Why one record per advisory

The `osv-scanner.toml` entry lapses, so the decision comes back for a second
look. A dismissed alert never does. Two records would drift apart.

## When it goes wrong

### The Monday scan fails on main with nothing merged

A new advisory, or an ignore that lapsed. I triage it again from step 2.

### The release's `manifest` job fails the image gate

An advisory in a Rust crate. A rerun builds from the release tag, so an ignore
added on `main` won't free it. The way out is a fix and a new release.

### Dependabot can't open a fix

A parent pins the package exactly. I override it and go upstream.

### OSV-Scanner flags what Dependabot doesn't

It's RustSec only. I bump it by hand.

### What I don't do

I don't dismiss without a reason. I don't file a public issue for an upstream
flaw that isn't public, write up a weakness before its fix ships or ignore a
whole ecosystem.
