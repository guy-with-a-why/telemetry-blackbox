# Airworthiness directives

When a fault turns up in a part, the aviation authority issues an airworthiness
directive and every operator of that type checks their aircraft. A security
advisory works the same way. Each one that reaches this project gets a
directive here, and so does any weakness found in my own code: what was found,
the [CWE](https://cwe.mitre.org/) behind it, whether it reached me and how I
closed it.

Findings come from OSV-Scanner, cargo-deny, Dependabot and CodeQL. The routine
behind them is in
[#155](https://github.com/guy-with-a-why/telemetry-blackbox/issues/155).
Directives start from `_template.md`, and only once the advisory is public and
the fix has shipped.

A critical one gets a deep dive: the attack vector, and a harness under `repro/`
that triggers the weakness against the pinned vulnerable version and shows it,
then shows the fix coming back clean. A repro pins a known flaw on purpose, so it
stays out of the build and its lockfile is ignored in the nearest
`osv-scanner.toml` with a reason. I reproduce only advisories that are already
public and already fixed.

None yet. The first covers heapless, in
[#150](https://github.com/guy-with-a-why/telemetry-blackbox/issues/150).
