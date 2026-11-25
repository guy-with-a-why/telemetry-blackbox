//! Logic for the STM32F407VG firmware that doesn't touch the hardware.

#![no_std]

use core::sync::atomic::{AtomicU32, Ordering::Relaxed};

/// The control loop runs at this rate.
pub const LOOP_HZ: u32 = 1_000;

/// One period of the loop, in microseconds.
const PERIOD_US: u32 = 1_000_000 / LOOP_HZ;

/// What the timer interrupt measured at the start of one tick.
#[derive(Clone, Copy, Debug)]
pub struct Tick {
    /// A free-running clock when the tick started, in microseconds. It may
    /// wrap.
    pub start_us: u32,
    /// How far the loop's timer had counted since the update event that
    /// released this tick.
    pub latency: u32,
    /// Counts of the loop's timer in one period.
    pub period: u32,
    /// Whether the next update event came before the tick's work finished.
    pub overran: bool,
}

/// How well the control loop keeps its deadline.
///
/// The timer interrupt is the only writer, so plain loads and stores are
/// enough, and a lower-priority reader never blocks it. Latency and jitter
/// are in counts of the loop's timer. The fields stay in this order, so a
/// debugger or Renode can read them at fixed offsets.
#[repr(C)]
pub struct LoopTiming {
    ticks: AtomicU32,
    overruns: AtomicU32,
    missed: AtomicU32,
    max_jitter: AtomicU32,
    last_latency: AtomicU32,
    last_release_us: AtomicU32,
}

/// A copy of the counters, taken outside the interrupt.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Snapshot {
    /// Ticks the loop has run.
    pub ticks: u32,
    /// Ticks whose work ran past the next deadline.
    pub overruns: u32,
    /// Update events that never ran a tick, because an earlier one was still
    /// running or started a whole period late.
    pub missed: u32,
    /// The largest change in start latency between two consecutive ticks, in
    /// timer counts. It equals the worst distance of a period from nominal.
    pub max_jitter: u32,
}

impl LoopTiming {
    pub const fn new() -> Self {
        Self {
            ticks: AtomicU32::new(0),
            overruns: AtomicU32::new(0),
            missed: AtomicU32::new(0),
            max_jitter: AtomicU32::new(0),
            last_latency: AtomicU32::new(0),
            last_release_us: AtomicU32::new(0),
        }
    }

    /// Records one tick and returns how many ticks have run, this one
    /// included.
    pub fn record(&self, tick: Tick) -> u32 {
        // When the update event fired. The timer's count wraps each period,
        // but the free-running clock doesn't, so whole periods between two
        // releases show any update events that merged into one.
        let latency_us = u64::from(tick.latency) * u64::from(PERIOD_US) / u64::from(tick.period);
        let release_us = tick.start_us.wrapping_sub(latency_us as u32);

        let ticks = self.ticks.load(Relaxed);
        if ticks > 0 {
            let elapsed = release_us.wrapping_sub(self.last_release_us.load(Relaxed));
            let periods = (elapsed + PERIOD_US / 2) / PERIOD_US;
            if periods > 1 {
                add(&self.missed, periods - 1);
            } else {
                let jitter = tick.latency.abs_diff(self.last_latency.load(Relaxed));
                if jitter > self.max_jitter.load(Relaxed) {
                    self.max_jitter.store(jitter, Relaxed);
                }
            }
        }
        self.last_latency.store(tick.latency, Relaxed);
        self.last_release_us.store(release_us, Relaxed);

        if tick.overran {
            add(&self.overruns, 1);
        }
        let ticks = ticks.wrapping_add(1);
        self.ticks.store(ticks, Relaxed);
        ticks
    }

    /// Ticks the loop has run, in one load.
    pub fn ticks(&self) -> u32 {
        self.ticks.load(Relaxed)
    }

    pub fn snapshot(&self) -> Snapshot {
        Snapshot {
            ticks: self.ticks.load(Relaxed),
            overruns: self.overruns.load(Relaxed),
            missed: self.missed.load(Relaxed),
            max_jitter: self.max_jitter.load(Relaxed),
        }
    }
}

/// Adds to a counter that only one context writes.
fn add(counter: &AtomicU32, n: u32) {
    counter.store(counter.load(Relaxed).wrapping_add(n), Relaxed);
}

impl Default for LoopTiming {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// At 16 MHz one period is 16,000 counts, and 16 counts are 1 µs.
    const PERIOD: u32 = 16_000;

    fn tick(start_us: u32, latency: u32, overran: bool) -> Tick {
        Tick {
            start_us,
            latency,
            period: PERIOD,
            overran,
        }
    }

    #[test]
    fn counts_ticks() {
        let timing = LoopTiming::new();
        assert_eq!(timing.record(tick(0, 4, false)), 1);
        assert_eq!(timing.record(tick(1_000, 4, false)), 2);
        assert_eq!(timing.ticks(), 2);
    }

    #[test]
    fn first_tick_has_no_jitter() {
        let timing = LoopTiming::new();
        timing.record(tick(0, 40, false));
        assert_eq!(timing.snapshot().max_jitter, 0);
    }

    #[test]
    fn keeps_the_worst_jitter_either_way() {
        let timing = LoopTiming::new();
        for (n, latency) in [10, 13, 9, 11].into_iter().enumerate() {
            timing.record(tick(n as u32 * 1_000, latency, false));
        }
        // 13 to 9 is the largest step, and it's a step down.
        assert_eq!(timing.snapshot().max_jitter, 4);
    }

    #[test]
    fn counts_overruns() {
        let timing = LoopTiming::new();
        timing.record(tick(0, 4, false));
        timing.record(tick(1_000, 4, true));
        // The overrun made this tick start 0.5 ms late, but no update event
        // was lost.
        timing.record(tick(2_500, 8_000, true));
        assert_eq!(
            timing.snapshot(),
            Snapshot {
                ticks: 3,
                overruns: 2,
                missed: 0,
                max_jitter: 8_000 - 4
            }
        );
    }

    #[test]
    fn counts_update_events_a_long_tick_swallowed() {
        let timing = LoopTiming::new();
        timing.record(tick(0, 4, true));
        // The first tick ran 3.25 ms, so the updates at 1 ms and 2 ms merged
        // and the next tick starts 0.25 ms after the one at 3 ms.
        timing.record(tick(3_250, 4_000, false));
        let snapshot = timing.snapshot();
        assert_eq!((snapshot.overruns, snapshot.missed), (1, 2));
        // A lost tick says nothing about jitter.
        assert_eq!(snapshot.max_jitter, 0);
    }

    #[test]
    fn sees_a_tick_released_a_whole_period_late() {
        let timing = LoopTiming::new();
        timing.record(tick(0, 4, false));
        // Masked for 1.2 ms, the tick starts after its timer wrapped, so its
        // latency looks small. Only the free-running clock shows the gap.
        timing.record(tick(2_200, 3_200, false));
        assert_eq!(timing.snapshot().missed, 1);
    }

    #[test]
    fn copes_with_the_clock_wrapping() {
        let timing = LoopTiming::new();
        timing.record(tick(u32::MAX - 499, 0, false));
        timing.record(tick(500, 0, false));
        assert_eq!(timing.snapshot().missed, 0);
    }
}
