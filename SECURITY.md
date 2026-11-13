# Security policy

## Reporting a vulnerability

Please report it privately through
[GitHub's private vulnerability reporting](https://github.com/guy-with-a-why/telemetry-blackbox/security/advisories/new),
not in a public issue.

Say what you found, how to reproduce it and what it affects. I'll reply within
a week, agree a disclosure date with you and credit you in the advisory unless
you'd rather I didn't.

## Supported versions

Only the latest release gets fixes. The project is under construction, so
there are no long-lived release branches to patch.

## Scope

The gateway and pipeline images, the firmware and the deployment manifests
are in scope. The cluster is a lab on one machine and isn't exposed to the
internet, so a finding there matters most if it would carry over to a real
deployment.
