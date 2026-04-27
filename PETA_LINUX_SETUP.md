# IMP - PetaLinux Setup & Deployment Guide

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Installation](#installation)
4. [Project Creation](#project-creation)
5. [SD Card Preparation](#sd-card-preparation)
6. [Building & Deployment](#building--deployment)
7. [FPGA Integration](#fpga-integration)
8. [Model Loading](#model-loading)
9. [Inference Execution](#inference-execution)
10. [Troubleshooting](#troubleshooting)

---

## Overview

This guide transforms the KV260 into a plug-and-work inference platform using Xilinx PetaLinux. The bare-metal approach was abandoned due to persistent memory management conflicts with U-Boot.

### What Changed

| Aspect | Bare-Metal (Failed) | PetaLinux (This Guide) |
|--------|---------------------|------------------------|
| Boot reliability | Manual commands required | Automatic on power-on |
| SD card access | Memory reservations block 2.2GB files | Normal filesystem read |
| Model loading | Blocked by U-Boot | `cat model.bin > /dev/fpga` |
| Development speed | Slow (debug memory issues) | Fast (Linux tools) |

### System Architecture

```
                    ┌─────────────────┐
                    │   PetaLinux     │
                    │   (ARM A53)     │
                    │   on KV260      │
                    └────────┬────────┘
                             │ /dev/uio0
                             │ /dev/mem
                             ▼
                    ┌─────────────────┐
                    │  FPGA Neural    │
                    │  Core Engine    │
                    │  (AXI4-Lite)    │
                    └────────┬────────┘
                             │
                    ┌────────▼────────┐
                    │     DDR4        │
                    │  (Model Weights)│
                    └─────────────────┘
```

---

## Prerequisites

### Hardware
- KV260 Vision AI Starter Kit
- SD card (16GB+ recommended)
- Power supply
- USB-UART cable for serial console
- Ethernet cable (optional, for TFTP)

### Software
- **Vivado Design Suite 2023.2+** with PetaLinux tools
  - Download from [Xilinx Downloads](https://www.xilinx.com/support/download/index.html)
- **Linux PC** (Ubuntu 20.04 LTS or 22.04 LTS recommended)
- **Xilinx account** (required for downloads)

### Skills
- Basic Linux command line
- Familiarity with embedded Linux
- Patience (first build takes 2-4 hours)

---

## Installation

### Step 1: Install PetaLinux Tools

**1a. Create Xilinx/AMD Account (Free)**
1. Go to: https://www.xilinx.com/support/download/index.html
2. Click "Sign In" → "Create Account"
3. Verify email

**1b. Download PetaLinux 2023.2**
1. Go to: https://www.xilinx.com/support/download/index.html
2. Search for "PetaLinux 2023.2"
3. Download: `petalinux-v2023.2-2023.08.17-installer.run`

**1c. Install Dependencies**
```bash
sudo apt update
sudo apt install -y \
    tofrodos \
    iproute2 \
    gawk \
    make \
    net-tools \
    ncurses-dev \
    libncurses5-dev \
    libssl-dev \
    flex \
    bison \
    libselinux1 \
    zlib1g-dev \
    autoconf \
    libtool \
    pkg-config \
    uboot-tools \
    uuid-dev \
    python3 \
    python3-pip
```

**1d. Run Installer**
```bash
# Make executable
chmod +x petalinux-v2023.2-2023.08.17-installer.run

# Run installer (as normal user, NOT root)
./petalinux-v2023.2-2023.08.17-installer.run --dir ~/petalinux
```

### Step 2: Set Up Environment

```bash
# Add to ~/.bashrc
echo 'source ~/petalinux/settings.sh' >> ~/.bashrc
source ~/petalinux/settings.sh

# Verify installation
petalinux-util --version
```

### Step 3: Install KV260 BSP

**3a. Download KV260 BSP**
1. Go to: https://www.xilinx.com/support/download/index.html
2. Search: "KR260 BSP" or "KV260 BSP"
3. Download: `xilinx-kr260-starterboard-v2023.2.bsp`
   (Or `xilinx-kv260-starterboard-v2023.2.bsp` for KV260)

**3b. Create Project**
```bash
source ~/petalinux/settings.sh

# Create project from BSP
petalinux-create -t project -s xilinx-kr260-starterboard-v2023.2.bsp -n imp-platform
cd imp-platform
```

---

## Project Creation

### Step 1: Configure Project

```bash
cd imp-platform

# Configure for KV260
petalinux-config --get-hw-description=<path-to-Vivado-hdf directory>

# OR use pre-built platform if you don't have Vivado
# Download from: https://www.xilinx.com/support/download/index.html
```

### Step 2: Configure Root Filesystem

```bash
petalinux-config -c rootfs
```

**Recommended packages to enable:**
- `packagegroup-petalinux-full` (full package set)
- `packagegroup-petalinux-networking` (for TFTP)
- `packagegroup-petalinux-sshd` (for remote access)
- `python3` and `python3-pip`
- `debug-tools` (for gdb)

### Step 3: Add Custom Layer (Optional)

For IMP-specific software:

```bash
# Create custom layer
petalinux-create -t layers -n meta-imp

# Add to project
echo 'BBLAYERS += "${METADIR}/layers/meta-imp"' >> project-spec/meta-imp/conf/layer.conf
```

---

## SD Card Preparation

### Partition Layout

| Partition | Filesystem | Size | Content |
|-----------|------------|------|---------|
| /dev/sdX1 | FAT32 | 1GB | BOOT.BIN, kernel, device tree |
| /dev/sdX2 | ext4 | Remaining | Root filesystem |

### Create Partitions

```bash
# Identify SD card device (BE CAREFUL!)
lsblk

# Assuming /dev/sdX is your SD card
sudo parted /dev/sdX --script \
    mklabel msdos \
    mkpart primary fat32 1MiB 1GiB \
    mkpart primary ext4 1GiB 100% \
    set 1 boot on

# Format
sudo mkfs.vfat -F 32 /dev/sdX1
sudo mkfs.ext4 -E nodiscard /dev/sdX2

# Mount
mkdir -p ~/sdcard/boot ~/sdcard/root
sudo mount /dev/sdX1 ~/sdcard/boot
sudo mount /dev/sdX2 ~/sdcard/root
```

---

## Building & Deployment

### Build PetaLinux

```bash
cd imp-platform

# Build everything
petalinux-build

# This produces:
#   images/linux/BOOT.BIN
#   images/linux/image.ub
#   images/linux/rootfs.tar.gz
```

### Deploy to SD Card

```bash
# Copy BOOT files
sudo cp images/linux/BOOT.BIN ~/sdcard/boot/
sudo cp images/linux/image.ub ~/sdcard/boot/
sudo cp images/linux/system.dtb ~/sdcard/boot/

# Extract rootfs
sudo tar -xvzf images/linux/rootfs.tar.gz -C ~/sdcard/root/

# Sync and unmount
sudo sync
sudo umount ~/sdcard/boot ~/sdcard/root
```

---

## FPGA Integration

### Device Tree Overlay for FPGA

Create `system-user.dtsi`:

```dtsi
/ {
    reserved-memory {
        #address-cells = <2>;
        #size-cells = <2>;
        ranges;

        fpga-region@80000000 {
            compatible = "fpga-region";
            reg = <0x0 0x80000000 0x0 0x10000000>;
        };
    };

    neural-core {
        compatible = "xlnx,neuralcore-1.0";
        reg = <0x0 0x8000A000 0x0 0x4000>;
        interrupt-parent = <&gic>;
        interrupts = <0 29 4>;
    };
};
```

### Load FPGA Bitstream

```bash
# Program FPGA at boot (add to /etc/rc.local or systemd service)
mkdir -p /lib/firmware
cp neuralcore.bit /lib/firmware/

# Create udev rule
echo 'SUBSYSTEM=="fpga", ACTION=="add", RUN+="/usr/bin/dWidth 0x8000A000 0x1"' > /etc/udev/rules.d/99-fpga.rules

# Or use devlink
devlink dev flash update /dev/mdev0 neuralcore.bit
```

### Userspace FPGA Access

```bash
# Create device node
mknod /dev/neuralcore c 245 0

# Or use UIO (userspace I/O)
echo "8000A000" > /sys/class/uio/uio0/maps/map0/addr
```

---

## Model Loading

### Method 1: Direct Filesystem Access (Simplest)

```bash
# Mount SD card on running system
# Model is just a file like any other

# Load model into DDR4 via custom driver
./imp-loader model_9b.isp 0x10000000

# Verify
md5sum model_9b.isp
./imp-query 0x10000000 32
```

### Method 2: TFTP (For Development)

```bash
# On development PC
sudo cp model_9b.isp /srv/tftp/
sudo systemctl start tftp-hpa

# On KV260
mkdir -p /tftp
mount -t nfs 192.168.1.100:/srv/tftp /tftp
cp /tftp/model_9b.isp /var/models/
```

### Method 3: Custom Kernel Module

Create `/lib/modules/5.15.0-xilinx-v2023.2/extra/imp.ko`:

```bash
# Load model via character device
echo "loading model_9b.isp" > /dev/imp
cat model_9b.isp > /dev/imp
```

---

## Inference Execution

### Basic Inference Script

Create `/usr/local/bin/run-inference.sh`:

```bash
#!/bin/bash
# run-inference.sh - Execute inference on KV260

MODEL_PATH="/var/models/model_9b.isp"
FPGA_DEV="/dev/neuralcore"

echo "IMP Inference Engine v1.0"
echo "=========================="

# Check FPGA
if [ ! -e "$FPGA_DEV" ]; then
    echo "ERROR: FPGA device not found"
    exit 1
fi

# Load model if not already loaded
if [ ! -f /var/models/.loaded ]; then
    echo "Loading model..."
    dd if=$MODEL_PATH of=/dev/neuralcore bs=1M status=progress
    touch /var/models/.loaded
fi

# Run inference
echo "Running inference..."
echo "input: Hello, world" | ./imp-inference

echo "Done."
```

### REST API Server (Optional)

For networked inference:

```bash
# Install Flask
pip3 install flask flask-restful

# Run server
python3 /usr/local/bin/imp-server.py
```

---

## Troubleshooting

### Board Not Booting

1. **Check SD card partitions**
   ```bash
   sudo parted /dev/sdX print
   ```

2. **Verify BOOT.BIN location**
   ```bash
   ls -la /media/boot/BOOT.BIN
   ```

3. **Check serial output**
   ```bash
   screen /dev/ttyUSB1 115200
   ```

### FPGA Not Detected

1. **Check device tree**
   ```bash
   dtc -I dtb /boot/system.dtb | grep -A5 neuralcore
   ```

2. **Reload device tree**
   ```bash
   echo 1 > /sys/firmware/devicetree/base/chosen/overlay_all/delete
   ```

### Model Loading Fails

1. **Check memory**
   ```bash
   free -h
   cat /proc/meminfo | grep -i avail
   ```

2. **Try smaller chunk**
   ```bash
   head -c 1M model_9b.isp > /dev/neuralcore
   ```

---

## Quick Reference

### Essential Commands

```bash
# Build
petalinux-build

# Package for SD card
petalinux-package --boot --fsbl images/linux/zynqmp_fsbl.elf \
    --u-boot images/linux/u-boot.elf \
    --atf images/linux/bl31.elf \
    --kernel images/linux/image.ub \
    -o images/linux/BOOT.BIN

# Connect to serial
screen /dev/ttyUSB1 115200

# Transfer files
scp model_9b.isp root@192.168.1.195:/var/models/

# FPGA programming
cat neuralcore.bit > /dev/fpga0
```

### Memory Map (KV260 DDR4)

| Address | Size | Usage |
|---------|------|-------|
| 0x00000000 | 2GB | Linux kernel + userspace |
| 0x80000000 | 2GB | FPGA + reserved |
| 0x8000A000 | 4KB | FPGA MMIO |
| 0x88000000 | 512MB | FPGA BRAM |

---

## Next Steps

1. Build PetaLinux project
2. Deploy to SD card
3. Verify boot
4. Load FPGA bitstream
5. Test model loading
6. Run first inference

---

## Appendix: File Manifest

```
SD Card/
├── BOOT.BIN          (PetaLinux boot image)
├── image.ub          (Linux kernel + device tree)
└── boot.scr          (Optional: boot script)

Root Filesystem/
├── lib/
│   └── firmware/     (FPGA bitstreams)
├── var/
│   └── models/       (AI model weights)
├── usr/
│   └── local/bin/    (IMP executables)
└── etc/
    └── init.d/       (Startup scripts)
```

---

## Version History

| Date | Version | Changes |
|------|---------|---------|
| 2026-04-26 | 1.0 | Initial PetaLinux guide |
| 2026-04-26 | 1.1 | Added bare-metal lessons learned reference |

## References

- [Xilinx PetaLinux Documentation](https://docs.xilinx.com/r/2023.2-English/ug1144-petalinux-tools-reference.pdf)
- [KV260 Hardware User Guide](https://www.xilinx.com/support/documentation/boards_and_kits/1.4/ug kria-vision-ai-starter-kit.pdf)
- [KV260 PetaLinux BSP Release Notes](https://www.xilinx.com/support/documentation/release-notes/kr260-petalinux-bsp-2023.2.pdf)