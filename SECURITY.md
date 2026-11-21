# Security policy

## Reporting a vulnerability

Please report it privately through
[GitHub's private vulnerability reporting](https://github.com/guy-with-a-why/telemetry-blackbox/security/advisories/new),
not in a public issue.

Say what you found, how to reproduce it and what it affects. I'll reply within
a week, agree a disclosure date with you and credit you in the advisory unless
you'd rather I didn't.

## How I handle a vulnerability

OSV-Scanner, CodeQL and zizmor raise findings in the repo's code scanning
alerts, and Dependabot in its own. The image scans report in each workflow
run's summary. I triage each finding within a week. The reasons behind this
routine are in [ADR 7](docs/adr/0007-osv-scanner-and-a-triage-routine.md).

### In a dependency

1. A scanner raises it, or you report it.
2. I triage it: fix, not affected, upstream or accepted.
3. A fix to something I ship goes out in a release.
4. A finding that doesn't reach this project goes in `osv-scanner.toml` with
   the reason and a date to look at it again.
5. A fix that belongs upstream gets an issue there, or a private report if the
   flaw isn't public yet. I carry a workaround until it ships.
6. Once the advisory is public and the fix has shipped, I write it up as a
   [directive](docs/directives/README.md).

### In my own code

1. I open a draft GitHub security advisory and request a CVE on it. If you
   reported it privately, I accept your report as that draft.
2. I fix it in the advisory's private fork, out of public view.
3. I merge the fix and cut a release.
4. I publish the advisory, and the CVE goes public with it.
5. The directive goes up after that, never before.

### Deadlines

| Finding | Fixed and released within |
|---|---|
| High or Critical, and reachable | 7 days |
| Medium | 30 days |
| Low or informational | the next weekly sweep |

The work that puts the scanners in place is in the
[Security milestone](https://github.com/guy-with-a-why/telemetry-blackbox/milestone/7).

## Supported versions

Only the latest release gets fixes. The project is under construction, so
there are no long-lived release branches to patch.

## Scope

The gateway and pipeline images, the firmware and the deployment manifests
are in scope. The cluster is a lab on one machine and isn't exposed to the
internet, so a finding there matters most if it would carry over to a real
deployment.
