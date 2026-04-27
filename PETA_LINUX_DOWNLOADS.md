# IMP - PetaLinux Setup & Deployment Guide

## ⚠️ IMPORTANT: Download Links Require AMD/Xilinx Account

The download links below require a **free account** on AMD.com. The links go to the official download pages where you can find the exact installer files.

---

## Download Locations

### 1. PetaLinux Tools Download Page
**URL:** https://www.xilinx.com/support/download/index.html/content/xilinx/en/downloadNav/embedded-design-tools.html

On this page, look for:
- **PetaLinux Tools - Installer** (the main tool)
- **Board Support Packages (BSP)** section

### 2. For KV260 (Vision AI Starter Kit)
**URL:** https://www.xilinx.com/support/download/index.html/content/xilinx/en/downloadNav/embedded-design-tools.html

Look for these BSP files (exact names vary):
- `xilinx-kr260-starterboard-v2025.2.bsp` (latest)
- `xilinx-kv260-starterboard-v2025.2.bsp` (if KV260 separate)

Or search for: **Kria KV260 BSP**

### 3. Direct Links (if available)
- PetaLinux 2025.2 Installer: Look for `petalinux-v2025.2-*.run` on the download page
- KV260 BSP: Look for `xilinx-kv260*.bsp` or `xilinx-kr260*.bsp`

---

## Version Information

| Version | Release Date | Status |
|---------|--------------|--------|
| 2025.2 | Nov 2025 | Latest |
| 2025.1 | May 2025 | Available |
| 2024.2 | Nov 2024 | Available |
| 2024.1 | May 2024 | Available |
| 2023.2 | Aug 2023 | Available |

**Note:** PetaLinux is being superseded by AMD EDF (Embedded Development Framework). BSP support will migrate to EDF before winter 2026.

---

## Installation Steps (After Download)

### Step 1: Create AMD Account
1. Go to: https://www.xilinx.com/support/download/index.html
2. Click "Sign In" → "Create Account"
3. Verify your email

### Step 2: Download PetaLinux Installer
1. Go to: https://www.xilinx.com/support/download/index.html/content/xilinx/en/downloadNav/embedded-design-tools.html
2. Select a version (2025.2 recommended)
3. Download: `petalinux-v2025.2-*.run`

### Step 3: Download KV260 BSP
1. On the same page, scroll to "Board Support Packages"
2. Find "Kria KV260 Vision AI Starter Kit" or "KR260 Robotics Starter Kit"
3. Download the `.bsp` file

### Step 4: Install Dependencies (Ubuntu)

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

### Step 5: Run PetaLinux Installer

```bash
# Make executable
chmod +x petalinux-v2025.2-*.run

# Run installer (as normal user, NOT root)
./petalinux-v2025.2-*.run --dir ~/petalinux

# Follow on-screen prompts
```

### Step 6: Set Up Environment

```bash
# Add to ~/.bashrc
echo 'source ~/petalinux/settings.sh' >> ~/.bashrc
source ~/petalinux/settings.sh

# Verify
petalinux-util --version
```

---

## Create PetaLinux Project

### Option A: From BSP (Recommended)

```bash
source ~/petalinux/settings.sh

# Create project from BSP
petalinux-create -t project -s /path/to/xilinx-kr260-starterboard-v2025.2.bsp -n imp-platform
cd imp-platform
```

### Option B: From Scratch

```bash
source ~/petalinux/settings.sh

# Create empty project
petalinux-create -t project -n imp-platform
cd imp-platform

# Configure for KV260 hardware
petalinux-config --get-hw-description=/path/to/hdf/
```

---

## Build PetaLinux

```bash
cd imp-platform

# Build (takes 1-2 hours first time)
petalinux-build

# Package for SD card
petalinux-package --boot \
    --fsbl images/linux/zynqmp_fsbl.elf \
    --u-boot images/linux/u-boot.elf \
    --atf images/linux/bl31.elf \
    --pmufw images/linux/pmufw.elf \
    --kernel images/linux/image.ub \
    -o images/linux/BOOT.BIN
```

---

## Troubleshooting Downloads

### "Access Denied" or "Login Required"
- You must be logged into AMD.com
- Create free account at: https://www.xilinx.com/register.html

### Can't Find KV260 BSP
- KV260 may be listed under "KR260" (Robotics Starter Kit) or generic Kria SOM
- Try searching on the page for "kria" or "kv260"
- The KV260 and KR260 use similar/identical BSP in some versions

### Which Version to Use?
- **2025.2** - Latest features, newest hardware support
- **2023.2** - Most documented, widely compatible
- Use 2023.2 if you have issues with newer versions

---

## Alternative: Pre-Built Images

If you just want to boot quickly, AMD provides pre-built images:

**URL:** https://www.xilinx.com/support/download/index.html/content/xilinx/en/downloadNav/embedded-design-tools.html

Look for:
- "Zynq UltraScale+ MPSoC" pre-built images
- "KV260 Evaluation Kit" pre-built images

These can be written directly to SD card without building.

---

## Quick Reference Card

See `IMP_QUICK_CARD.md` for abbreviated reference.

---

## Support

- AMD/Xilinx Forums: https://forums.xilinx.com/
- PetaLinux Docs: `<petalinux-install>/docs/`
- Wiki: https://wiki.xilinx.com/

---

*Document version: 1.1*
*Last updated: 2026-04-26*