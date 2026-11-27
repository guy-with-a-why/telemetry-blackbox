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

In 5.071 virtual seconds Renode counted 5,071 ticks, no overruns, none missed
and a worst jitter of 187 ns, three counts of the 16 MHz timer. Then I padded
every tick to about 8 ms to see the counters under load. 257 ticks ran and 1,792
were missed, which is every one of the 2,049 periods in 2.05 seconds.

## Why was it done that way

The board is ST's
[STM32F4DISCOVERY](https://www.st.com/en/evaluation-tools/stm32f4discovery.html).
Renode simulates it out of the box, so I could start without any hardware. It's
also cheap and common, so I can flash a real one once the simulation has done
its job. Its chip, the STM32F407VG, is a Cortex-M4F, which gives the attitude
estimate in [#5](https://github.com/guy-with-a-why/telemetry-blackbox/issues/5)
a hardware FPU. The same family turns up in plenty of hobby flight controllers,
so the target is a realistic one.

Embassy runs the firmware because
[embassy-stm32](https://docs.embassy.dev/embassy-stm32/) already drives the
F407's timers, UART and DMA. My evenings go into the loop instead of register
plumbing. It also steps aside when I need it to. Its [low-level
timer](https://docs.embassy.dev/embassy-stm32/git/stm32f407vg/timer/low_level/struct.Timer.html)
and
[interrupt](https://docs.embassy.dev/embassy-stm32/git/stm32f407vg/interrupt/trait.InterruptExt.html)
APIs let me run the loop straight from a hardware interrupt, with no executor in
between.

Renode is the bench because its time is virtual and deterministic. The same
firmware gives the same timing figures on every run, and I can script the drills
from its monitor.

The loop itself runs inside TIM3's interrupt. I considered an Embassy task woken
by a `Ticker`, which would read more nicely. Its wake-up goes through the
executor and the time driver, though, so their delays would end up in the loop's
jitter. Polling a timer flag was never an option. It keeps the core busy doing
nothing, and the tick has to wait for whatever else is running. An interrupt
starts the tick when the timer fires.

Priorities decide who waits. Embassy leaves its TIM2 and DMA interrupts at P0,
the top priority I want for the loop. Interrupts at the same priority never
preempt each other, and when two are pending the lower IRQ number goes first.
TIM2 is 28 and TIM3 is 29, so TIM2 would win. Moving TIM2 and DMA down to P1
leaves TIM3 alone at P0, so the loop wins every tie and can preempt a DMA
handler. TIM2 is the exception. Its handler runs inside a critical section,
which masks the loop as well, so its length still counts against the tick.

The loop measures itself with TIM3's own counter. When the interrupt starts, the
count says how long ago the timer overflowed. That's the tick's latency, and the
change in latency from one tick to the next is the jitter. If the timer
overflows again before the work ends, the tick overran.

TIM3's counter starts again every period, so on its own it can't see a tick that
starts a whole period late. A free-running 32-bit TIM5, counting microseconds,
fills that gap. Each tick works back to when its overflow happened, and more
than one period between two overflows means updates were missed.

The counters are atomics, and only the interrupt writes them. Telemetry can read
them at any time without ever blocking the loop. Each one reads whole, though a
read of all four can straddle a tick, which
[#6](https://github.com/guy-with-a-why/telemetry-blackbox/issues/6) settles.

## What challenges were faced

The first run in Renode gave 1,910 ticks in just over 3 virtual seconds, where
about 3,000 were due. Renode's [STM32F4
platform](https://github.com/renode/renode/blob/master/platforms/cpus/stm32f4.repl)
clocks every timer at a fixed 10 MHz. The real chip on its 16 MHz internal
oscillator clocks them at 16 MHz, so each 16,000-count period took 1.6 ms. The
same fault had slowed Embassy's clock on TIM2, so the 500 ms blink from
[#3](https://github.com/guy-with-a-why/telemetry-blackbox/issues/3) really ran
at 800 ms. Nobody times a blink. The board script now sets the timers to 16 MHz
by hand. That's a stopgap on purpose. The lasting fix is an F4 clock model in
Renode that drives its timers, and
[#188](https://github.com/guy-with-a-why/telemetry-blackbox/issues/188) parks it
so it doesn't eat into Leg 2.

The review on
[#187](https://github.com/guy-with-a-why/telemetry-blackbox/pull/187) turned up
ticks that could go missing without a trace, because of that wrap. My first fix
dated the update events with embassy-time's `Instant`, and the overrun drill
reported 128,848,810 missed ticks in 2 seconds. A loop that overruns at P0 is
pending again the moment it returns, so the NVIC tail-chains straight back into
it and TIM2 at P1 never wins arbitration. Its period count stalls, and its clock
jumps back 65.5 ms each time the 16-bit counter wraps. TIM5 needs no interrupt
at all, and with it the drill accounts for every period.

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
MIPS, about six times what this chip manages on its 16 MHz oscillator, so 187 ns
is a figure for the model. My fallback is the same as for
[#3](https://github.com/guy-with-a-why/telemetry-blackbox/issues/3). Timing
claims are tied to virtual time, and anything only silicon can prove is marked
for real hardware.

## Quiz

Five questions on the post. Open one for my answer.

<details>
<summary>Why does the loop run in an interrupt rather than polling a timer
flag?</summary>

Polling burns the core, and the deadline slips whenever other code runs. The
interrupt preempts lower-priority work, so the tick starts after a fixed entry
latency unless a critical section holds it.

</details>

<details>
<summary>Why move TIM2 and the DMA interrupts down to P1?</summary>

Embassy leaves them at P0. At equal priority nothing preempts, and TIM2's lower
IRQ number wins a tie. At P1 the tick wins every tie and preempts DMA. TIM2's
handler sits in a critical section, so it can still hold the tick.

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
<summary>Why not date the update events with embassy-time?</summary>

Its clock depends on TIM2's interrupt at P1. A loop that overruns at P0 starves
that interrupt, and the clock stops being right exactly when it's needed.

</details>
