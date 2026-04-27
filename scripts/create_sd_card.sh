#!/bin/bash
################################################################################
# SD Card Preparation Script
# Creates properly partitioned SD card for KV260 PetaLinux
#
# WARNING: This script will DESTROY all data on the target device!
#          Double-check the DEVICE variable before running!
#
# Usage: sudo ./create_sd_card.sh /dev/sdX
################################################################################

set -e

if [ "$EUID" -ne 0 ]; then
    echo "ERROR: This script must be run as root"
    echo "Usage: sudo $0 /dev/sdX"
    exit 1
fi

DEVICE="$1"
SD_SIZE_GB="16"

if [ -z "$DEVICE" ]; then
    echo "ERROR: No device specified"
    echo "Usage: sudo $0 /dev/sdX"
    echo ""
    echo "Available devices:"
    lsblk -d -o NAME,SIZE,TYPE | grep -E 'disk|sd'
    exit 1
fi

# Verify device exists
if [ ! -b "$DEVICE" ]; then
    echo "ERROR: Device $DEVICE does not exist"
    exit 1
fi

# Double-check it's an SD card or USB drive (not internal disk)
if [[ "$DEVICE" =~ nvme|nvme[0-9]n[0-9] ]]; then
    echo "ERROR: NVMe devices are not supported for SD card"
    exit 1
fi

# Show device info
echo "========================================"
echo "SD Card Preparation Script"
echo "========================================"
echo ""
echo "Target device: $DEVICE"
echo "This will DESTROY all data on this device!"
echo ""
read -p "Are you sure? Type 'yes' to continue: " confirm

if [ "$confirm" != "yes" ]; then
    echo "Aborted."
    exit 1
fi

echo ""
echo "[1/6] Partitioning SD card..."

# Unmount any mounted partitions
umount ${DEVICE}* 2>/dev/null || true

# Create new partition table
parted --script "$DEVICE" \
    mklabel msdos \
    mkpart primary fat32 1MiB 1536MiB \
    mkpart primary ext4 1536MiB 100% \
    set 1 boot on

echo "  Done."

echo ""
echo "[2/6] Formatting partitions..."

# Format first partition as FAT32
mkfs.vfat -F 32 -n BOOT "${DEVICE}1"

# Format second partition as ext4
mkfs.ext4 -E nodiscard -L rootfs "${DEVICE}2"

echo "  Done."

echo ""
echo "[3/6] Mounting partitions..."

# Create mount points
MOUNT_BOOT="/tmp/sdcard_boot_$$"
MOUNT_ROOT="/tmp/sdcard_root_$$"
mkdir -p "$MOUNT_BOOT" "$MOUNT_ROOT"

# Mount
mount "${DEVICE}1" "$MOUNT_BOOT"
mount "${DEVICE}2" "$MOUNT_ROOT"

echo "  Done."

echo ""
echo "[4/6] Copying PetaLinux boot files..."

# Copy BOOT.BIN, image.ub, etc.
# (These will be added after petalinux-build)
if [ -f "images/linux/BOOT.BIN" ]; then
    cp images/linux/BOOT.BIN "$MOUNT_BOOT/"
fi

if [ -f "images/linux/image.ub" ]; then
    cp images/linux/image.ub "$MOUNT_BOOT/"
fi

if [ -f "images/linux/system.dtb" ]; then
    cp images/linux/system.dtb "$MOUNT_BOOT/"
fi

echo "  Done."

echo ""
echo "[5/6] Syncing..."

sync

echo "  Done."

echo ""
echo "[6/6] Unmounting..."

umount "$MOUNT_BOOT" "$MOUNT_ROOT"
rmdir "$MOUNT_BOOT" "$MOUNT_ROOT"

echo "  Done."

echo ""
echo "========================================"
echo "SD card prepared successfully!"
echo "========================================"
echo ""
echo "Next steps:"
echo "  1. Extract rootfs to SD card root partition"
echo "  2. Copy FPGA bitstream to /lib/firmware/"
echo "  3. Copy model files to /var/models/"
echo "  4. Unmount and insert into KV260"
echo ""
echo "Files on BOOT partition:"
ls -la "${DEVICE}1" 2>/dev/null || ls -la /tmp/sdcard_boot_*/ 2>/dev/null || echo "BOOT partition contents listed above"

echo ""
echo "SD card is ready!"