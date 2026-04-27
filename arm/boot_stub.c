// IMP Kernel Boot Stub for Bare-Metal ARM
// Sets up stack, calls main, halts if returns
//
// COMPILE: aarch64-linux-gnu-gcc -nostdlib -static -march=armv8-a -ffreestanding -O2 -Wl,-Ttext=0x00100000 kernel.c boot_stub.o -o kernel.elf

void _start(void) __attribute__((section(".text.start")));
void _start(void) {
    extern void main(void);

    // Call main
    main();

    // Should never return - halt
    while (1) {
        __asm__ volatile ("wfi");
    }
}
