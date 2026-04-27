#!/bin/bash
################################################################################
# IMP PetaLinux Build & Deploy Script
# Builds PetaLinux and prepares SD card for KV260
#
# Prerequisites:
#   - PetaLinux 2023.2 installed at ~/petalinux
#   - KV260 BSP downloaded
#   - HDF/XSA file from Vivado (or use pre-built platform)
#
# Usage: ./build_and_deploy.sh [OPTIONS]
#
# Options:
#   --skip-build      Skip PetaLinux build (use existing images)
#   --skip-sd         Skip SD card preparation
#   --sd-device /dev/sdX  SD card device
################################################################################

set -e

# Configuration
PETALINUX_DIR="$HOME/petalinux"
PROJECT_NAME="imp-platform"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR=""

# Parse arguments
SKIP_BUILD=0
SKIP_SD=0
SD_DEVICE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-build)
            SKIP_BUILD=1
            shift
            ;;
        --skip-sd)
            SKIP_SD=1
            shift
            ;;
        --sd-device)
            SD_DEVICE="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

echo "========================================"
echo "IMP PetaLinux Build & Deploy Script"
echo "========================================"
echo ""

# Step 1: Check environment
echo "[1/7] Checking environment..."

if [ ! -d "$PETALINUX_DIR" ]; then
    echo "ERROR: PetaLinux not found at $PETALINUX_DIR"
    echo "Please install PetaLinux first or update PETALINUX_DIR"
    exit 1
fi

source "$PETALINUX_DIR/settings.sh"

if ! command -v petalinux-build &> /dev/null; then
    echo "ERROR: petalinux-build not found"
    echo "Please source PetaLinux settings: source ~/petalinux/settings.sh"
    exit 1
fi

echo "  PetaLinux found at: $PETALINUX_DIR"
echo "  $(petalinux-util --version)"
echo ""

# Step 2: Create or update project
echo "[2/7] Setting up project..."

cd "$SCRIPT_DIR"

if [ -d "$PROJECT_NAME" ]; then
    echo "  Project exists at $PROJECT_NAME"
    echo "  Updating project..."
    cd "$PROJECT_NAME"
    petalinux-config --refresh
else
    echo "  ERROR: Project directory not found"
    echo "  Please run this script from the PetaLinux project directory"
    echo "  Or create project first with:"
    echo "    source ~/petalinux/settings.sh"
    echo "    petalinux-create -t project -s <bsp-file>"
    exit 1
fi

echo "  Done."
echo ""

# Step 3: Build PetaLinux
if [ $SKIP_BUILD -eq 0 ]; then
    echo "[3/7] Building PetaLinux..."
    echo "  WARNING: This takes 1-2 hours on first build"
    echo ""

    petalinux-build

    echo "  Done."
else
    echo "[3/7] Skipping build (--skip-build)"
fi

echo ""

# Step 4: Package boot files
echo "[4/7] Packaging boot files..."

petalinux-package --boot --fsbl images/linux/zynqmp_fsbl.elf \
    --u-boot images/linux/u-boot.elf \
    --atf images/linux/bl31.elf \
    --pmufw images/linux/pmufw.elf \
    --kernel images/linux/image.ub \
    -o images/linux/BOOT.BIN

echo "  Created: images/linux/BOOT.BIN"
echo ""

# Step 5: Prepare SD card
if [ $SKIP_SD -eq 0 ]; then
    echo "[5/7] Preparing SD card..."

    if [ -z "$SD_DEVICE" ]; then
        echo "  ERROR: No SD device specified"
        echo "  Use --sd-device /dev/sdX"
        echo ""
        echo "  Available devices:"
        lsblk -d -o NAME,SIZE,TYPE | grep -E 'disk|sd'
        exit 1
    fi

    # Run SD card preparation script
    chmod +x "$SCRIPT_DIR/create_sd_card.sh"
    sudo "$SCRIPT_DIR/create_sd_card.sh" "$SD_DEVICE"

    echo "  Done."
else
    echo "[5/7] Skipping SD preparation (--skip-sd)"
fi

echo ""

# Step 6: Deploy to SD card
echo "[6/7] Deploying to SD card..."

if [ -n "$SD_DEVICE" ]; then
    MOUNT_BOOT="/tmp/deploy_boot_$$"
    MOUNT_ROOT="/tmp/deploy_root_$$"
    mkdir -p "$MOUNT_BOOT" "$MOUNT_ROOT"

    # Mount
    mount "${SD_DEVICE}1" "$MOUNT_BOOT"
    mount "${SD_DEVICE}2" "$MOUNT_ROOT"

    # Copy boot files
    cp images/linux/BOOT.BIN "$MOUNT_BOOT/"
    cp images/linux/image.ub "$MOUNT_BOOT/"
    cp images/linux/system.dtb "$MOUNT_BOOT/"

    # Extract rootfs
    tar -xzf images/linux/rootfs.tar.gz -C "$MOUNT_ROOT/"

    # Create application directories
    mkdir -p "$MOUNT_ROOT/var/models"
    mkdir -p "$MOUNT_ROOT/lib/firmware"
    mkdir -p "$MOUNT_ROOT/usr/local/bin"

    # Sync and unmount
    sync
    umount "$MOUNT_BOOT" "$MOUNT_ROOT"
    rmdir "$MOUNT_BOOT" "$MOUNT_ROOT"

    echo "  Files deployed to SD card"
else
    echo "  Skipped (no SD device)"
fi

echo ""

# Step 7: Summary
echo "[7/7] Summary"
echo ""
echo "========================================"
echo "Build Complete!"
echo "========================================"
echo ""
echo "SD card contents:"
echo "  BOOT partition:"
echo "    - BOOT.BIN"
echo "    - image.ub"
echo "    - system.dtb"
echo ""
echo "  ROOT partition:"
echo "    - Full PetaLinux filesystem"
echo "    - /var/models/ (empty, ready for model files)"
echo "    - /lib/firmware/ (empty, ready for bitstreams)"
echo ""
echo "Next steps:"
echo "  1. Copy model files to /var/models/"
echo "  2. Copy FPGA bitstream to /lib/firmware/"
echo "  3. Insert SD card into KV260"
echo "  4. Connect serial cable"
echo "  5. Power on"
echo ""
echo "Serial connection:"
echo "  screen /dev/ttyUSB1 115200"
echo ""