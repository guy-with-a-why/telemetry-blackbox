//! Logic for the STM32F407VG firmware that doesn't touch the hardware.

#![no_std]

/// The control loop runs at this rate.
pub const LOOP_HZ: u32 = 1_000;
