/* IMP Kernel Linker Script for KV260 (Zynq UltraScale+)
 * Binary starts at 0x00100000 with _start as entry point
 * Note: 0x00100000 chosen to avoid overlap with Model Part A
 *
 * COMPILE:
 *   aarch64-linux-gnu-gcc -nostdlib -march=armv8-a -mlittle-endian \
 *       -ffreestanding -O2 -T arm/linker.ld -o kernel.elf kernel.c
 *   aarch64-linux-gnu-objcopy -O binary kernel.elf kernel.bin
 */

OUTPUT_FORMAT("binary")

ENTRY(_start)

SECTIONS
{
    . = 0x00100000;

    .text : {
        *(.text.start)       /* _start FIRST */
        *(.text)
        *(.rodata)
    }

    .bss : {
        __bss_start = .;
        *(.bss)
        __bss_end = .;
    }
}