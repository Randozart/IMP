# IMP KV260 Boot Plan

## Status
**Last Updated:** 2026-04-26 (v1.2 - Memory overlap fixed)

## Current Problem
The KV260 boots from QSPI flash and ignores the SD card. U-Boot in QSPI is looking for Linux (`Image` + `system.dtb`), but IMP is a bare-metal project.

## Boot Solution: Option 1 (Development Path)

Use the Kria's built-in U-Boot to load IMP via a `boot.scr` script. This is the safest development path.

### Why This Works
1. QSPI flash contains FSBL + PMUFW + U-Boot
2. U-Boot initializes DDR, powers FPGA fabric
3. `boot.scr` tells U-Boot to load bitstream and skip Linux
4. Board runs IMP without needing BOOT.BIN

### SD Card Structure
```
<SD card root (FAT32)>
├── boot.scr                          # U-Boot boot script
├── system_wrapper.bin                # Headerless FPGA bitstream (7.8MB)
└── imp/
    ├── kernel.bin                    # Bare-metal executable (~130KB)
    ├── model_9b.isp                  # Foundation model weights (~2.2GB)
    └── feeder.isp                    # Drafter model weights (~867MB)
```

### Corrected Memory Map (v1.2)

| Asset | Start Address | End Address (Approx) | Size |
|-------|---------------|---------------------|------|
| **Kernel** | `0x00000000` | `0x0FFFFFFF` | 256 MB |
| **9B Model** | `0x10000000` | `0x9FFFFFFF` | 2.25 GB |
| **Feeder Model** | `0xA0000000` | `0xD3FFFFFF` | 867 MB |
| **Working RAM** | `0xD4000000` | `0xFFFFFFFF` | ~700 MB |

### boot.cmd (Corrected)

```bash
# IMP Automated Boot Script for KV260 (v1.2 Fixed)
# Memory Map (Safe for 4GB DDR):
#   0x00080000  - Kernel entry (256MB region starting at 0x00000000)
#   0x10000000  - 9B Model (2.25GB)
#   0xA0000000  - Feeder Model (867MB)
#   0xD4000000  - Working RAM (~700MB)

echo ========================================
echo IMP Boot Sequence v1.2 (aarch64)
echo ========================================

# 1. Program FPGA fabric
echo [1/5] Programming FPGA...
load mmc 1:1 0x01000000 system_wrapper.bin
fpga load 0 0x01000000 $filesize

# 2. Load Kernel (Load this early so weights don't sit on it)
echo [2/5] Loading kernel to 0x00080000...
load mmc 1:1 0x00080000 imp/kernel.bin

# 3. Load Foundation model (9B) - 2.2GB
echo [3/5] Loading model_9b.isp to 0x10000000...
echo WARNING: This takes approximately 2-3 minutes...
load mmc 1:1 0x10000000 imp/model_9b.isp

# 4. Load Drafter model (0.5B)
echo [4/5] Loading feeder.isp to 0xA0000000...
load mmc 1:1 0xA0000000 imp/feeder.isp

# 5. Execute
echo [5/5] Starting IMP kernel at 0x00080000...
echo ========================================
go 0x00080000

# If we get here, kernel exited
echo KERNEL EXITED
```

### Step 1: Create boot.scr

```bash
cd /path/to/imp/boot
mkimage -A arm64 -T script -C none -d boot.cmd boot.scr
```

### Step 2: Prepare Files

1. **Copy bitstream to SD card root:**
   ```bash
   cp /path/to/imp/boot/system_wrapper.bin /media/sdcard/
   ```

2. **Create imp/ directory:**
   ```bash
   mkdir -p /media/sdcard/imp
   ```

3. **Compile kernel.c → kernel.bin (64-bit):**
   ```bash
   cd /home/randozart/Desktop/Projects/imp
   aarch64-linux-gnu-gcc -nostdlib -march=armv8-a -mlittle-endian -ffreestanding -O2 \
       -T arm/linker.ld -o arm/kernel.elf arm/kernel.c
   aarch64-linux-gnu-objcopy -O binary arm/kernel.elf arm/kernel.bin
   cp arm/kernel.bin /media/sdcard/imp/
   ```

4. **Copy model weights:**
   ```bash
   cp /path/to/weights/model_9b.isp /media/sdcard/imp/
   cp /path/to/weights/feeder.isp /media/sdcard/imp/
   ```

### Step 3: Boot the Board

1. Insert SD card
2. Connect USB-UART (115200 baud)
3. Power on
4. **Immediately press SPACE** to stop autoboot
5. At `ZynqMP>` prompt, type:
   ```
   reset
   ```
   OR if that doesn't work:
   ```
   run bootcmd
   ```
6. Watch IMP boot sequence

---

## Alternative: Boot Mode Override (One-Time SD Boot)

If you want the board to truly boot from SD card like a classic Zynq:

```uboot
ZynqMP> mw 0xff5e0200 0x00000005
ZynqMP> reset
```

This forces SD boot mode temporarily. After hard power cycle, reverts to QSPI.

---

## Option 2: Production Path (QSPI Flash)

Once IMP is stable, burn to internal flash for "appliance" mode.

### Requirements
- `BOOT.BIN` containing: `fsbl.elf` → `pmufw.elf` → `system_wrapper.bin` → `kernel.elf`
- Use Vitis "Create Boot Image" tool
- Kria Firmware Update web interface (hold FWUEN button, power on)

### Warning
Burning to QSPI is irreversible without JTAG. **Stick to Option 1 during development.**

---

## Files on SD Card

| File | Source | Size | Status |
|------|--------|------|--------|
| `boot.scr` | `boot/boot.cmd` + mkimage | 1KB | ✅ Ready |
| `system_wrapper.bin` | `boot/system_wrapper.bin` | 7.8MB | ✅ Ready |
| `imp/kernel.bin` | `arm/kernel.bin` | 130KB | ✅ Need to compile |
| `imp/model_9b.isp` | `weights/model_9b.isp` | 2.2GB | ✅ Ready |
| `imp/feeder.isp` | `weights/feeder.isp` | 828MB | ✅ Ready |

---

## Toolchain

**CRITICAL:** Use 64-bit ARM toolchain (Cortex-A53 = ARMv8-A):
- ✅ `aarch64-linux-gnu-gcc -march=armv8-a`
- ❌ NOT `arm-none-eabi-gcc` (32-bit Cortex-M/R)

---

## Next Steps

1. [ ] Compile `kernel.c` → `kernel.bin` with updated linker script
2. [ ] Copy all files to SD card
3. [ ] Test boot on hardware
4. [ ] Debug any issues
5. [ ] (Optional) Burn to QSPI for production

### Quick Compile Command
```bash
cd /home/randozart/Desktop/Projects/imp
aarch64-linux-gnu-gcc -nostdlib -static -march=armv8-a -mlittle-endian -ffreestanding -O2 \
    -Ttext=0x00080000 -Wl,--section-start=.text.start=0x00080000 \
    -o arm/kernel.elf arm/kernel.c
aarch64-linux-gnu-objcopy -O binary arm/kernel.elf arm/kernel.bin
```

**Output:**
- `arm/kernel.elf`: 131KB (ELF with symbols)
- `arm/kernel.bin`: 3.6MB (statically linked raw binary)

---

## Critical Fixes in v1.2

1. **Fixed memory overlap** - 9B model (2.2GB) starting at 0x10000000 no longer overlaps kernel
2. **Changed feeder address** - moved from 0x70000000 to 0xA0000000
3. **Changed kernel address** - moved from 0x20000000 to 0x00080000
4. **Changed `fpga loadb` to `fpga load`** - using raw bitstream format
5. **Updated linker script** - `arm/linker.ld` now uses 0x00080000 entry point
