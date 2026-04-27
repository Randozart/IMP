#!/bin/bash
# Build BOOT.BIN for KV260 IMP
# This script requires:
#   - Vivado 2023.1 with Vitis (for FSBL generation)
#   OR
#   - Pre-built fsbl.elf in this directory

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Find Vivado installation
if [ -d "/mnt/data/tools/Xilinx/Vivado/2023.1" ]; then
    VIVADO_DIR="/mnt/data/tools/Xilinx/Vivado/2023.1"
else
    echo "ERROR: Vivado not found"
    exit 1
fi

source "$VIVADO_DIR/settings64.sh" 2>/dev/null || true
export PATH="$VIVADO_DIR/bin:$PATH"

echo "=== KV260 Boot Image Builder ==="
echo "Vivado at: $VIVADO_DIR"
echo ""

# Step 1: Get or build FSBL
if [ -f "fsbl.elf" ]; then
    echo "[1/4] Found fsbl.elf"
elif [ -f "$VIVADO_DIR/data/embeddedsw/boot/fsbl.elf" ]; then
    cp "$VIVADO_DIR/data/embeddedsw/boot/fsbl.elf" fsbl.elf
    echo "[1/4] Copied prebuilt fsbl.elf"
else
    echo "[1/4] FSBL not found!"
    echo ""
    echo "ERROR: fsbl.elf not found and Vitis SDK not installed."
    echo ""
    echo "OPTIONS:"
    echo "  1. Install Vitis (includes ARM toolchain + hsi)"
    echo "  2. Generate FSBL using hsi:"
    echo "     hsi -source create_fsbl.tcl -tclargs <hw_platform>"
    echo "  3. Download prebuilt FSBL for KV260:"
    echo "     https://www.xilinx.com/member/kv260_boot.html"
    echo ""
    echo "For now, using a minimal stub FSBL..."
    
    # Create minimal bootable stub - just jumps to kernel
    cat > /tmp/minimal_fsbl.S << 'ASMEOF'
    .section .boot,"ax"
    .globl _start
    .type _start, %function
_start:
    ldr sp, =0x00100000
    ldr lr, =0x00100000
    ldr pc, =0x00100000
    .align 12
ASMEOF
    
    echo "Note: This stub FSBL will NOT load the kernel from SD."
    echo "Please install Vitis SDK to build proper FSBL."
fi

# Step 2: Check for kernel
if [ ! -f "../arm/kernel.elf" ]; then
    echo "[2/4] kernel.elf not found!"
    echo "  Building ARM kernel..."
    cd ../arm
    cargo build --release --target thumbv7em-none-eabihf 2>/dev/null || \
    cargo build --release --target thumbv6-m-none-eabihf 2>/dev/null || \
    (echo "ERROR: Cannot build kernel. ARM toolchain required." && exit 1)
    cp target/*/release/kernel ../arm/kernel.elf 2>/dev/null || \
    cp target/*/release/*.elf ../arm/kernel.elf 2>/dev/null || true
    cd ../boot
fi

# Step 3: Check bitstream
if [ ! -f "system_wrapper.bit" ]; then
    echo "[3/4] ERROR: system_wrapper.bit not found!"
    echo "  Please generate bitstream in Vivado first"
    exit 1
fi
echo "[3/4] Bitstream found: system_wrapper.bit"

# Step 4: Create BOOT.BIN
echo "[4/4] Creating BOOT.BIN..."

# Create BIF file
cat > boot.bif << 'EOF'
the_ROM_image:
{
    [bootloader]fsbl.elf
    [load=0x00100000]system_wrapper.bit
    [offset=0x100000]../arm/kernel.elf
}
EOF

# Check if fsbl.elf exists
if [ ! -f "fsbl.elf" ]; then
    echo ""
    echo "WARNING: Cannot create BOOT.BIN without fsbl.elf"
    echo ""
    echo "To create fsbl.elf:"
    echo "  1. Install Vitis (includes SDK with ARM toolchain)"
    echo "  2. Run: hsi -source $VIVADO_DIR/scripts/hsm/hsm.tcl"
    echo ""
    echo "Meanwhile, copy this to SD card:"
    echo "  - system_wrapper.bit (for manual FPGA programming)"
    echo "  - kernel.elf (when fsbl is available)"
    exit 1
fi

# Generate BOOT.BIN
bootgen -image boot.bif -w on -o BOOT.BIN -z

echo ""
echo "=== SUCCESS ==="
echo "BOOT.BIN created: $SCRIPT_DIR/BOOT.BIN"
echo ""
echo "SD card layout:"
echo "  /BOOT.BIN"
echo "  /imp/model_9b.isp"
echo "  /imp/feeder.isp"
echo ""
ls -la BOOT.BIN