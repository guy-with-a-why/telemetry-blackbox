//! Firmware for the STM32F407VG.

#![no_std]
#![no_main]

use core::cell::RefCell;

use cortex_m::interrupt::Mutex;
use embassy_stm32::gpio::{Level, Output, Speed};
use embassy_stm32::interrupt::{self, InterruptExt, Priority};
use embassy_stm32::peripherals::TIM3;
use embassy_stm32::time::Hertz;
use embassy_stm32::timer::low_level::{RoundTo, Timer};
use firmware::{LOOP_HZ, LoopTiming};
use panic_halt as _;

/// The loop's timing, for telemetry to read. The name isn't mangled, so
/// Renode's monitor can find it.
#[expect(unsafe_code, reason = "no_mangle is unsafe if two symbols clash")]
#[unsafe(no_mangle)]
static LOOP_TIMING: LoopTiming = LoopTiming::new();

/// What the control loop owns. The timer interrupt takes it once at start-up.
struct ControlLoop {
    timer: Timer<'static, TIM3>,
    led: Output<'static>,
}

static CONTROL_LOOP: Mutex<RefCell<Option<ControlLoop>>> = Mutex::new(RefCell::new(None));

#[embassy_executor::main]
async fn main(_spawner: embassy_executor::Spawner) {
    // The default clocks run the core from the 16 MHz internal oscillator.
    let mut config = embassy_stm32::Config::default();
    // DMA would share the loop's priority by default, so it waits a level below.
    config.dma_interrupt_priority = Priority::P1;
    let p = embassy_stm32::init(config);

    // The Discovery board's green LED is on PD12.
    let led = Output::new(p.PD12, Level::Low, Speed::Low);

    // TIM3 overflows once a millisecond. The prescaler comes from the real
    // timer clock, so changing the clocks keeps the rate.
    let timer = Timer::new(p.TIM3);
    timer.set_frequency(Hertz(LOOP_HZ), RoundTo::Slower);
    timer.generate_update_event();
    timer.enable_update_interrupt(true);

    cortex_m::interrupt::free(|cs| {
        CONTROL_LOOP
            .borrow(cs)
            .replace(Some(ControlLoop { timer, led }));
    });

    // The loop's deadline outranks everything else. embassy-time's TIM2
    // starts at the same top priority, so it moves a level down.
    interrupt::TIM2.set_priority(Priority::P1);
    interrupt::TIM3.set_priority(Priority::P0);
    #[expect(unsafe_code, reason = "unmasking can break a critical section")]
    // SAFETY: the handler only touches CONTROL_LOOP, through its Mutex, and
    // LOOP_TIMING, which is built for a single writer.
    unsafe {
        interrupt::TIM3.enable();
    }

    cortex_m::interrupt::free(|cs| {
        if let Some(control) = CONTROL_LOOP.borrow(cs).borrow().as_ref() {
            control.timer.start();
        }
    });
    // From here the interrupt runs the loop, and the executor sleeps until
    // other tasks have work.
}

/// One tick of the control loop.
#[cortex_m_rt::interrupt]
fn TIM3() {
    cortex_m::interrupt::free(|cs| {
        let mut control = CONTROL_LOOP.borrow(cs).borrow_mut();
        let Some(control) = control.as_mut() else {
            return;
        };
        let regs = control.timer.regs_core();

        // How far the timer has counted since its update event: the time this
        // tick waited to start.
        let latency = u32::from(regs.cnt().read().cnt());
        control.timer.clear_update_interrupt();

        // The work of the loop goes here. For now it blinks the LED at 1 Hz.
        if LOOP_TIMING.snapshot().ticks.is_multiple_of(LOOP_HZ / 2) {
            control.led.toggle();
        }

        // If the timer has overflowed again, this tick missed its deadline.
        let overran = regs.sr().read().uif();
        LOOP_TIMING.record(latency, overran);
    });
}
