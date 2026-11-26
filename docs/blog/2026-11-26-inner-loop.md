# Inner loop: a deadline every millisecond

*26 November 2026*

## What was done

The firmware has a pulse. TIM3 overflows once a millisecond and its interrupt
runs the control loop. For now the loop only toggles the green LED every 500
ticks, but it already records how well it keeps time. It counts ticks that run
past their deadline, update events that never got a tick and the worst jitter
between two ticks. That closes
[#4](https://github.com/guy-with-a-why/telemetry-blackbox/issues/4), in
[#187](https://github.com/guy-with-a-why/telemetry-blackbox/pull/187).

In 5.064 virtual seconds Renode counted 5,064 ticks, no overruns and a worst
jitter of 187 ns, three counts of the 16 MHz timer. Then I padded every tick to
about 8 ms to see the counters under load. 257 ticks ran and 1,792 were missed,
which is every one of the 2,049 periods in 2.05 seconds.

## Why was it done that way

The board is ST's
[STM32F4DISCOVERY](https://www.st.com/en/evaluation-tools/stm32f4discovery.html).
Renode simulates it out of the box, so I could start without hardware, and it's
a cheap, common board to flash once the simulation has done its job. Its
STM32F407VG is a Cortex-M4F, so the attitude estimate in
[#5](https://github.com/guy-with-a-why/telemetry-blackbox/issues/5) gets a
hardware FPU. The same family turns up in plenty of hobby flight controllers,
which keeps the target realistic.

Embassy runs on it because
[embassy-stm32](https://docs.embassy.dev/embassy-stm32/) already covers the
F407's timers, UART and DMA, so the evenings go into the loop rather than
register plumbing. It also gets out of the way when asked. Its
[low-level timer](https://docs.embassy.dev/embassy-stm32/git/stm32f407vg/timer/low_level/struct.Timer.html)
let me hang the loop off a raw interrupt with no executor in between. Renode is
the bench because it runs in deterministic virtual time, so a timing figure
reflects the firmware and repeats run for run. Its monitor scripts the drills.

The loop runs inside the interrupt, at the top priority. I weighed an Embassy
task woken by a `Ticker`, which reads well, but its wake-up passes through the
executor and the time driver, so its jitter would include theirs. Polling a
timer flag was never in the running. It burns the core and its deadline slips
whenever anything else runs, while an interrupt arrives on time whatever thread
mode is doing. TIM3 sits alone at P0. Embassy starts its own TIM2 and DMA at P0
too. Equal priorities never preempt each other, so a tick would wait for their
handlers to finish, and TIM2's lower IRQ number, 28 to TIM3's 29, would even
win a tie. Both move down to P1.

The loop times itself with TIM3's own counter. The count when the interrupt
starts is the latency since the update event, and the change in it from tick to
tick is the jitter. If the update flag is set again before the work ends, the
tick overran. TIM3 wraps every period, so a tick that starts a whole period
late would look on time. A free-running 32-bit TIM5 at 1 MHz times each
release, and whole periods between two releases show the update events that
merged. The counters are atomics with one writer, the interrupt, so telemetry
can read them without ever blocking it.

## What challenges were faced

The first run in Renode gave 1,910 ticks in 3 virtual seconds, a 1.6 ms period.
Renode's
[STM32F4 platform](https://github.com/renode/renode/blob/master/platforms/cpus/stm32f4.repl)
clocks every timer at a fixed 10 MHz. The real chip on its 16 MHz internal
oscillator clocks them at 16 MHz, so each 16,000-count period ran long. The
same fault had slowed Embassy's clock on TIM2, so the 500 ms blink from
[#3](https://github.com/guy-with-a-why/telemetry-blackbox/issues/3) really ran
at 800 ms. Nobody times a blink. The board script now sets the timers to 16 MHz
by hand. That's a stopgap on purpose. The lasting fix is Renode's F4 clock model
driving its timers, as its H7 and WBA models already do, and
[#188](https://github.com/guy-with-a-why/telemetry-blackbox/issues/188) parks
it so it doesn't eat into Leg 2.

The review on
[#187](https://github.com/guy-with-a-why/telemetry-blackbox/pull/187) turned up
ticks that could go missing without a trace, because of that wrap. My first fix
timed releases with embassy-time's `Instant`, and the overrun drill reported
128,848,810 missed ticks in 2 seconds. A loop that overruns at P0 tail-chains,
one tick straight into the next without returning to thread mode, so TIM2's
handler at P1 never gets a turn. Its period count stalls and its clock runs
backwards after 65 ms. TIM5 needs no interrupt at all, and with it the drill
accounts for every period.

## What's next

The attitude estimate in
[#5](https://github.com/guy-with-a-why/telemetry-blackbox/issues/5) goes into
the loop next. That gives each tick real work and makes an overrun something
the loop can actually do. Then
[#6](https://github.com/guy-with-a-why/telemetry-blackbox/issues/6) sends
telemetry over the UART with DMA. Embassy's UART interrupt starts at P0 as
well, so it moves down to P1 beside DMA.

The biggest risk is critical sections. On a single core each one sets PRIMASK,
which masks every interrupt, P0 included, so Embassy's TIM2 handler and any
channel the telemetry uses set the floor for jitter, whatever the priorities
say. Keeping them short is the guard, and the jitter counter shows it if one
grows. If one does, BASEPRI can mask P1 and below and leave the loop running,
for anything the loop doesn't share. Renode also runs the core at a flat 100
MIPS, so 187 ns is a figure for the model. My fallback is the same as for
[#3](https://github.com/guy-with-a-why/telemetry-blackbox/issues/3). Timing
claims are tied to virtual time, and anything only silicon can prove is marked
for real hardware.

## Quiz

Five questions on the post. Open one for my answer.

<details>
<summary>Why does the loop run in an interrupt rather than polling a timer
flag?</summary>

Polling burns the core, and the deadline slips whenever other code runs. The
interrupt preempts lower-priority work, so the tick starts on time.

</details>

<details>
<summary>Why move embassy-time's TIM2 and DMA down to P1?</summary>

Embassy starts them at P0. At equal priority neither preempts the other, so a
TIM2 or DMA handler already running would hold up the loop.

</details>

<details>
<summary>How does the loop know it overran?</summary>

It clears TIM3's update flag at the start of the tick. If the flag is set
again before the work ends, the next deadline has already passed.

</details>

<details>
<summary>Why can't TIM3's counter alone catch a tick that starts a whole period
late?</summary>

The counter wraps every period, so a late start reads as a small latency. TIM5
keeps counting across periods, which shows the gap.

</details>

<details>
<summary>Why not time the releases with embassy-time?</summary>

Its clock depends on TIM2's interrupt at P1. A loop that overruns at P0 starves
that interrupt, and the clock stops being right exactly when it's needed.

</details>
