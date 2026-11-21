# Leg 1 debrief: A cluster I built myself

*21 November 2026*

| | Planned | Flown |
|---|---|---|
| Landed | 20 November | 21 November |
| Evenings | 4 | 7 |
| Issues | 8 at takeoff | 11 closed, 3 of them headwind |

## What the leg delivered

[Leg 1](https://github.com/guy-with-a-why/telemetry-blackbox/milestone/3)
set out to build a highly available cluster, break it on purpose and put the
stores on it. It did all three. Five VMs run on my home server, and caches on
the host cut a full rebuild from 18 minutes to 6. I bootstrapped three control
planes behind a virtual IP by hand in
[#11](https://github.com/guy-with-a-why/telemetry-blackbox/issues/11), then
turned the same steps into one command in
[#105](https://github.com/guy-with-a-why/telemetry-blackbox/issues/105).

The drills prove it holds. Losing one control plane in
[#12](https://github.com/guy-with-a-why/telemetry-blackbox/issues/12) cost
nothing, and losing two stopped writes exactly as quorum says it should. The
etcd restore in
[#13](https://github.com/guy-with-a-why/telemetry-blackbox/issues/13) took
reads down for 19 minutes the first time and 93 seconds following the
runbook. Redpanda in
[#14](https://github.com/guy-with-a-why/telemetry-blackbox/issues/14) kept all
100,000 acknowledged records through a Pod delete. ClickHouse in
[#15](https://github.com/guy-with-a-why/telemetry-blackbox/issues/15) took
10,000 frames twice and kept 10,000. ADRs 2 and 3 record why kubeadm and
Redpanda, and the checkpoint in
[#17](https://github.com/guy-with-a-why/telemetry-blackbox/issues/17) closed
the leg.

## How it went

The first call set the rest. My laptop had 6 GB free against a 10.5 GB budget,
so the cluster moved to my home server before the first VM booted. Building
the control plane by hand first, then scripting it, meant every line of the
script was a step I'd already run and understood. The plan's order held, and
every issue landed in it.

Two calls changed the design mid-leg. The ClickHouse key moved from MAVLink's
`seq` to Redpanda's partition and offset, because `seq` wraps at 255 and would
have deleted real frames. And when the bash passed 600 lines, I filed the
move to standard platform tools as
[#130](https://github.com/guy-with-a-why/telemetry-blackbox/issues/130), with a
trigger, rather than polish code it will replace.

## What could have gone better

The budget was wrong, not the work. Four evenings assumed more hours than an
evening holds after a full working day. Exercise, cooking, dishes and some rest
leave a few hours at most. Three issues of headwind added to it. The caches and
the one-command bootstrap paid for themselves within the leg, but they weren't
in the plan.

The due day went on the wrong work. On 20 November I opened nine security
issues and closed four of them instead of sitting the checkpoint. The other
five closed the next day before it did, and the leg landed a day late. From now on, work outside a leg waits until that leg has landed. Security
keeps its own milestone, but it never takes a leg's last evening.

The tools cost evenings of their own. A snap refresh downgraded Multipass
overnight and broke the suspended VMs, so refreshes are now held. `multipass
exec` truncated an etcd snapshot to 2.2 of 15 MB, so the runbook copies with
`multipass transfer` and checks every hash. And a pull request closed #11
while every box on it was still unticked, so I now check which issues a pull
request will close before it merges.

## Into the next leg

The lesson that leads is to budget for the machine I have. My home server is a
2012 two-core i5 on a link of about 1.1 MB/s. ClickHouse 26.8 needs AVX2, and I
found out after five minutes spent pulling an image that couldn't run. From
here I check an image's CPU baseline before pulling it, and I size work for
this box, not an ideal one.

The plan now follows the pace I actually flew, with room to read. Leg 1 took
1.75 times its budget, and the legs ahead lean on datasheets, reference
manuals and protocol specs. So every remaining budget doubles, flown every
evening. Leg 2 gets six evenings and lands on 27 November, Leg 3 eight by
5 December and Leg 4 eight by 13 December, nine days after the old landing.
The milestones moved in
[#176](https://github.com/guy-with-a-why/telemetry-blackbox/issues/176).

Leg 2 builds the firmware. Its biggest risk is MAVLink over UART with DMA in
[#6](https://github.com/guy-with-a-why/telemetry-blackbox/issues/6). If DMA
eats the evenings, interrupt-driven writes still keep up with the frame rate,
and DMA moves to Stretch.

Two things carry forward. data-1 has 2.5 of its 4 GiB claimed before the
pipeline and Grafana arrive in Leg 3, and the fallback is another gigabyte from
the host. And the project stays on 0.x. A 1.0.0 promises a stable API, and
Legs 2 and 3 still build the gateway, the pipeline and the wire format. 1.0
waits until the end of Leg 4, when the claim is proven with numbers. A leg is
marked by its debrief and its milestone, not by a version.
