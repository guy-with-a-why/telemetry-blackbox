# 0007. OSV-Scanner and a fixed triage routine over Dependabot alone

- **Status:** Proposed
- **Date:** 2026-11-20
- **Issue:** #155

## Context

Dependabot was the only thing watching my dependencies, and it reads one
source: GitHub's advisory database. Two findings slipped past it in the same
week.

1. On 18 November RustSec published nine advisories against heapless 0.9.3,
   [RUSTSEC-2026-0574](https://rustsec.org/advisories/RUSTSEC-2026-0574.html)
   to 0582. They include a use after free and two races, and heapless reaches
   the firmware through embassy. They have no GitHub alias, so Dependabot never
   raised them. cargo-deny marks them unsound, and by default it reports unsound
   advisories only for direct dependencies. Only Scorecard's Vulnerabilities
   check saw them, as a single alert.
2. On 14 November Dependabot raised
   [GHSA-px8p-9vwx-vf98](https://github.com/advisories/GHSA-px8p-9vwx-vf98)
   against fflate 0.7.3 in the flight tool. satori pins fflate exactly, so
   Dependabot couldn't open a fix, and the alert sat for six days.

Both are fixed, in #159 and #160. The gaps that let them through are still
there. Nothing scans the gateway and pipeline images or the third-party images
I deploy. CodeQL doesn't read the flight tool's TypeScript. And I have no
written routine: no deadline, no record of why a finding doesn't apply and no
order for disclosing a weakness in my own code.

The constraints:

- I maintain this alone, in the evenings. Every finding needs a decision, so
  the scanners must not bury me in noise I can't act on.
- The repo is public. A weakness in my own code must stay private until its fix
  ships.
- Every action is pinned by commit SHA. A scanner runs with access to the repo,
  and trivy-action's tags were hijacked in March 2026.
- Scorecard reads `osv-scanner.toml`, and the OSV-Scanner inside it only
  understands `ignoreUntil`.
- release-please cuts no release for `chore`, so a security bump committed as
  `chore` never ships.
- The distroless base image carries 16 High or Critical advisories as I write
  this, and Debian 13 has a fix for none of them. None of them are mine to fix.

## Decision

- OSV-Scanner owns dependency advisories. It reads GitHub, RustSec, PyPA and
  more through [OSV](https://osv.dev/), and covers every lockfile here.
  `.github/workflows/osv-scanner.yml` fails a pull request that adds a known
  vulnerability, runs a full scan on main and every Monday and sends its
  findings to code scanning. `just vulns` runs the same scan locally. #152.
- cargo-deny checks licences, bans and sources for both Rust workspaces, from
  `deny.toml`. Its advisories check stays off, so each advisory has one record.
  #152.
- Dependabot stays, for its version and security pull requests.
- The gateway and pipeline build with `cargo auditable`. The release scans
  both architectures before it tags the images, and stops on any advisory in a
  Rust crate. release-please has tagged the release by then, so the gate holds
  the image tags, provenance and SBOMs, not the release. Base-image advisories
  are reported, never blocking: their fix is a newer base digest, which
  Dependabot proposes each week. Each architecture
  gets an SPDX SBOM, attested against its own image and attached to the
  release. A scan of the third-party images runs every Monday and on any pull
  request that touches `deploy/`, and only reports. It reads each image field
  in the manifests and kube-vip's pin in `config.sh`. Cilium's images come from
  its Helm chart, so it can't see them yet. #153.
- CodeQL adds `javascript-typescript`, and zizmor audits the workflows. #154.
- I triage every finding within 7 days, as `SECURITY.md` promises a reporter.
  Each gets one of four outcomes:
  - **Fix.** A bump or a code change, naming the advisory. A fix to something I
    ship is `fix(...)`, so it cuts a release. Dependabot titles every bump
    `chore(deps)`, a new base digest included, so I retitle one that touches
    what I ship to `fix(deps)` before I squash it.
  - **Not affected.** For an advisory, the reason goes in the nearest
    `osv-scanner.toml`, with an `ignoreUntil` no more than 6 months out. That
    entry is the record, because it lapses and a dismissed alert never comes
    back. For a CodeQL or zizmor finding, the reason goes in the alert's
    dismissal or a zizmor ignore comment.
  - **Upstream.** I link the upstream issue, or file one, and carry a
    workaround that links it. A public issue only for a public advisory.
    Anything new goes to the maintainer privately.
  - **Accepted.** Recorded like "not affected", with the risk as the reason.
- Deadlines run from triage. High or Critical and reachable: fixed and released
  within 7 days. Medium: within 30 days. Low and informational: the next weekly
  sweep.
- A weakness in my own code goes in a fixed order: a draft GitHub security
  advisory with a CVE requested on it, the fix in its private fork, a release,
  the advisory published, then a directive in `docs/directives/`.
- The order is public in `SECURITY.md`.

## Options I turned down

- **Dependabot alone.** It reads only GitHub's database. It missed heapless.
- **cargo-audit.** It reads RustSec only, and cargo-deny covers it.
- **cargo-deny for advisories as well.** It would raise the same advisories as
  OSV-Scanner, and every "not affected" would need two records that drift
  apart.
- **dependency-review-action for the pull request gate.** GitHub's database
  only, again.
- **Trivy for images.** SHA pinning guards against a hijacked tag, but
  OSV-Scanner already reads images. A second tool means a second ignore format.
- **Grype.** The same reason. It's the fallback if OSV-Scanner's image coverage
  proves thin.
- **Snyk or Socket.** Commercial, and the free tools cover every ecosystem
  here.
- **Blocking a release on any High or Critical advisory in the image.** My
  first draft did. The base image would have stopped every release on
  advisories only Debian and distroless can fix.
- **Blocking on third-party images.** Most findings there are in Debian
  packages I can't change. Blocking on them would stall my pull requests on
  someone else's release.

## Consequences

- Two more workflows, and a few more minutes of CI on each pull request.
- The Monday scan raises findings against code I haven't touched. That's its
  job: heapless arrived that way.
- Every `osv-scanner.toml` ignore expires, so each advisory decision comes back
  for a second look.
- A reproduction harness pins a flawed version on purpose, so each one needs an
  ignore that points at its directive.
- An advisory in a Rust crate published between merge and release holds the
  image tags. The job builds from the release tag, so an ignore added on main
  can't free it. The way out is a fix and a new release.
- A release can ship with a High advisory in the base image that Debian hasn't
  fixed. It shows in the run's summary, and that's the cost of not waiting
  on Debian.
- The OSV-Scanner check becomes required, which is a ruleset change I make by
  hand.
- Findings in third-party images are visible but not mine to fix. I move the
  digest when upstream ships.
- I'd revisit this if Dependabot gained RustSec, if the project gained
  maintainers to share triage, or if an image scanner caught something
  OSV-Scanner missed.

## References

- [OSV-Scanner](https://google.github.io/osv-scanner/) and its
  [GitHub Action](https://google.github.io/osv-scanner/github-action)
- [The RustSec advisory database](https://rustsec.org/)
- [The cargo-deny book](https://embarkstudios.github.io/cargo-deny/)
- [cargo-auditable](https://github.com/rust-secure-code/cargo-auditable)
- [zizmor](https://docs.zizmor.sh/)
- [Repository security advisories](https://docs.github.com/en/code-security/security-advisories/working-with-repository-security-advisories/about-repository-security-advisories)
- [GHSA-69fq-xp46-6x23](https://github.com/aquasecurity/trivy/security/advisories/GHSA-69fq-xp46-6x23),
  the trivy-action compromise
- [CWE](https://cwe.mitre.org/)
