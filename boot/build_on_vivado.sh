#!/bin/bash
# Create BOOT.BIN using Vivado on your local machine
# 
# Usage: Run this script on your Vivado machine
#   cd imp/boot
#   ./build_on_vivado.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=== KV260 Boot Image Builder ==="
echo ""
echo "This script will create BOOT.BIN for your KV260"
echo ""

# Find Vivado
VIVADO=""
for path in \
    "/mnt/data/tools/Xilinx/Vivado/2023.1" \
    "$HOME/tools/Xilinx/Vivado/2023.1" \
    "/opt/Xilinx/Vivado/2023.1" \
    "/usr/local/Xilinx/Vivado/2023.1"
do
    if [ -d "$path" ]; then
        VIVADO="$path"
        break
    fi
done

if [ -z "$VIVADO" ]; then
    echo "ERROR: Vivado 2023.1 not found"
    echo "Please either:"
    echo "  1. Install Vivado 2023.1"
    echo "  2. Update this script with your Vivado path"
    exit 1
fi

export PATH="$VIVADO/bin:$VIVADO/tps/lnx64/gcc-9.3.0/bin:$PATH"

echo "Found Vivado at: $VIVADO"
echo ""

# Check if FSBL exists
if [ ! -f "fsbl.elf" ]; then
    echo "[1/4] Creating FSBL.elf using Vivado..."
    
    # Create FSBL using hsm
    hsm -xmodel ../imp_kv260.xpr -proc ps_e/fabric ProcessingSystem7 \
        -lang c -app fsbl -swrepo "$VIVADO/data/embeddedsw" \
        -output fsbl.elf
else
    echo "[1/4] FSBL.elf already exists"
fi

# Check if kernel exists
if [ ! -f "../kernel.elf" ]; then
    echo "[2/4] kernel.elf not found!"
    echo "  Please build kernel.rs first:"
    echo "    cd ../arm"
    echo "    cargo build --release --target thumbv7em-none-eabihf"
    echo "    # Convert to ELF if needed"
    exit 1
else
    echo "[2/4] kernel.elf found"
fi

# Check if bitstream exists
if [ ! -f "system_wrapper.bit" ]; then
    echo "[3/4] ERROR: system_wrapper.bit not found!"
    echo "  Please run bitstream generation in Vivado first"
    exit 1
else
    echo "[3/4] Bitstream found"
fi

# Create BIF
echo "[4/4] Creating BIF and BOOT.BIN..."
cat > boot.bif << 'EOF'
the_ROM_image:
{
    [bootloader]fsbl.elf
    [load=0x00100000]system_wrapper.bit
    [offset=0x100000]../kernel.elf
}
EOF

# Generate BOOT.BIN
bootgen -image boot.bif -w on -o BOOT.BIN -z

echo ""
echo "=== SUCCESS ==="
echo "BOOT.BIN created at: $SCRIPT_DIR/BOOT.BIN"
echo ""
echo "Next steps:"
echo "  1. Format SD card as FAT32"
echo "  2. Copy BOOT.BIN to SD card"
echo "  3. Set KV260 boot switch to SD"
echo "  4. Insert SD and power on KV260"
echo ""
ls -la BOOT.BIN