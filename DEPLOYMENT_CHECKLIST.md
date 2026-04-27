# IMP Deployment Checklist

## Pre-Flight Checklist

Before you begin, verify you have everything:

### Hardware
- [ ] KV260 Vision AI Starter Kit
- [ ] SD card (16GB or larger)
- [ ] Power supply (12V DC)
- [ ] USB-UART cable (for serial console)
- [ ] Ethernet cable (optional, for TFTP)

### Software
- [ ] Vivado Design Suite 2023.2+ installed
- [ ] PetaLinux 2023.2 installed at ~/petalinux
- [ ] KV260 BSP downloaded (xilinx-kr260-starterboard-v2023.2.bsp)
- [ ] FPGA bitstream (system_wrapper.bit or neuralcore.bit)

### Files
- [ ] Model weights: model_9b.isp (2.2GB)
- [ ] Feeder weights: feeder.isp (867MB)
- [ ] BOOT.BIN (pre-built or from PetaLinux)

---

## Phase 1: Build PetaLinux

### Step 1.1: Install PetaLinux Tools

```bash
# Install dependencies
sudo apt install tofrodos iproute2 gawk make net-tools ncurses-dev \
    libncurses5-dev libssl-dev flex bison libselinux1 zlib1g-dev \
    autoconf libtool pkg-config uboot-tools uuid-dev python3 python3-pip

# Download PetaLinux installer from Xilinx
# Run installer
chmod +x petalinux-v2023.2-*.run
./petalinux-v2023.2-*.run --dir ~/petalinux
```

### Step 1.2: Set Up Environment

```bash
# Add to ~/.bashrc
echo 'source ~/petalinux/settings.sh' >> ~/.bashrc
source ~/.bashrc

# Verify
petalinux-util --version
```

### Step 1.3: Create Project

```bash
source ~/petalinux/settings.sh
cd ~/imp-platform

# Download BSP from Xilinx first!
petalinux-create -t project -s xilinx-kr260-starterboard-v2023.2.bsp -n imp-platform
cd imp-platform
```

### Step 1.4: Configure Project

```bash
# Point to hardware description (if you have Vivado HDF)
petalinux-config --get-hw-description=/path/to/hdf/

# OR use pre-built platform from Xilinx
# (download from Xilinx support portal)
```

### Step 1.5: Build

```bash
# This takes 1-2 hours on first build
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

**Verification:**
- [ ] `images/linux/BOOT.BIN` exists
- [ ] `images/linux/image.ub` exists
- [ ] `images/linux/rootfs.tar.gz` exists

---

## Phase 2: Prepare SD Card

### Step 2.1: Partition SD Card

```bash
# Identify SD card device (BE CAREFUL!)
lsblk
# Assume /dev/sdX for this checklist

# Unmount any mounted partitions
sudo umount /dev/sdX*

# Partition
sudo parted /dev/sdX --script \
    mklabel msdos \
    mkpart primary fat32 1MiB 1536MiB \
    mkpart primary ext4 1536MiB 100% \
    set 1 boot on

# Format
sudo mkfs.vfat -F 32 -n BOOT /dev/sdX1
sudo mkfs.ext4 -E nodiscard -L rootfs /dev/sdX2
```

**Verification:**
- [ ] Two partitions visible in `lsblk`
- [ ] BOOT partition is FAT32
- [ ] rootfs partition is ext4

### Step 2.2: Copy Boot Files

```bash
# Mount partitions
mkdir -p ~/sdcard/{boot,root}
sudo mount /dev/sdX1 ~/sdcard/boot/
sudo mount /dev/sdX2 ~/sdcard/root/

# Copy boot files
cp images/linux/BOOT.BIN ~/sdcard/boot/
cp images/linux/image.ub ~/sdcard/boot/
cp images/linux/system.dtb ~/sdcard/boot/ 2>/dev/null || true

# Extract rootfs
sudo tar -xzf images/linux/rootfs.tar.gz -C ~/sdcard/root/
```

**Verification:**
- [ ] `~/sdcard/boot/BOOT.BIN` exists
- [ ] `~/sdcard/boot/image.ub` exists
- [ ] `~/sdcard/root/etc/passwd` exists

### Step 2.3: Create Application Directories

```bash
# Create directories for IMP
sudo mkdir -p ~/sdcard/root/var/models
sudo mkdir -p ~/sdcard/root/lib/firmware
sudo mkdir -p ~/sdcard/root/usr/local/bin

# Set permissions
sudo chmod 755 ~/sdcard/root/var/models
sudo chmod 755 ~/sdcard/root/lib/firmware
sudo chmod 755 ~/sdcard/root/usr/local/bin

# Sync and unmount
sudo sync
sudo umount ~/sdcard/{boot,root}
```

**Verification:**
- [ ] SD card unmounts cleanly
- [ ] No errors during sync

---

## Phase 3: Deploy to KV260

### Step 3.1: Insert SD Card

1. Power off KV260
2. Insert SD card
3. Connect USB-UART cable to PC
4. Open serial console: `screen /dev/ttyUSB1 115200`

### Step 3.2: Power On

```
# You should see:
Xilinx Zynq MP First Stage Boot Loader
...
Hit any key to stop autoboot:  0
ZynqMP>
```

If you see the prompt, press a key to stop autoboot.

### Step 3.3: Boot Manually (if needed)

```uboot
# Boot from SD
mmc dev 1
fatload mmc 1:1 0x30000000 image.ub
bootm 0x30000000
```

**Verification:**
- [ ] Linux kernel boots
- [ ] You see "PetaLinux" or "Xilinx" in boot log
- [ ] Login prompt appears

### Step 3.4: Initial Login

```
# Default credentials
login: root
password: root
```

**Verification:**
- [ ] Successfully logged in
- [ ] `uname -a` shows Linux running
- [ ] `free -h` shows memory

---

## Phase 4: FPGA Configuration

### Step 4.1: Load Bitstream

```bash
# Copy bitstream to SD card (before inserting, or via SSH)
sudo cp neuralcore.bit /media/root/lib/firmware/

# On KV260:
cat /lib/firmware/neuralcore.bit > /dev/fpga0

# Verify
dmesg | grep -i fpga
ls /sys/class/fpga/
```

**Verification:**
- [ ] `/dev/fpga0` exists
- [ ] `dmesg` shows FPGA load message
- [ ] DONE LED turns green (if applicable)

### Step 4.2: Verify FPGA Access

```bash
# Check FPGA status
cat /sys/class/fpga/fpga0/status

# Check MMIO
devmem 0x8000A000
devmem 0x8000A004
```

**Verification:**
- [ ] FPGA status is "operational" or similar
- [ ] MMIO registers return valid values

---

## Phase 5: Model Loading & Inference

### Step 5.1: Copy Model to KV260

**Option A: Via SSH/SCP**
```bash
# From development PC
scp model_9b.isp root@192.168.1.195:/var/models/
```

**Option B: Via USB**
```bash
# Copy to FAT32 partition on SD card
sudo cp model_9b.isp /media/boot/
# On KV260: mount /dev/mmcblk0p1 /mnt
# Then: cp /mnt/model_9b.isp /var/models/
```

**Option C: Via TFTP**
```bash
# On KV260:
mkdir -p /tftp
mount -t nfs 192.168.1.100:/srv/tftp /tftp
cp /tftp/model_9b.isp /var/models/
```

**Verification:**
- [ ] `ls -lh /var/models/model_9b.isp` shows ~2.2GB

### Step 5.2: Run Inference

```bash
# Check if IMP software is installed
which imp-inference

# If not, you'll need to build/copy IMP tools
# See IMP_QUICK_START.md for details

# Run inference
imp-inference "Hello, world"
```

**Verification:**
- [ ] Model loads without memory errors
- [ ] Inference completes
- [ ] Output is generated

---

## Phase 6: Post-Deployment

### Step 6.1: Verify System Stability

```bash
# Run for several minutes
top
# Check memory usage
free -h
# Check disk space
df -h

# Reboot test
reboot
# Verify system comes back up
```

### Step 6.2: Configure Auto-Start

```bash
# Create systemd service for auto-inference
cat > /etc/systemd/system/imp-inference.service << EOF
[Unit]
Description=IMP Inference Service
After=fpga-load.service

[Service]
Type=simple
ExecStart=/usr/local/bin/imp-inference-server
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

systemctl enable imp-inference.service
```

### Step 6.3: Document Deployment

- [ ] Record any issues encountered
- [ ] Note any modifications made
- [ ] Update this checklist with results

---

## Troubleshooting Guide

| Problem | Cause | Solution |
|---------|-------|----------|
| No serial output | Wrong baud rate | Try 9600 or 230400 |
| Boot hangs at "Loading" | SD card not read | Check partition format |
| "filesystem not found" | Wrong partition | Verify FAT32 boot partition |
| FPGA load fails | Bitstream corrupt | Re-copy bitstream |
| Model won't load (2.2GB) | Memory full | Check `free -h` first |
| Inference crashes | FPGA not configured | Verify with `dmesg` |

---

## Success Criteria

The deployment is successful when:

1. [ ] KV260 boots to Linux prompt without manual intervention
2. [ ] FPGA bitstream loads and DONE LED indicates success
3. [ ] Model file (2.2GB) can be read into memory
4. [ ] Inference completes without crashes
5. [ ] System can run continuously for 1+ hour without issues

---

## Deployment Log

| Date | Step | Result | Notes |
|------|------|--------|-------|
| 2026-04-26 | PetaLinux build | | |
| 2026-04-26 | SD card prep | | |
| 2026-04-26 | First boot | | |
| 2026-04-26 | FPGA load | | |
| 2026-04-26 | Model load | | |
| 2026-04-26 | First inference | | |

---

*Checklist version: 1.0*
*Created: 2026-04-26*