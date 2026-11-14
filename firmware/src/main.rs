//! Firmware for the STM32F407VG.

#![no_std]
#![no_main]

use embassy_stm32::gpio::{Level, Output, Speed};
use embassy_time::Timer;
use panic_halt as _;

#[embassy_executor::main]
async fn main(_spawner: embassy_executor::Spawner) {
    // The default config runs the core from the 16 MHz internal oscillator.
    let p = embassy_stm32::init(Default::default());

    // The Discovery board's green LED is on PD12.
    let mut led = Output::new(p.PD12, Level::Low, Speed::Low);

    loop {
        led.toggle();
        Timer::after_millis(500).await;
    }
}
