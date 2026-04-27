#!/bin/bash
# Build standalone FSBL for KV260 (Zynq UltraScale+)
# Uses a minimal approach - no Xilinx BSP required

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=== Building KV260 FSBL ==="

# Check for ARM64 toolchain (A53 is 64-bit)
if ! command -v aarch64-none-elf-gcc &> /dev/null; then
    echo "Installing aarch64-none-elf toolchain..."
    sudo apt install -y gcc-aarch64-none-elf
fi

CC=aarch64-none-elf-gcc
AS=aarch64-none-elf-gcc
AR=aarch64-none-elf-ar
OBJCOPY=aarch64-none-elf-objcopy

# Create minimal linker script
cat > fsbl/lscript_minimal.ld << 'EOF'
MEMORY
{
    DDR (rx) : ORIGIN = 0x00100000, LENGTH = 0x00100000
}

ENTRY(_start)
SECTIONS
{
    .text 0x00100000 : { *(.text) } > DDR
    .data : { *(.data) } > DDR
    .rodata : { *(.rodata) } > DDR
    .bss : { *(.bss) } > DDR
}
EOF

# Create minimal FSBL (just boots and jumps)
cat > fsbl/fsbl_minimal.c << 'EOF'
// Minimal FSBL for KV260 - boots and jumps to kernel
volatile unsigned int *const UART_PTR = (volatile unsigned int *)0xFF000000;
void putstr(const char *s) { while(*s) *UART_PTR = *s++; }
void _start(void) __attribute__((naked));
void _start(void) {
    // Set stack pointer
    __asm__ volatile ("mov sp, #0x00100000");
    
    // Print boot message
    putstr("IMP FSBL v1.0\r\n");
    
    // Load kernel from SD (stub - real implementation uses Xilinx SD driver)
    // For now, just jump to what would be the kernel location
    // The kernel would be at 0x00120000 after FSBL (0x20000 offset)
    
    void (*kernel_entry)(void) = (void (*)(void))0x00120000;
    kernel_entry();
    
    while(1); // Should never return
}
EOF

# Compile minimal FSBL
echo "[1/2] Compiling minimal FSBL..."
cd fsbl
$aarch64-none-elf-gcc -nostdlib -march=armv8-a -DARMA53_64 -O2 -c fsbl_minimal.c -o fsbl_minimal.o

# Assemble entry point
cat > boot.S << 'EOF'
.section .text
.globl _start
.type _start, %function
_start:
    b _start
EOF
$aarch64-none-elf-gcc -march=armv8-a -c boot.S -o boot.o

# Link
echo "[2/2] Linking..."
$aarch64-none-elf-gcc -nostdlib -march=armv8-a -T lscript_minimal.ld -o fsbl_minimal.elf boot.o fsbl_minimal.o

# Copy to parent directory
cp fsbl_minimal.elf ../fsbl.elf
cd ..

echo "=== FSBL built successfully ==="
ls -la fsbl.elf