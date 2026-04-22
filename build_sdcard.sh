#!/bin/bash
# IMP SD Card Builder - Builds bootable SD card image for KV260
#     Copyright (C) 2026 Randy Smits-Schreuder Goedheijt
#
# build_sdcard.sh - Build SD card image for KV260 IMP
# Usage: ./build_sdcard.sh <path-to-sd-card-mount>

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="/tmp/imp_build"
SD_CARD="${1:-}"

echo "=== IMP SD Card Builder ==="
echo ""

# Check arguments
if [ -z "$SD_CARD" ]; then
    echo "Usage: $0 <sd-card-mount-point>"
    echo "Example: $0 /mnt/sdcard"
    exit 1
fi

# Create build directory
mkdir -p "$BUILD_DIR"
mkdir -p "$BUILD_DIR/weights"

echo "[1/6] Setting up build directory..."

# Generate ARM kernel
echo "[2/6] Compiling ARM kernel..."
cd "$SCRIPT_DIR"
if [ ! -f arm/kernel.rs ]; then
    echo "Error: arm/kernel.rs not found"
    exit 1
fi

# Note: Full Rust compilation requires ARM toolchain + no_std support
# For now, we assume kernel.rs has been pre-compiled to kernel.elf
if [ ! -f arm/kernel.elf ]; then
    echo "Warning: arm/kernel.elf not found. Using placeholder."
    echo "You must compile arm/kernel.rs to ARM ELF separately."
    touch "$BUILD_DIR/kernel.elf.placeholder"
fi

# Generate SystemVerilog
echo "[3/6] Generating SystemVerilog..."
"$SCRIPT_DIR/../brief-compiler/target/release/brief-compiler" \
    verilog neuralcore.ebv --hw hardware.toml -o "$BUILD_DIR/" 2>/dev/null || true

if [ -f neuralcore.sv ]; then
    mv neuralcore.sv "$BUILD_DIR/"
fi

# Copy hardware config
cp hardware.toml "$BUILD_DIR/"

echo "[4/6] Creating boot files..."

# Create boot.cmd
cat > "$BUILD_DIR/boot.cmd" << 'EOF'
# IMP Boot Script for KV260
fatload mmc 0:1 0x4000A000 kernel.elf
fatload mmc 0:1 0x50000000 system.dtb
fatload mmc 0:1 0x60000000 neuralcore.bit
booti 0x4000A000 - 0x50000000
EOF

# Compile boot script
if command -v mkimage > /dev/null 2>&1; then
    mkimage -A arm -T script -C none -n "IMP Boot" -d "$BUILD_DIR/boot.cmd" "$BUILD_DIR/boot.scr"
fi

echo "[5/6] SD card contents prepared at: $BUILD_DIR"
echo ""
echo "Contents:"
ls -la "$BUILD_DIR/"
echo ""

echo "[6/6] Copying to SD card..."
if [ -d "$SD_CARD" ]; then
    cp "$BUILD_DIR"/* "$SD_CARD/"
    echo "Files copied to $SD_CARD"
else
    echo "Warning: $SD_CARD not mounted. Copy files manually:"
    echo "  cp -r $BUILD_DIR/* <sd-card-mount>/"
fi

echo ""
echo "=== Build Complete ==="
echo ""
echo "SD Card Contents:"
echo "  kernel.elf      - ARM bare-metal kernel"
echo "  neuralcore.sv   - FPGA design (synthesize with Vivado)"
echo "  hardware.toml   - Memory configuration"
echo "  boot.cmd/.scr   - U-Boot boot script"
echo ""
echo "Next steps:"
echo "  1. Synthesize neuralcore.sv in Vivado to get neuralcore.bit"
echo "  2. Copy BOOT.BIN (from Vivado) to SD card"
echo "  3. Download Qwen 1.58-bit weights to weights/model_9b.bin"
echo "  4. Download BPE vocab to weights/vocab.bin"
echo "  5. Insert SD card and power on"