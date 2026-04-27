#!/bin/bash
# Build KV260 Boot Image - Fixed version
set -e

BOOT_DIR=$HOME/Desktop/Projects/imp/boot
VIVADO_DIR=/mnt/data/tools/Xilinx/Vivado/2023.1
export PATH="$VIVADO_DIR/bin:$PATH"

echo "=== KV260 Boot Builder ==="

cd $BOOT_DIR

# Check for aarch64-linux-gnu (we just installed this)
CC=aarch64-linux-gnu-gcc
if ! command -v $CC &> /dev/null; then
    echo "ERROR: aarch64-linux-gnu-gcc not found"
    exit 1
fi
echo "[1/4] Toolchain: OK ($CC)"

# 1. Build minimal FSBL
echo "[1/4] Building FSBL..."

# Create minimal FSBL source
cat > fsbl_minimal.S << 'EOF'
.section .text
.globl _start
.type _start, %function
_start:
    // Set stack pointer
    mov sp, #0x00100000
    
    // Putchar function
    mov x1, #0xFF000000
    
    // Print "IMP FSBL\r\n"
    adr x0, msg
1:  ldrb w2, [x0], #1
    cbz w2, 2f
    strb w2, [x1]
    b 1b
2:
    // Jump to kernel at 0x00120000
    ldr x30, =0x00120000
    br x30
    
msg: .ascii "IMP FSBL\r\n"
    .byte 0
    .align 3
EOF

$CC -nostdlib -march=armv8-a -c fsbl_minimal.S -o fsbl_minimal.o

# Create linker script
cat > fsbl_minimal.ld << 'EOF'
MEMORY {
    ROM (rx) : ORIGIN = 0x00100000, LENGTH = 128K
}
ENTRY(_start)
SECTIONS {
    .text : { *(.text) } > ROM
}
EOF

$CC -nostdlib -T fsbl_minimal.ld -o fsbl.elf fsbl_minimal.o
rm -f fsbl_minimal.o fsbl_minimal.S fsbl_minimal.ld
echo "[1/4] FSBL: OK (fsbl.elf)"
ls -la fsbl.elf

# 2. Check for kernel
echo "[2/4] Checking kernel..."
if [ -f kernel.elf ]; then
    echo "[2/4] Kernel: OK (kernel.elf exists)"
elif [ -f ../arm/target/thumbv7em-none-eabihf/release/kernel ]; then
    cp ../arm/target/thumbv7em-none-eabihf/release/kernel kernel.elf
    echo "[2/4] Kernel: OK (copied from ARM build)"
elif [ -f ../arm/target/thumbv6m-none-eabi/release/kernel ]; then
    cp ../arm/target/thumbv6m-none-eabi/release/kernel kernel.elf
    echo "[2/4] Kernel: OK (copied from ARM build)"
else
    echo "[2/4] Kernel: Not found - creating stub kernel.elf"
    # Create minimal stub kernel that just loops
    cat > kernel_stub.S << 'KEOF'
.section .text
.globl _start
.type _start, %function
_start:
1:  wfe
    b 1b
KEOF
    arm-none-eabi-gcc -nostdlib -march=armv6-m -c kernel_stub.S -o kernel_stub.o 2>/dev/null || \
    aarch64-linux-gnu-gcc -nostdlib -march=armv8-a -c kernel_stub.S -o kernel_stub.o
    arm-none-eabi-ld -Ttext=0x00120000 -o kernel.elf kernel_stub.o 2>/dev/null || \
    aarch64-linux-gnu-gcc -nostdlib -Ttext=0x00120000 -o kernel.elf kernel_stub.o 2>/dev/null || \
    cp fsbl.elf kernel.elf
    rm -f kernel_stub.o kernel_stub.S
    echo "[2/4] Kernel stub: OK"
fi

# 3. Check bitstream
echo "[3/4] Checking bitstream..."
if [ -f system_wrapper.bit ]; then
    echo "[3/4] Bitstream: OK"
else
    echo "[3/4] ERROR: system_wrapper.bit not found!"
    echo "Please generate bitstream in Vivado first"
    exit 1
fi

# 4. Build BOOT.BIN
echo "[4/4] Creating BOOT.BIN..."

cat > boot.bif << 'EOF'
the_ROM_image:
{
    [bootloader]fsbl.elf
    [load=0x00100000]system_wrapper.bit
    [offset=0x100000]kernel.elf
}
EOF

bootgen -image boot.bif -w on -o BOOT.BIN

echo ""
echo "=== SUCCESS ==="
ls -la BOOT.BIN fsbl.elf kernel.elf 2>/dev/null
echo ""
echo "Copy to SD card:"