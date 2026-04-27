# IMP KV260 - PetaLinux Quick Card

## Build (90-120 min first time)

```bash
# 1. Setup
source ~/petalinux/settings.sh
cd ~/imp-platform

# 2. Build
petalinux-build                    # 1-2 hours
petalinux-package --boot \
  --fsbl images/linux/zynqmp_fsbl.elf \
  --u-boot images/linux/u-boot.elf \
  --atf images/linux/bl31.elf \
  --pmufw images/linux/pmufw.elf \
  --kernel images/linux/image.ub \
  -o images/linux/BOOT.BIN
```

## Flash SD Card

```bash
# Partition
sudo parted /dev/sdX --script \
  mklabel msdos \
  mkpart primary fat32 1MiB 1536MiB \
  mkpart primary ext4 1536MiB 100%

# Format
sudo mkfs.vfat -F 32 /dev/sdX1
sudo mkfs.ext4 -E nodiscard /dev/sdX2

# Mount & copy
mkdir -p ~/sdcard/{boot,root}
sudo mount /dev/sdX1 ~/sdcard/boot/
sudo mount /dev/sdX2 ~/sdcard/root/
cp images/linux/BOOT.BIN ~/sdcard/boot/
cp images/linux/image.ub ~/sdcard/boot/
sudo tar -xzf images/linux/rootfs.tar.gz -C ~/sdcard/root/
sync; sudo umount ~/sdcard/{boot,root}
```

## Serial Console

```bash
screen /dev/ttyUSB1 115200
# Password: root
```

## FPGA & Model Loading

```bash
# Load bitstream
cp neuralcore.bit /lib/firmware/
cat /lib/firmware/neuralcore.bit > /dev/fpga0

# Load model
cp model_9b.isp /var/models/

# Run inference
imp-inference "Hello world"
```

## File Locations

| Item | Path |
|------|------|
| Boot | /media/boot/BOOT.BIN |
| Kernel | /media/boot/image.ub |
| Models | /var/models/ |
| Bitstreams | /lib/firmware/ |
| IMP tools | /usr/local/bin/ |

## KV260 Memory Map

| Region | Address | Use |
|--------|---------|-----|
| Linux RAM | 0x0 - 0x7FFFFFFF | Kernel + apps |
| FPGA MMIO | 0x80000000 | Register access |
| FPGA BRAM | 0x88000000 | On-chip memory |

## Commands

```bash
# Build PetaLinux
petalinux-build

# Package boot image
petalinux-package --boot --fsbl ... --kernel ...

# Check FPGA status
cat /sys/class/fpga/fpga0/status

# Check memory
free -h

# Reboot
reboot
```

## Troubleshooting

| Problem | Fix |
|---------|-----|
| No serial output | Check cable, try different USB port |
| Boot hangs | Press key to stop autoboot |
| FPGA not found | Load bitstream: `cat bitstream > /dev/fpga0` |
| Model won't load | Check space: `df -h` |

---

**See Also:**
- `PETA_LINUX_SETUP.md` - Full guide
- `BAREMETAL_FAILURES.md` - Why we switched
- `IMP_QUICK_START.md` - Detailed reference