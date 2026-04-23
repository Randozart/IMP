/* IMP Memory Layout for KV260 - ARM Cortex-A53
 *     Copyright (C) 2026 Randy Smits-Schreuder Goedheijt
 *
 * Linker script for KV260 DDR4 at 0x00000000 (2GB)
 * ARM code runs from DDR4, not FPGA BRAM
 */

MEMORY
{
    /* DDR4 Memory - 2GB starting at 0x00000000 */
    /* Note: 0x8000A000 is FPGA MMIO, NOT a code storage address */
    DDR4 (rwx) : ORIGIN = 0x00000000, LENGTH = 0x80000000

    /* FPGA BRAM - 518KB at 0x40A80000 */
    /* This is for FPGA weights, NOT ARM code */
    BRAM (rw)  : ORIGIN = 0x40A80000, LENGTH = 0x00080000
}

ENTRY(_start)

SECTIONS
{
    .text 0x00000000 : {
        *(.text.start)
        *(.text)
        *(.rodata)
    } > DDR4

    .data : {
        *(.data)
    } > DDR4

    .bss : {
        *(.bss)
    } > DDR4

    /* Stack at end of DDR4 */
    .stack (ORIGIN DDR4 + LENGTH DDR4 - 0x10000) : {
        *(.stack)
    }
}