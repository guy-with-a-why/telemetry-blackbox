/* The STM32F407VG memory map, from RM0090 section 2.3. */
MEMORY
{
  /* Code and constants. The core boots from here, vector table first. */
  FLASH : ORIGIN = 0x08000000, LENGTH = 1024K
  /* SRAM1 and SRAM2, contiguous. DMA can reach it, so it holds everything.
     The 64K of CCM RAM at 0x10000000 is left out: DMA can't reach it. */
  RAM   : ORIGIN = 0x20000000, LENGTH = 128K
}
