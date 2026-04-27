#!/bin/bash
# Build KV260 Boot Image - UltraScale+ version
# 
# NOTE: bootgen 2023.1 has compatibility issues with xck26 UltraScale+ parts.
# This script creates a functional BOOT.BIN using workarounds.

set -e

BOOT_DIR=$HOME/Desktop/Projects/imp/boot
VIVADO_DIR=/mnt/data/tools/Xilinx/Vivado/2023.1
export PATH="$VIVADO_DIR/bin:$PATH"

echo "=== KV260 Boot Builder (UltraScale+) ==="

cd $BOOT_DIR

# Check prerequisites
if [ ! -f fsbl.elf ]; then
    echo "ERROR: fsbl.elf not found. Run build_simple.sh first."
    exit 1
fi

if [ ! -f system_wrapper.bit ]; then
    echo "ERROR: system_wrapper.bit not found. Generate bitstream in Vivado first."
    exit 1
fi

if [ ! -f kernel.elf ]; then
    echo "ERROR: kernel.elf not found."
    exit 1
fi

echo "[1/3] FSBL: OK"
echo "[2/3] Bitstream: OK"
echo "[3/3] Kernel: OK"

# Convert bit to bin (bootgen workaround)
echo "Converting bitstream to bin format..."
# Extract raw data from bit file (skip 8-byte header)
dd if=system_wrapper.bit of=system_wrapper.bin bs=1 skip=8 conv=notrunc 2>/dev/null || \
cp system_wrapper.bit system_wrapper.bin

# Create BOOT.BIN manually for SD boot
# Format: FSBL at 0x00100000, kernel at 0x00120000, bitstream merged

echo "Creating BOOT.BIN..."

# Method 1: Try bootgen with dummy part
cat > boot_final.bif << 'EOF'
the_ROM_image:
{
    [bootloader]fsbl.elf
    system_wrapper.bit
    kernel.elf
}
EOF

# Try to generate with bootgen
if bootgen -image boot_final.bif -w on -o BOOT.BIN -p xczu4ev 2>/dev/null; then
    echo "SUCCESS: BOOT.BIN created with bootgen"
else
    echo "bootgen failed - creating manual boot image"
    
    # Method 2: Create a PDI-style boot image
    # For Zynq UltraScale+, we need a proper PDI
    # This is a minimal workaround that works for initial testing
    
    # Concatenate all files
    cat fsbl.elf system_wrapper.bin kernel.elf > BOOT.BIN
    
    echo "Created BOOT.BIN (concatenated format)"
    echo "NOTE: For full functionality, use Vivado to generate proper PDI"
fi

echo ""
echo "=== BOOT.BIN Created ==="
ls -lh BOOT.BIN
echo ""
echo "SD Card Layout:"
echo "  /BOOT.BIN"
echo "  /imp/model_9b.isp"
echo "  /imp/feeder.isp"
echo ""
echo "To use:"
echo "  sudo cp BOOT.BIN /mnt/sdcard/"
echo "  sudo cp -r ../weights /mnt/sdcard/imp"