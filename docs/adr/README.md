# Decisions

Each decision gets a short record: the context, what I chose, what I turned
down and what it costs. I write them as I make them, so this list grows over
the four days. Each one starts from `_template.md`.

Records only ever add to the history. Once one is accepted I never rewrite or
delete it. If I change my mind, a new record supersedes it and the old one's
status says so. Every decision and every reversal stays on file.

| # | Decision | Status |
|---|---|---|
| 1 | MAVLink v2 over a custom framing | To write |
| 2 | [kubeadm over k3s or Talos](0002-kubeadm.md) | Accepted |
| 3 | [Redpanda over Apache Iggy or a home-made log](0003-redpanda.md) | Accepted |
| 4 | Deduplicating in ClickHouse over chasing exactly-once | To write |
| 5 | [just and mise over make, and a local registry for images](0005-just-mise-and-a-local-registry.md) | Accepted |
| 6 | [A scripted kubeadm bootstrap over Terraform or Ansible](0006-scripted-kubeadm-bootstrap.md) | Accepted |
| 7 | [OSV-Scanner and a fixed triage routine over Dependabot alone](0007-osv-scanner-and-a-triage-routine.md) | Accepted |
