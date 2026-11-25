//! Logic for the STM32F407VG firmware that doesn't touch the hardware.

#![no_std]

use core::sync::atomic::{AtomicU32, Ordering::Relaxed};

/// The control loop runs at this rate.
pub const LOOP_HZ: u32 = 1_000;

/// Marks that no tick has been recorded yet, so there's nothing to compare.
const NO_LATENCY: u32 = u32::MAX;

/// How well the control loop keeps its deadline.
///
/// The timer interrupt is the only writer, so plain loads and stores are
/// enough, and a lower-priority reader never blocks it. Times are in counts of
/// the loop's timer. The fields stay in this order, so a debugger or Renode can
/// read them at fixed offsets.
#[repr(C)]
pub struct LoopTiming {
    ticks: AtomicU32,
    overruns: AtomicU32,
    max_jitter: AtomicU32,
    last_latency: AtomicU32,
}

/// A copy of the counters, taken outside the interrupt.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Snapshot {
    /// Ticks the loop has run.
    pub ticks: u32,
    /// Ticks whose work ran past the next deadline.
    pub overruns: u32,
    /// The largest change in start latency from one tick to the next, in
    /// timer counts. It equals the worst distance of a period from nominal.
    pub max_jitter: u32,
}

impl LoopTiming {
    pub const fn new() -> Self {
        Self {
            ticks: AtomicU32::new(0),
            overruns: AtomicU32::new(0),
            max_jitter: AtomicU32::new(0),
            last_latency: AtomicU32::new(NO_LATENCY),
        }
    }

    /// Records one tick and returns how many ticks have run, this one
    /// included.
    ///
    /// `latency` is how far the timer had counted when the tick started, and
    /// `overran` says whether the next deadline passed before it finished.
    pub fn record(&self, latency: u32, overran: bool) -> u32 {
        let last = self.last_latency.load(Relaxed);
        if last != NO_LATENCY {
            let jitter = latency.abs_diff(last);
            if jitter > self.max_jitter.load(Relaxed) {
                self.max_jitter.store(jitter, Relaxed);
            }
        }
        self.last_latency.store(latency, Relaxed);

        if overran {
            self.overruns
                .store(self.overruns.load(Relaxed).wrapping_add(1), Relaxed);
        }
        let ticks = self.ticks.load(Relaxed).wrapping_add(1);
        self.ticks.store(ticks, Relaxed);
        ticks
    }

    pub fn snapshot(&self) -> Snapshot {
        Snapshot {
            ticks: self.ticks.load(Relaxed),
            overruns: self.overruns.load(Relaxed),
            max_jitter: self.max_jitter.load(Relaxed),
        }
    }
}

impl Default for LoopTiming {
    fn default() -> Self {
        Self::new()
    }
}

/// Converts timer counts to nanoseconds, given how many counts make one
/// period of the loop.
pub fn counts_to_ns(counts: u32, counts_per_period: u32) -> u32 {
    let ns_per_period = 1_000_000_000 / u64::from(LOOP_HZ);
    (u64::from(counts) * ns_per_period / u64::from(counts_per_period)) as u32
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn counts_ticks() {
        let timing = LoopTiming::new();
        assert_eq!(timing.record(4, false), 1);
        assert_eq!(timing.record(4, false), 2);
        assert_eq!(timing.snapshot().ticks, 2);
    }

    #[test]
    fn first_tick_has_no_jitter() {
        let timing = LoopTiming::new();
        timing.record(40, false);
        assert_eq!(timing.snapshot().max_jitter, 0);
    }

    #[test]
    fn keeps_the_worst_jitter_either_way() {
        let timing = LoopTiming::new();
        for latency in [10, 13, 9, 11] {
            timing.record(latency, false);
        }
        // 13 to 9 is the largest step, and it's a step down.
        assert_eq!(timing.snapshot().max_jitter, 4);
    }

    #[test]
    fn counts_overruns() {
        let timing = LoopTiming::new();
        timing.record(4, false);
        timing.record(4, true);
        timing.record(4, true);
        assert_eq!(
            timing.snapshot(),
            Snapshot {
                ticks: 3,
                overruns: 2,
                max_jitter: 0
            }
        );
    }

    #[test]
    fn converts_counts_to_ns() {
        // At 16 MHz with no prescaler, one period is 16,000 counts.
        assert_eq!(counts_to_ns(16, 16_000), 1_000);
        assert_eq!(counts_to_ns(16_000, 16_000), 1_000_000);
    }
}
