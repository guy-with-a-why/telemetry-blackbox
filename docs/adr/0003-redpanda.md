# 0003. Redpanda over Apache Iggy or a home-made log

- **Status:** Accepted
- **Date:** 2026-11-19
- **Issue:** #16

## Context

The gateway reads frames off the serial link, and Spate loads them into
ClickHouse. Something has to sit between them and hold every frame while the
pipeline is down. The drills kill the pipeline, restart the log and drain its
node, so that buffer is where a lost frame would come from.

What the log has to do:

1. Keep a frame once it acknowledges it, through a crash or a restart.
2. Let a consumer replay from an offset. Spate commits an offset only after
   ClickHouse confirms the batch is durable, so a restart repeats work rather
   than skipping it.
3. Split frames by key across partitions and share them out to a consumer
   group, so the drill that scales the pipeline to two replicas works.

The constraints:

- Spate already has a Kafka source. It has no source for anything else I'd
  consider.
- data-1 has 2 shared vCPUs, 4 GB and a 40 GB disk, and ClickHouse, Grafana
  and the pipeline run there too.
- There's one data node, so nothing can be replicated yet.
- Leg 1 is due on 20 November.

## Decision

- One Redpanda v26.2.7 broker runs as a StatefulSet on data-1, on a 10 Gi
  local volume. The manifests are in
  [`deploy/redpanda/`](https://github.com/guy-with-a-why/telemetry-blackbox/tree/main/deploy/redpanda),
  and `just redpanda` applies them.
- `telemetry.raw` has six partitions, one replica and 1 GiB of retention per
  partition.
- The broker starts in dev mode with one core and 512 MB. Write caching and
  the fsync bypass that dev mode turns on are both off, so an ack means the
  frame is on disk.
- `just redpanda-check` proves a Pod restart loses nothing.
  [Holding pattern](../blog/2026-11-18-holding-pattern.md) has the detail.

## Options I turned down

- **Apache Kafka.** The reference implementation, with the same protocol.
  It runs on a JVM with its own heap, which is a poor fit for 2 shared vCPUs
  next to ClickHouse. The clients wouldn't notice the difference, so I can
  swap it in later.
- **Apache Iggy.** Written in Rust and lighter still. It speaks its own
  protocol and Spate has no Iggy source yet, so choosing it would put a new
  connector on the critical path. That connector is stretch work in
  [#32](https://github.com/guy-with-a-why/telemetry-blackbox/issues/32).
- **A home-made log.** I'd be writing offsets, retention, consumer groups and
  fsync handling myself. Every bug in them would show up as a lost frame, and
  the drills would blame the pipeline for it.

## Consequences

- The Kafka protocol is the contract. Spate's source, `rpk` and any Kafka
  client work against it, and the broker behind it can change.
- One broker with one replica means a lost disk on data-1 loses every frame
  Spate hasn't loaded. Draining data-1 stops Redpanda until the node is back,
  and the drain drill in
  [#27](https://github.com/guy-with-a-why/telemetry-blackbox/issues/27) will
  show it.
- Dev mode's defaults are unsafe for this job. I missed the fsync bypass the
  first time, and a restart check can't catch it. The flag is now explicit in
  the manifest, and the Leg 4 drills should stop data-1 hard.
- Seastar claims its memory up front and wants a core of its own. The flags
  and a 1 GiB limit keep it to its share of data-1.
- Redpanda is source-available under the Business Source Licence, not open
  source. That's fine for running it myself.
- I'd revisit this if Spate gained an Iggy source, if a second and third data
  node arrived for replication, or if the licence changed.

## References

- [Redpanda on Kubernetes](https://docs.redpanda.com/current/deploy/redpanda/kubernetes/)
- [Redpanda's development mode](https://docs.redpanda.com/current/reference/rpk/rpk-redpanda/rpk-redpanda-mode/)
- [Seastar](https://seastar.io/)
- [Spate's delivery invariants](https://github.com/spate-etl/spate/blob/main/docs/INVARIANTS.md)
- [Apache Iggy](https://iggy.apache.org/)
- [Apache Kafka](https://kafka.apache.org/documentation/)
