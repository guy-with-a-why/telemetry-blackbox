# telemetry-blackbox

A flight recorder for a simulated flight controller. Rust firmware runs a
1 kHz control loop and streams MAVLink telemetry over a serial link. A Rust
gateway, Redpanda and a [Spate](https://github.com/spate-etl/spate) pipeline
carry every frame into ClickHouse, on a highly available Kubernetes cluster
I built by hand.

> **Status:** under construction. Progress is tracked in the
> [milestones](../../milestones).

## Why I'm building it

I want to understand four things from the bottom up:

- Kubernetes run on my own machines, including the parts that break.
- Rust, both `no_std` on a microcontroller and async on a server.
- Real-time embedded systems and the protocols between them.
- Streaming data into ClickHouse with Spate.

A black box is a good way to learn all four at once. It has a hard deadline
at one end, a database at the other and a simple test in between. Did every
frame arrive?

## The claim

Cut the serial link, kill the pipeline, drain a node or lose a control plane
in the middle of a flight. Every frame still reaches ClickHouse. Some arrive
twice, because delivery is at-least-once, and ClickHouse removes the
duplicates by key. `bbcheck` measures the outcome after each drill, and the
numbers go in [Results](#results).

![Spate crashes after inserting frames 41 to 43 but before committing. On restart the same frames arrive again, and ClickHouse removes the duplicates when it merges.](docs/diagrams/chaos-proof.svg)

## How it fits together

![Firmware in Renode sends MAVLink over UART to a gateway in the cluster. The gateway publishes to Redpanda, Spate loads ClickHouse, Grafana reads it and bbcheck verifies it.](docs/diagrams/architecture.svg)

Each part has one job.

| Part | Built with | Job |
|---|---|---|
| `firmware/` | Rust, `no_std`, Embassy | Runs the control loop on a hardware timer and sends telemetry over UART |
| `gateway/` | Rust, tokio | Finds frame boundaries, checks CRCs, spots sequence gaps and publishes to Redpanda |
| `pipeline/` | Rust, Spate | Decodes frames, routes them into tables and loads ClickHouse |
| `deploy/` | cloud-init, kubeadm, YAML | Builds the VMs and the cluster, then runs everything on it |
| `tools/bbcheck/` | Python | Proves what arrived: gaps, duplicates and latency |

## The cluster

Five VMs on one machine. Three control planes share a virtual IP, so the API
stays up when one of them goes down. Two workers carry the workloads, and a
node label decides which one owns the serial link.

![Three control planes behind a kube-vip virtual IP, and two workers. edge-1 owns the serial link and runs the gateway. data-1 runs Redpanda, the pipeline, ClickHouse and Grafana.](docs/diagrams/cluster.svg)

Renode runs on the host, outside the cluster, because it stands in for a
physical device. On real hardware the gateway would read `/dev/ttyUSB0`.
Here it reads the TCP socket Renode exposes.

## The life of one frame

![Frames 41 to 43 pass through the gateway into Redpanda. Spate inserts them into ClickHouse and commits the offset only once the batch is durable.](docs/diagrams/frame-journey.svg)

The last step matters most. Spate only commits an offset once ClickHouse has
confirmed the batch is durable, so a crash can repeat work but never skip it.
That is where duplicates come from, and why the table removes them by
`(boot_id, system_id, seq)`.

## The wire format

Telemetry uses MAVLink v2. Every frame carries a sequence number, which is
what lets the gateway and `bbcheck` count gaps.

| Bytes | Field | Notes |
|---|---|---|
| 1 | `STX` | Always `0xFD` in v2 |
| 1 | `len` | Payload length |
| 1 | `incompat_flags` | Bit 0 marks a signed frame |
| 1 | `compat_flags` | Safe to ignore if unknown |
| 1 | `seq` | Wraps at 255; a jump means lost frames |
| 1 | `sysid` | Which vehicle |
| 1 | `compid` | Which component on it |
| 3 | `msgid` | 24-bit message ID |
| `len` | payload | Trailing zero bytes are trimmed |
| 2 | `checksum` | CRC-16/MCRF4XX, seeded with the message's `CRC_EXTRA` |
| 13 | signature | Only on signed frames |

The firmware sends `HEARTBEAT`, `ATTITUDE`, `HIGHRES_IMU` and a custom
`LOOP_TIMING` message that reports overruns and jitter.

## Real-time, honestly

The control loop is hard real-time inside the simulation. Renode runs in
deterministic virtual time, so loop timing reflects the firmware alone.

Everything after the serial port is soft real-time. I measure it as
end-to-end latency percentiles, from the firmware's timestamp to the row
landing in ClickHouse.

## Running it

Still being built. When it's done, it will look like this:

```bash
make bench      # check the tools are installed
make cluster    # five VMs and a highly available cluster
make deploy     # Redpanda, ClickHouse, Grafana, gateway and pipeline
make fly        # boot the firmware in Renode and start streaming
make check      # run bbcheck against ClickHouse
```

You'll need Linux with KVM, about 10 GB of free memory, Multipass, Renode,
Rust with the `thumbv7em-none-eabihf` target, `uv` and, for the diagrams,
[D2](https://d2lang.com).

## Repository layout

```text
firmware/        Embassy firmware for the STM32F4
gateway/         serial link to Redpanda
pipeline/        Spate pipeline into ClickHouse
deploy/          VMs, cluster bootstrap and manifests
tools/bbcheck/   delivery and latency report
docs/adr/        decisions and the reasons behind them
docs/diagrams/   D2 sources and the SVGs they render
runbooks/        drills, with real output
```

## Decisions

Each gets a short record in `docs/adr/`.

1. MAVLink v2 over a custom framing.
2. kubeadm over k3s or Talos.
3. Redpanda over Apache Iggy or a home-made log.
4. Deduplicating in ClickHouse over chasing exactly-once.

## Results

These fill in as the drills run.

| Drill | Frames sent | Missing | Duplicates | Recovery |
|---|---|---|---|---|
| Kill the pipeline | pending | pending | pending | pending |
| Drain the pipeline's node | pending | pending | pending | pending |
| Restart Redpanda | pending | pending | pending | pending |
| Cut the serial link for 60 s | pending | pending | pending | pending |
| Lose a control plane | pending | pending | pending | pending |
| Scale the pipeline to two replicas | pending | pending | pending | pending |

## Diagrams

Every diagram is a [D2](https://d2lang.com) file in `docs/diagrams/`. D2 lays
it out, and each SVG follows the viewer's light or dark theme. The animated
ones step through boards declared in the same file.

To change one, edit the `.d2` file and watch it live, then render the lot:

```bash
d2 --watch --layout=elk docs/diagrams/architecture.d2
make diagrams
```
