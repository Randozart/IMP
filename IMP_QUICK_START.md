# IMP Quick Start Guide (KV260 + PetaLinux)

## TL;DR

1. Build PetaLinux project
2. Flash to SD card
3. Power on KV260
4. Model loads, inference runs

---

## Step 1: Build PetaLinux

```bash
# Source PetaLinux
source ~/petalinux/settings.sh

# Navigate to project
cd ~/imp-platform

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

## Step 2: Prepare SD Card

```bash
# Identify SD card (BE CAREFUL!)
lsblk

# Partition and format
sudo parted /dev/sdX --script \
    mklabel msdos \
    mkpart primary fat32 1MiB 1536MiB \
    mkpart primary ext4 1536MiB 100% \
    set 1 boot on

sudo mkfs.vfat -F 32 /dev/sdX1
sudo mkfs.ext4 -E nodiscard /dev/sdX2

# Mount
mkdir -p ~/sdcard/{boot,root}
sudo mount /dev/sdX1 ~/sdcard/boot
sudo mount /dev/sdX2 ~/sdcard/root

# Copy boot files
cp images/linux/BOOT.BIN ~/sdcard/boot/
cp images/linux/image.ub ~/sdcard/boot/
cp images/linux/system.dtb ~/sdcard/boot/

# Extract rootfs
sudo tar -xzf images/linux/rootfs.tar.gz -C ~/sdcard/root/

# Sync
sudo sync
sudo umount ~/sdcard/{boot,root}
```

---

## Step 3: First Boot

```bash
# Connect serial
screen /dev/ttyUSB1 115200

# Power on KV260
# Watch for boot messages

# Login (serial console)
root (password: root)

# Check system
petalinux-util --status
```

---

## Step 4: Load FPGA Bitstream

```bash
# Copy bitstream to firmware directory
sudo cp neuralcore.bit /lib/firmware/

# Create FPGA device (if needed)
echo "xilinx" > /sys/class/fpga/fpga0/interface

# Load bitstream
cat /lib/firmware/neuralcore.bit > /dev/fpga0

# Verify FPGA loaded
dmesg | grep -i fpga
```

---

## Step 5: Load Model & Run Inference

```bash
# Copy model to SD card (via USB or network)
sudo mkdir -p /var/models
sudo cp model_9b.isp /var/models/

# Run inference
python3 /usr/local/bin/imp-inference.py "Hello, world"
```

---

## Common Commands

```bash
# Serial console
screen /dev/ttyUSB1 115200

# Copy files via SSH
scp model.bin root@192.168.1.195:/var/models/

# Check FPGA status
cat /sys/class/fpga/fpga0/status

# Check memory
free -h

# View kernel logs
dmesg | tail -50

# Reboot
reboot

# Shutdown
poweroff
```

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| No serial output | Check cable / try different USB port |
| Boot hangs | Press key to stop autoboot, check boot.scr |
| FPGA not detected | Verify bitstream loaded: `dmesg \| grep fpga` |
| Model won't load | Check available memory: `free -h` |
| Network not working | Check eth0: `ip addr show eth0` |

---

## File Locations

| Item | Location |
|------|----------|
| Bootloader | /media/boot/BOOT.BIN |
| Kernel | /media/boot/image.ub |
| Models | /var/models/ |
| FPGA bitstreams | /lib/firmware/ |
| IMP software | /usr/local/bin/ |
| Logs | /var/log/ |
| Startup scripts | /etc/init.d/ |

---

## Memory Map (PetaLinux)

| Region | Address | Usage |
|--------|---------|-------|
| ARM DDR4 | 0x00000000 | Linux kernel + apps |
| FPGA MMIO | 0x80000000 | FPGA registers |
| FPGA BRAM | 0x88000000 | FPGA block RAM |

---

## Quick Recovery

```bash
# If system won't boot:
# 1. Remove SD card
# 2. Mount on PC
# 3. Check /var/log/ for errors
# 4. Re-flash if needed

# Force rebuild:
petalinux-build -x mrproper
petalinux-build
```

---

## Support

- Xilinx forums: https://forums.xilinx.com/
- PetaLinux docs: `<petalinux-install>/docs/`
- IMP project: See README.md