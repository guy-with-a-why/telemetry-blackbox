<!-- One directive per weakness in this project's own code. Advisories in
dependencies don't get one. Copy this file to YYYY-MM-DD-slug.md and number it
AD YYYY-NNN in order. Add it as the last row of the table in
directives/README.md and the last directive entry in SUMMARY.md.

Publish only once the fix has shipped and the GitHub security advisory is
public. Never write up an unfixed weakness.

Link the CWE to its MITRE definition page and give its name exactly as MITRE
does. Severity is the advisory's CVSS score. -->
# AD YYYY-NNN: Title

*D Month YYYY*

| | |
|---|---|
| Advisory | The GitHub security advisory and its CVE, each linked |
| Weakness | The CWE, linked to its MITRE definition page, named as MITRE gives it |
| Affects | The crate or component, and the releases it shipped in |
| Severity | The [CVSS](https://www.first.org/cvss/) score and vector |
| Found | The date, and the tool or person that found it |
| Closed | The date, and the pull request and release that fixed it |

## What was found

How it surfaced and what it does, in a sentence or two.

## The weakness

What the CWE is and why it's dangerous, for an engineer who hasn't met it.
Where it sits in the CWE tree, and the [CAPEC](https://capec.mitre.org/) attack
pattern that uses it if one fits.

## How far it reached

The verdict first. Then which releases carried it, what input reaches it and
what an attacker would need.

## How it was fixed

The change, and the regression test that came with it. The test fails on the
last vulnerable release and passes on the fix. Name the tool that makes the
flaw visible if it needs one, such as Miri or a fuzz target.

## What guards against it now

The test, check or fuzz target that catches the next one.

## References

- The CWE's definition page on [MITRE](https://cwe.mitre.org/)
- The GitHub security advisory and the CVE
- The pull request that fixed it
