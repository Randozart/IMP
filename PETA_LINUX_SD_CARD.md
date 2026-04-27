# IMP - PetaLinux SD Card Setup (Using Pre-Built Image)

## You Have the Right Files

```
~/Downloads/
├── petalinux-v2025.2-11160223-installer.run    # PetaLinux tool installer
└── kria-image-full-cmdline-kria-zynqmp-generic.rootfs-20251116094523.wic.xz
                                                                # Pre-built Kria image
```

## Two Options

### Option A: Write Pre-Built Image to SD Card (Fastest)

This gives you a working Linux system immediately. You can then add IMP software on top.

#### Step 1: Insert SD Card and Identify Device

```bash
lsblk
# Look for /dev/sdX with ~16GB or more
```

#### Step 2: Write Image to SD Card

```bash
# Decompress and write in one step (slow but uses less temp space)
xzcat ~/Downloads/kria-image-full-cmdline-kria-zynqmp-generic.rootfs-20251116094523.wic.xz | sudo dd of=/dev/sdX bs=4M status=progress

# OR decompress first, then write (faster but needs ~2GB temp space)
unxz ~/Downloads/kria-image-full-cmdline-kria-zynqmp-generic.rootfs-20251116094523.wic.xz
sudo dd if=~/Downloads/kria-image-full-cmdline-kria-zynqmp-generic.rootfs-20251116094523.wic of=/dev/sdX bs=4M status=progress
```

#### Step 3: Sync and Insert into KV260

```bash
sudo sync
# Remove SD card, insert into KV260
```

---

### Option B: Install PetaLinux Tools First (For Customization)

Use this if you need to customize the kernel, add drivers, or rebuild components.

#### Step 1: Install PetaLinux Tools

```bash
# Make executable
chmod +x ~/Downloads/petalinux-v2025.2-11160223-installer.run

# Run installer (as normal user, NOT root)
# Choose installation directory: ~/petalinux
# Accept all defaults
~/Downloads/petalinux-v2025.2-11160223-installer.run --dir ~/petalinux
```

#### Step 2: Set Up Environment

```bash
# Add to ~/.bashrc
echo 'source ~/petalinux/settings.sh' >> ~/.bashrc
source ~/petalinux/settings.sh
```

#### Step 3: Create Project

```bash
# Option A: From BSP (if you have one)
petalinux-create -t project -s /path/to/bsp.bsp -n imp-platform

# Option B: From scratch with your HDF file
petalinux-create -t project -n imp-platform
cd imp-platform
petalinux-config --get-hw-description=/path/to/hdf/
```

#### Step 4: Build

```bash
petalinux-build
petalinux-package --boot --fsbl images/linux/zynqmp_fsbl.elf \
    --u-boot images/linux/u-boot.elf --atf images/linux/bl31.elf \
    --kernel images/linux/image.ub -o images/linux/BOOT.BIN
```

---

## First Boot (Either Option)

1. Insert SD card into KV260
2. Connect serial cable (screen /dev/ttyUSB1 115200)
3. Power on
4. You should see Linux boot messages
5. Login: `root` (no password initially)

---

## After Boot: Install PetaLinux Tools (Optional)

If you used Option A (pre-built image) but want to customize later:

```bash
# On KV260 or your build PC:
# Copy installer to KV260
scp ~/Downloads/petalinux-v2025.2-11160223-installer.run root@192.168.1.195:/tmp/

# On KV260:
cd /tmp
chmod +x petalinux-v2025.2-*.run
./petalinux-v2025.2-*.run --dir /opt/petalinux
```

---

## Recommended: Use Option A First

Get the board working with the pre-built image, then customize later.

---

## Quick Reference

| Task | Command |
|------|---------|
| Write image | `xzcat *.wic.xz \| sudo dd of=/dev/sdX bs=4M` |
| Serial console | `screen /dev/ttyUSB1 115200` |
| Default login | `root` (no password) |
| Check IP | `ip addr` |

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| SD card not detected | Try different USB port, check with `lsblk` |
| Boot fails | Check serial output for errors |
| No network | Edit `/etc/network/interfaces` |

---

*Document version: 1.0*
*Created: 2026-04-26*