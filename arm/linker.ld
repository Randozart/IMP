/* IMP Kernel Linker Script for KV260
 * Loads at 0x00120000 where U-Boot expects kernel
 */

MEMORY
{
    /* Code - 128KB from 0x00120000 */
    RAM (rwx) : ORIGIN = 0x00120000, LENGTH = 0x20000
    
    /* Stack - below code */
    STACK : ORIGIN = 0x00140000, LENGTH = 0x1000
}

ENTRY(_start)

SECTIONS
{
    .text : {
        *(.text.start)
        *(.text)
        *(.rodata)
    } > RAM

    .data : {
        *(.data)
    } > RAM

    .bss : {
        __bss_start = .;
        *(.bss)
        __bss_end = .;
    } > RAM

    .stack : {
        *(.stack)
    } > STACK
}