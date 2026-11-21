# Runbooks

Every drill I run gets a runbook: the steps, what I expected and the real
output. They fill in as the drills happen, and each one starts from
`_template.md`.

| Runbook | Drill | Status |
|---|---|---|
| [`bootstrap.md`](bootstrap.md) | Bootstrap the cluster by hand | Run on 15 Nov 2026 |
| [`control-plane.md`](control-plane.md) | Lose one control plane, then two | Run on 16 Nov 2026 |
| [`etcd.md`](etcd.md) | Snapshot and restore etcd | Run on 17 Nov 2026 |
| [`triage.md`](triage.md) | Triage one alert from the Security tab to closed | Run on 20 Nov 2026 |
| `chaos.md` | Break the pipeline while it streams | To run |
