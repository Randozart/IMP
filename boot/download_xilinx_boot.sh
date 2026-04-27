#!/bin/bash
# Download Xilinx KV260 prebuilt boot files and inject our bitstream
set -e

BOOT_DIR=$HOME/Desktop/Projects/imp/boot
VIVADO_DIR=/mnt/data/tools/Xilinx/Vivado/2023.1
TMP_DIR=/tmp/kv260_boot

mkdir -p $TMP_DIR
cd $TMP_DIR

echo "=== Downloading KV260 Prebuilt Boot Files ==="

# Download from Xilinx (BOM file contains links)
BOOT_URL="https://www.xilinx.com/member/kv260/kv260_sg_1_4.zip"
BOOT_URL_ALT="https://www.xilinx.com/content/dam/xilinx/support/sn/2021.2/xtp660-kv260-rfm-sg1.zip"

echo "Downloading KV260 boot files..."
if command -v wget &> /dev/null; then
    wget -O kv260_boot.zip "$BOOT_URL" 2>/dev/null || \
    wget -O kv260_boot.zip "$BOOT_URL_ALT" 2>/dev/null || \
    curl -L -o kv260_boot.zip "$BOOT_URL" 2>/dev/null
else
    curl -L -o kv260_boot.zip "$BOOT_URL" 2>/dev/null || \
    curl -L -o kv260_boot.zip "$BOOT_URL_ALT" 2>/dev/null
fi

if [ -f kv260_boot.zip ]; then
    echo "Extracting..."
    unzip -o kv260_boot.zip -d kv260_prebuilt
    ls -la kv260_prebuilt/
else
    echo "Download failed - trying alternate method"
fi