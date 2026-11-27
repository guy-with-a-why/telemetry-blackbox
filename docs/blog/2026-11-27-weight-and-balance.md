# Weight and balance: what sits where on the F407

*27 November 2026*

## Where everything sits

The linker writes this firmware's load sheet. `llvm-size` on the release build
puts 4,808 bytes in flash, out of 1 MB. That's the vector table, the code, the constants and a copy of the
statics' starting values. RAM holds 112 bytes of statics, and the rest of it is
stack.

The Cortex-M4 sees one flat 4 GB address space, and the [ARMv7-M
architecture](https://developer.arm.com/documentation/ddi0403/latest/) fixes its
rough shape. Code sits low, SRAM from `0x2000_0000`, peripherals from
`0x4000_0000` and the core's own registers (the NVIC, SysTick and the MPU) from
`0xE000_0000`.
[RM0090](https://www.st.com/resource/en/reference_manual/rm0090-stm32f405415-stm32f407417-stm32f427437-and-stm32f429439-advanced-armbased-32bit-mcus-stmicroelectronics.pdf)
fills in the F407. Flash starts at `0x0800_0000`. SRAM1 (112 KB) and SRAM2
(16 KB) sit back to back from `0x2000_0000`, so `memory.x` treats them as one
128 KB block. Just below `0x2000_0000` sit the ROM bootloader and the option
bytes, which hold the chip's protection settings.

The odd one out is 64 KB of core-coupled memory (CCM) at `0x1000_0000`. It hangs
off the core's data bus, outside the bus matrix that links the DMA controllers
to memory, so only the core can reach it. That's why `memory.x` leaves it out.
The telemetry in [#6](https://github.com/guy-with-a-why/telemetry-blackbox/issues/6)
needs DMA buffers, and the simplest rule is that every static lives where DMA
can see it. Moving the stack there would give it a hard floor, since anything
below `0x1000_0000` is reserved and faults, but it would have half the room.

![The STM32F407VG's 4 GB address space, from the top: the private peripheral bus at 0xE000_0000 with the NVIC, SCB, SysTick and MPU; peripherals at 0x4000_0000; SRAM1 and SRAM2 at 0x2000_0000, reachable by the core and DMA; the option bytes at 0x1FFF_C000; the ROM bootloader and OTP at 0x1FFF_0000; CCM RAM at 0x1000_0000, reachable by the core only; flash at 0x0800_0000 with 4,808 bytes used; and the boot alias at 0x0000_0000. Beside it, SRAM as this firmware fills it: the initial stack pointer at 0x2002_0000, 130,960 bytes of stack growing down, __sheap at 0x2000_0070 with no heap, LOOP_TIMING at 0x2000_0058 outlined in red as the first thing an overflow overwrites, then CONTROL_LOOP, Embassy's task pool and .data.](../diagrams/memory-map.svg)

There's no heap. Nothing in the firmware allocates, and `__sheap` at
`0x2000_0070` only marks where one would start. Every byte has its place at link time.

## From reset to main

The BOOT0 pin is low at reset, so flash is aliased at `0x0000_0000`. The core
reads two words from there before it runs a single instruction. Word 0 is the
initial stack pointer, `0x2002_0000`, the top of SRAM. Word 1 is the reset
vector, `0x0800_0189`, though `Reset` starts at `0x0800_0188`. The extra 1 is
the Thumb bit. A Cortex-M only runs Thumb code, so every handler address has bit 0 set,
and one without it faults on the spot. The table is 98 words long: the stack
pointer, 15 system exception slots and the F407's 82 interrupts.

Reset doesn't clear SRAM. Whatever the last run left is still there, so
[cortex-m-rt](https://docs.rs/cortex-m-rt/0.7.7/cortex_m_rt/)'s `Reset` does
the housekeeping before any Rust runs. It zeroes `.bss`, copies `.data` from its
image in flash, enables the FPU and calls `main`. A static that starts at zero
costs no flash. One that starts at anything else is paid for twice, in flash and
in RAM.

## The stack and the exception frame

The stack grows down from `0x2002_0000`, and nothing below it stops it. It has
130,960 bytes before it reaches the statics. The first static in its path is
`LOOP_TIMING` at `0x2000_0058`, the counters that prove the loop keeps its
deadline. The stack just keeps writing, because to the core it's ordinary RAM.

Every interrupt adds weight. On entry the core pushes eight words onto the
current stack: R0 to R3, R12, LR, the return address and xPSR. That's 32 bytes
per preemption. Once the attitude estimate in
[#5](https://github.com/guy-with-a-why/telemetry-blackbox/issues/5) runs float
code, an interrupt that preempts it can push 18 more words (S0 to S15, FPSCR
and a reserved word) for 104 bytes in all. [Lazy stacking](https://developer.arm.com/documentation/dai0298/a)
keeps that cheap. The core reserves the space and notes its address in FPCAR,
but only writes the registers if the handler touches the FPU itself. The value
the core leaves in LR, `EXC_RETURN`, tells the return which frame it pushed. Bit
4 clear means the long one.

So the return address is just a word in SRAM, next to everything else. That's
worth a drill. On a throwaway branch, I made the firmware dive down the stack
once the Discovery's blue button is pressed. Each 32-byte frame carries 16
bytes of `0xAA`, and the dive stops at the first frame whose `0xAA` bytes sit
below the start of `LOOP_TIMING`. Interrupts
stay masked during the dive, so no tick lands halfway.

![just fly boots the drill build in Renode. runMacro $timing shows 3,958 and then 6,857 ticks with no overruns, while the green LED log toggles every half second. After gpioPortA.UserButton Press the LED log stops. The next two runs of runMacro $timing both show 10,361 ticks, 2,863,311,530 overruns, 2,863,311,530 missed and a max jitter of 178,956,970,625 ns.](assets/2026-11-27-stack-dive.gif)

The LED stopped blinking the moment the button went down. The counters now
report 2,863,311,530 overruns, which is `0xAAAAAAAA`, and a worst jitter of 179
seconds. `last_release_us` holds `0x2000_005C`, the address of that frame's own
`0xAA` bytes. The word just above `.bss` holds `0x0800_047D`, a return address
back into the dive. The loop died because
the overflow went one step further. `CONTROL_LOOP`'s `RefCell` borrow flag, 12
bytes below the counters, took the next frame's buffer address. The next tick's
`borrow_mut` read it as borrowed and panicked, and `panic-halt` spins inside
TIM3 at P0, so nothing runs again. The flight recorder's own counters were the
first casualty, which isn't a great look for a flight recorder.

## Who can touch what

Everything in this firmware runs privileged, on the main stack, with the MPU
off. The core's [default memory map](https://developer.arm.com/documentation/dui0553/latest/)
marks SRAM as executable, so bytes the stack writes could run as
code. The MPU can change that. It has eight regions, each a power of two from 32
bytes and aligned to its size. One region can make SRAM execute-never, and
another can turn the bottom of the stack into a guard. An access the MPU
forbids raises a MemManage fault.

The MPU sits inside the core, so it only judges the core's own accesses. The DMA
controllers are separate masters on the bus matrix, and a transfer aimed at the
wrong address writes there anyway. That matters for
[#6](https://github.com/guy-with-a-why/telemetry-blackbox/issues/6). A UART DMA
buffer is memory that something other than the core writes, behind the
compiler's back.

The chip has guards of its own in the option bytes. The Discovery ships at read
protection Level 0, where SWD can read and write everything. At Level 1, flash
and backup SRAM are blocked while a debugger is connected or the chip boots
from RAM or the ROM bootloader, and dropping back to Level 0 mass-erases both.
Level 2 is permanent. It switches off the debug port, SWD and JTAG alike, along
with trace. It stops booting from RAM or the bootloader and freezes the option
bytes, so nothing can lower it again.
Write protection works per flash sector, with one bit for each of the twelve.

## What Rust covers and what it doesn't

The firmware denies `unsafe_code`, with two marked exceptions: an unmangled
symbol so Renode can find `LOOP_TIMING`, and unmasking TIM3 in the NVIC.
The borrow checker guards every reference the core holds, and the PAC reaches
registers through volatile accesses.

It doesn't cover the stack's depth. The dive above is safe Rust.
`thumbv7em-none-eabihf` has no guard page and no stack probes, so recursion or
one large local is enough to write over statics with no `unsafe` in sight. The
borrow checker can't see the DMA engine either, or what a register write does
to the hardware.

## What's next

[#5](https://github.com/guy-with-a-why/telemetry-blackbox/issues/5) puts float
work in the tick. Whenever TIM3 preempts code that has used the FPU, it reserves
the long frame, and the tick's float work fills it.
[#6](https://github.com/guy-with-a-why/telemetry-blackbox/issues/6) keeps its DMA
buffers in `'static` SRAM, never on the stack and never in CCM.

The biggest risk is the one the drill showed. An overflow corrupts state
quietly and leaves the counters lying. A guard lands before
[#6](https://github.com/guy-with-a-why/telemetry-blackbox/issues/6) adds tasks. My
first choice is [flip-link](https://github.com/knurling-rs/flip-link). It puts
the stack below the statics, so an overflow runs off the bottom of SRAM into
reserved space and faults. It spends no MPU region either. The fallback is an
MPU guard region. That costs one of the eight, and a frame bigger than 32 bytes
can step clean over it. The bus fault flip-link relies on is the silicon's to
raise, so the guard is proved on real hardware.

## Further reading

- [RM0090](https://www.st.com/resource/en/reference_manual/rm0090-stm32f405415-stm32f407417-stm32f427437-and-stm32f429439-advanced-armbased-32bit-mcus-stmicroelectronics.pdf),
  chapters 2 and 3: the memory map, boot aliasing, the flash and its option
  bytes.
- Arm's [Cortex-M4 Devices Generic User Guide](https://developer.arm.com/documentation/dui0553/latest/):
  the default memory map, the exception frame, `EXC_RETURN` and the MPU in one
  place.
- [AN298](https://developer.arm.com/documentation/dai0298/a), Cortex-M4(F) lazy
  stacking: how the long frame is reserved and when it's filled.
- [AN5156](https://www.st.com/resource/en/application_note/an5156-introduction-to-security-for-stm32-mcus-stmicroelectronics.pdf),
  security for STM32 MCUs: ST's own map of read protection, write protection and
  the rest.
- [AN4838](https://www.st.com/resource/en/application_note/an4838-introduction-to-memory-protection-unit-management-on-stm32-mcus-stmicroelectronics.pdf),
  the MPU on STM32: regions, attributes and worked examples.
- The Embedonomicon on [memory layout](https://docs.rust-embedded.org/embedonomicon/memory-layout.html)
  and [DMA](https://docs.rust-embedded.org/embedonomicon/dma.html): the linker
  script, and a memory-safe DMA API built from first principles.
- Memfault on [debugging a HardFault](https://interrupt.memfault.com/blog/cortex-m-fault-debug)
  and [the MPU](https://interrupt.memfault.com/blog/fix-bugs-and-secure-firmware-with-the-mpu):
  reading a fault from the stacked frame, and a guard region in practice.
- Obermaier and Tatschner,
  [Shedding too much Light on a Microcontroller's Firmware Protection](https://www.usenix.org/conference/woot17/workshop-program/presentation/obermaier):
  how read protection on a sibling STM32 holds up with the board in someone
  else's hands.

## Quiz

The questions this post set out to answer. Open one for my answer.

<details>
<summary>Why does memory.x leave out the CCM, and what would moving the stack
there gain and lose?</summary>

DMA can't reach it. The stack there would fault on overflow below
`0x1000_0000`, with half the room.

</details>

<details>
<summary>What two words does the core read first, and why is the second one
odd? Who sets up .data and .bss?</summary>

The initial stack pointer, `0x2002_0000`, and the reset vector, `0x0800_0189`.
Bit 0 marks Thumb code. Reset doesn't clear SRAM, so cortex-m-rt zeroes `.bss`
and copies `.data` from its image in flash.

</details>

<details>
<summary>What does the stack run into first, and why is the overflow
silent?</summary>

`LOOP_TIMING` at `0x2000_0058`, the top of `.bss`. It's ordinary RAM with no
guard page or MPU region, so every write succeeds.

</details>

<details>
<summary>What does TIM3 push when it preempts float code, and what does lazy
stacking save?</summary>

The eight basic words plus 18 for the float registers, 104 bytes. Lazy stacking
reserves the float space and only fills it if the handler uses the FPU.

</details>

<details>
<summary>Why did the loop stop dead instead of counting nonsense?</summary>

The dive also overwrote `CONTROL_LOOP`'s `RefCell` borrow flag. The next tick's
`borrow_mut` panicked, and `panic-halt` spins in TIM3 at P0, so nothing runs
again.

</details>

<details>
<summary>How can safe Rust write over LOOP_TIMING?</summary>

By overflowing the stack. This target has no guard page or stack probes, and the
dive was safe code.

</details>

<details>
<summary>What are two ways to make an overflow fault, and why won't the MPU stop
a stray DMA transfer?</summary>

flip-link moves the stack below the statics and spends no MPU region. An MPU guard costs one of eight regions, and a big frame can jump it. The
MPU only checks the core's accesses, and DMA is a separate bus master.

</details>

<details>
<summary>What does read protection Level 1 change for a debugger on SWD, and why
is Level 2 a one-way door?</summary>

With a debugger attached, flash and backup SRAM are blocked, and
dropping to Level 0 mass-erases them. Level 2 switches off the debug port, SWD
included, and freezes the option bytes, so nothing can lower it.

</details>
