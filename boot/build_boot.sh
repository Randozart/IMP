#!/bin/bash
# Build BOOT.BIN for KV260 IMP
# Run this on your Vivado machine

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Find Vivado installation
if [ -d "/mnt/data/tools/Xilinx/Vivado/2023.1" ]; then
    VIVADO_DIR="/mnt/data/tools/Xilinx/Vivado/2023.1"
elif [ -d "$HOME/Xilinx/Vivado/2023.1" ]; then
    VIVADO_DIR="$HOME/Xilinx/Vivado/2023.1"
elif [ -d "/opt/Xilinx/Vivado/2023.1" ]; then
    VIVADO_DIR="/opt/Xilinx/Vivado/2023.1"
else
    echo "ERROR: Vivado 2023.1 not found. Please install or update paths."
    exit 1
fi

export PATH="$VIVADO_DIR/bin:$VIVADO_DIR/tps/lnx64/gcc-9.3.0/bin:$PATH"

echo "=== Building BOOT.BIN for KV260 ==="

# Step 1: Create FSBL
echo "[1/4] Building FSBL..."
cd fsbl
make clean 2>/dev/null || true
make COMPILER=arm-none-eabi-gcc ARCHIVER=arm-none-eabi-ar OS=freertos PART=xc7z045
mv fsbl.elf ..
cd ..

# Step 2: Check for kernel ELF
if [ ! -f "kernel.elf" ]; then
    echo "[2/4] kernel.elf not found - building from ARM source..."
    cd arm
    cargo build --release --target thumbv7em-none-eabihf
    # Convert to ELF format if needed
    mv target/thumbv7em-none-eabihf/release/kernel kernel.elf
    cd ..
fi

# Step 3: Create BIF file
cat > boot/boot.bif << 'EOF'
the_ROM_image:
{
    [bootloader]fsbl.elf
    [load=0x00100000]boot/system_wrapper.bit
    [offset=0x100000]kernel.elf
}
EOF

# Step 4: Build BOOT.BIN
echo "[4/4] Creating BOOT.BIN..."
bootgen -image boot.bif -w on -o BOOT.BIN -z

echo "=== BOOT.BIN created successfully ==="
echo "Flash BOOT.BIN to SD card (FAT32 partition) and boot KV260"
ls -la BOOT.BIN