<!-- One directive per advisory or weakness. Copy this file to
YYYY-MM-DD-slug.md and number it AD YYYY-NNN in order. Add it as the last row of
the table in directives/README.md and the last directive entry in SUMMARY.md.

Publish only once the advisory is public and the fix has shipped. Never write up
an unfixed weakness in my own code or one upstream hasn't disclosed.

Link every CWE to its MITRE definition page and give its name exactly as MITRE
does. Use the advisory's CWE. If a more precise one fits, name it and say why.
If the advisory gives none, pick one and say it's my mapping. Severity is the
advisory's own score, never one I made up. If I rescore it for this project,
show both.

A critical advisory earns a deep dive: keep the "Reproducing the weakness"
section and show the flaw running. A routine bump deletes it. Reproduce only a
public advisory whose fix has shipped, only against the pinned vulnerable
version, in a harness the build never links. It proves the weakness, it is not a
tool to point at anyone else's system. -->
# AD YYYY-NNN: Title

*D Month YYYY*

| | |
|---|---|
| Advisory | The advisory and its aliases, each linked: the RustSec or GitHub (GHSA) page and the CVE on cve.org, or "none, found here" |
| Weakness | The CWE, linked to its MITRE definition page, named as MITRE gives it |
| Affects | The package and versions, and how it arrives: direct, or through which crate |
| Severity | The [CVSS](https://www.first.org/cvss/) score and vector, or "none given" |
| Found | The date, and the tool or person that found it |
| Verdict | Fixed, not affected, upstream or accepted |
| Closed | The date, and the pull request and release that closed it |

## What was found

How it surfaced, which scanner saw it and which didn't. What the advisory says
in a sentence or two.

## The weakness

What the CWE is and why it's dangerous, for an engineer who hasn't met it. Where
it sits in the CWE tree: its parent, and a more precise child if the advisory's
is broad. Whether it's in the current
[CWE Top 25](https://cwe.mitre.org/top25/), and the
[CAPEC](https://capec.mitre.org/) attack pattern that uses it if one fits.

<!-- Deep dive only. Delete this whole section for a routine bump. -->
## Reproducing the weakness

### The attack vector

The [CAPEC](https://capec.mitre.org/) attack pattern that fits, linked to its
definition page. What the attacker controls, the precondition they need and what they get
out of it. In plain terms, not a script. Say where untrusted input would enter
a real system through this path.

### The harness

Where it lives and how to run it. The harness is a crate under
`docs/directives/repro/<slug>/` with its own lockfile pinned to the vulnerable
version, outside the workspace so nothing links it. Its lockfile pins a known
flaw on purpose, so it sits in the nearest `osv-scanner.toml` ignore with a
reason pointing here. Name the tool that makes the flaw visible: Miri or
AddressSanitizer for a memory bug, a timeout for a loop that never ends,
[cargo-fuzz](https://rust-fuzz.github.io/book/) for a parser.

### What it shows

The observable proof, with the real output: the sanitizer's report line, the
seconds the loop ran before the timeout, the panic and its message. One captured
number, nothing invented. Then the fixed version through the same harness,
coming back clean.

## Did it reach this project

The triage. Which functions carry the flaw, whether my code or a dependency
calls them and whether untrusted input can get there. Show the weighing, then
the verdict.

## How it was fixed

The change, and why it beat the alternatives: a bump, an override or patch, a
dismissal with the reason recorded, or waiting on upstream. The proof: the scan
that came back clean, the test or the build.

## Upstream

What I found or filed upstream and where it stands. A public issue only for an
advisory that's already public. Anything new goes through the maintainer's
private reporting. Delete this section if nothing went upstream.

## What guards against it now

The check, gate, test or fuzz target that catches the next one. If a scan would
have caught this one sooner, say which and whether it runs now.

## Check your understanding

<details>
<summary>A question a reader should be able to answer after the post.</summary>

The answer in a line or two.

</details>

## References

- The CWE's definition page on [MITRE](https://cwe.mitre.org/)
- The advisory on [OSV](https://osv.dev/), and on
  [RustSec](https://rustsec.org/advisories/),
  [GitHub](https://github.com/advisories) or
  [NVD](https://nvd.nist.gov/vuln/search) where it's listed
- The upstream issue and fix
- The pull request that closed it here
