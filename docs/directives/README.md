# Airworthiness directives

When a fault turns up in a part, the aviation authority issues an airworthiness
directive and every operator of that type checks their aircraft. Here a
directive writes up a weakness found in telemetry-blackbox's own code: what was
found, the [CWE](https://cwe.mitre.org/) behind it, how far it reached and how I
fixed it.

Advisories in dependencies don't get one. I bump them or record why they don't
apply, as [ADR 7](../adr/0007-osv-scanner-and-a-triage-routine.md) sets out.

Directives start from `_template.md`, once the fix has shipped and its GitHub
security advisory is public. The reproduction is the regression test that came
with the fix, in the crate it fixed.

None yet.
