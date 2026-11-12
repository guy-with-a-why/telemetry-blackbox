//! Firmware for the STM32F407VG. Day 1 turns this into an Embassy binary.

#![no_std]

/// The control loop runs at this rate.
pub const LOOP_HZ: u32 = 1_000;
