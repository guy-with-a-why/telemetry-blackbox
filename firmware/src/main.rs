//! Firmware for the STM32F407VG.

#![no_std]
#![no_main]

use panic_halt as _;

#[embassy_executor::main]
async fn main(_spawner: embassy_executor::Spawner) {
    let _p = embassy_stm32::init(Default::default());
    core::future::pending::<()>().await;
}
