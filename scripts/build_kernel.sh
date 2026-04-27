#!/bin/bash
################################################################################
# IMP Kernel Build Script
# Compiles kernel for KV260 and extracts raw binary
#
# Usage: ./build.sh
#
# Output: 
#   arm/kernel.elf  - ELF executable (for U-Boot bootelf)
#   arm/kernel.bin  - Raw binary (for U-Boot go command)
################################################################################

set -e

echo "========================================"
echo "IMP Kernel Build Script"
echo "========================================"
echo ""

TARGET=aarch64-linux-gnu
PREFIX=$TARGET
CC=${PREFIX}-gcc
OBJCOPY=${PREFIX}-objcopy
OBJDUMP=${PREFIX}-objdump

# Paths
SRC_DIR=arm
BUILD_DIR=$SRC_DIR/build
OUT_ELF=$SRC_DIR/kernel.elf
OUT_BIN=$SRC_DIR/kernel.bin

# Source files
KERNEL_SRC=$SRC_DIR/kernel.c
LINKER_SCRIPT=$SRC_DIR/linker.ld

echo "[1/4] Checking toolchain..."
if ! command -v $CC &> /dev/null; then
    echo "ERROR: $CC not found"
    echo "Install with: apt install gcc-aarch64-linux-gnu"
    exit 1
fi
echo "  Using: $CC"
echo "  Using: $OBJCOPY"
echo ""

echo "[2/4] Compiling kernel..."
$CC -nostdlib \
    -march=armv8-a \
    -ffreestanding \
    -O2 \
    -fno-stack-protector \
    -fno-pie \
    -T $LINKER_SCRIPT \
    -Wl,--entry=_start \
    -Wl,--defsym=_start=0x20000000 \
    -o $OUT_ELF \
    $KERNEL_SRC

echo "  Built: $OUT_ELF"
ls -lh $OUT_ELF
echo ""

echo "[3/4] Extracting raw binary..."
$OBJCOPY -O binary $OUT_ELF $OUT_BIN

echo "  Built: $OUT_BIN"
ls -lh $OUT_BIN
echo ""

echo "[4/4] Verifying binary header..."
xxd -l 16 $OUT_BIN
echo ""

echo "========================================"
echo "Build complete!"
echo "========================================"
echo ""
echo "To deploy on SD card:"
echo "  1. Copy kernel.bin to SD card (FAT partition)"
echo "  2. Load with: fatload mmc 1:1 0x20000000 imp/kernel.bin"
echo "  3. Execute with: go 0x20000000"
echo ""