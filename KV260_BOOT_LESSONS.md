# KV260 Boot Debugging: Lessons Learned

**Date:** 2026-04-26
**Project:** IMP (Inference Machine Project)
**Goal:** Boot bare-metal IMP kernel on KV260 using SD card via U-Boot script

---

## Executive Summary

The KV260 has a fundamentally different boot architecture than traditional Zynq boards (Zybo, ZedBoard). This document captures every issue encountered, root cause analysis, and solutions.

---

## The KV260 Boot Architecture

### How KV260 Boots (vs Traditional Zynq)

| Aspect | Traditional Zynq | KV260 |
|--------|-----------------|-------|
| Boot Mode | Jumper selectable (SD, QSPI, JTAG) | **Hardwired to QSPI** |
| First Stage | BOOT.BIN on SD card | QSPI flash contains FSBL + PMUFW + U-Boot |
| Linux Expectation | Optional | **Mandatory** - U-Boot expects `Image` + `system.dtb` |
| Boot Control | Hardware switch | **Software override only** |

### The Two-Stage Boot

```
Power On
    ↓
QSPI Flash (Stage 1 - Fixed)
├── FSBL (First Stage Boot Loader)
├── PMUFW (Power Management Unit Firmware)
└── U-Boot (looks for Linux on SD card)
    ↓
SD Card (Stage 2 - User Data)
└── If Linux files found → Boot Linux
└── If boot.scr found → Execute script
└── If nothing recognized → Do nothing (silent hang)
```

---

## Issue 1: Silent Boot Failure

### Symptom
Board powered on, no serial output, no activity.

### Root Cause
The pre-installed Kria Ubuntu image was loaded, but the KV260 in this setup has **no boot mode switches**. It boots from QSPI flash first, which contains factory U-Boot. That U-Boot looks for specific Linux files that weren't present.

### Key Insight
> The KV260 is a "Linux-first" platform. It will NOT fall back to SD card boot if QSPI has valid firmware.

### Resolution
- Connect USB-UART serial console (115200 baud)
- Press SPACE during boot to stop at U-Boot prompt
- Manually issue commands

---

## Issue 2: "Wrong Image Format for bootm command"

### Symptom
```
ZynqMP> fatload mmc 1:1 0x00200000 Image
ZynqMP> bootm 0x00200000
Wrong Image Format for bootm command
ERROR: can't get kernel image!
```

### Root Cause
`bootm` expects U-Boot wrapped images (uImage, FIT). The raw `Image` file (raw kernel binary) is not wrapped.

### Resolution
- Use `bootz` for raw kernel + initramfs, OR
- Use `booti` for ARM64 kernel with flattened device tree, OR
- For bare-metal: Use `go <addr>` to jump directly to executable

---

## Issue 3: "Unknown command 'bootz'"

### Symptom
```
ZynqMP> bootz 0x00200000
Unknown command 'bootz' - try 'help'
```

### Root Cause
The U-Boot in QSPI flash is a **minimal/custom variant** that doesn't include all standard commands.

### Resolution
1. Check available commands: `help` or `help | grep boot`
2. Use alternative commands available in this U-Boot
3. For bare-metal: Use `go <address>`

---

## Issue 4: Missing Device Tree Blob (DTB)

### Symptom
```
ERROR: uImage is not a fdt - must RESET the board to recover.
FDT and ATAGS support not compiled in
```

### Root Cause
When using `booti` (ARM64 boot), U-Boot expects a Device Tree Blob at a specific address. The pre-built Kria generic image expects one, but none was provided.

### Resolution
- For Linux: Obtain `system.dtb` for KV260 (extract from BSP or build with PetaLinux)
- For bare-metal: Skip DTB entirely, use `go <addr>` instead

---

## Issue 5: Memory Overlap in boot.cmd

### Original (Broken) Memory Map
```
0x10000000 - Model weights (2.2GB)
0x20000000 - Kernel entry
0x70000000 - Feeder weights
```

**Problem:** 2.2GB model starting at 0x10000000 extends to 0x9C000000, which OVERWRITES the kernel at 0x20000000!

### Corrected Memory Map (v1.2)
| Asset | Start | End | Size |
|-------|-------|-----|------|
| Kernel | 0x00000000 | 0x0FFFFFFF | 256 MB |
| 9B Model | 0x10000000 | 0x9FFFFFFF | 2.25 GB |
| Feeder | 0xA0000000 | 0xD3FFFFFF | 867 MB |
| Working RAM | 0xD4000000 | 0xFFFFFFFF | ~700 MB |

---

## Issue 6: Toolchain Mismatch (32-bit vs 64-bit)

### Symptom
Binary appears to execute but crashes immediately or hangs.

### Root Cause
Used `arm-none-eabi-gcc` which produces **32-bit ARM code**. The KV260 uses **Cortex-A53 (ARMv8-A, 64-bit)**.

### Resolution
Use **64-bit toolchain**: `aarch64-linux-gnu-gcc -march=armv8-a`

### Available Toolchains
```bash
# 32-bit (WRONG for KV260)
arm-none-eabi-gcc     # Cortex-M/R, 32-bit

# 64-bit (CORRECT for KV260)
aarch64-linux-gnu-gcc # Cortex-A53, 64-bit
```

---

## Issue 7: Dynamic Linking vs Static Linking

### Symptom
Binary starts with `/lib/ld-linux-aarch64.so.1` instead of actual code.

### Root Cause
Without `-static`, the linker includes dynamic loader references.

### Resolution
Always use `-static` for bare-metal:
```bash
aarch64-linux-gnu-gcc -static -nostdlib -march=armv8-a ...
```

### Checking for Dynamic Linking
```bash
# WRONG - dynamic
xxd kernel.bin | head
# Output starts with: /lib/ld-linux-aarch64.so.1

# CORRECT - static
xxd kernel.bin | head
# Output starts with: fd7b b7a9 (ARM instructions)
```

---

## Issue 8: Binary Not Starting at Entry Point

### Symptom
`_start` function exists but binary contents start elsewhere.

### Root Cause
GCC reorders functions alphabetically by default. `_start` wasn't first in `.text` section.

### Resolution
1. Place `_start` in its own section: `__attribute__((section(".text.start")))`
2. Use linker flags: `-Wl,--section-start=.text.start=0x00080000`

---

## Issue 9: fpga loadb vs fpga load

### Original Command
```bash
fpga loadb 0 0x01000000 $filesize  # loadb = load with BIT header
```

### Problem
`system_wrapper.bin` is a **headerless .bin**, not a .bit with header.

### Resolution
Use `fpga load` for raw binary:
```bash
fpga load 0 0x01000000 $filesize  # load = load raw binary
```

### FPGA Load Commands
| Command | Format | Use Case |
|---------|--------|----------|
| `fpga load` | Raw binary (.bin) | Our case |
| `fpga loadb` | BIT file with header | Vivado .bit files |
| `fpga loadp` | Pxie/BOOT.BIN | Pre-built images |

---

## Issue 10: boot.scr Not Regenerated

### Symptom
boot.cmd updated but old script still running.

### Root Cause
U-Boot reads compiled `.scr` file, not `.cmd` text file.

### Resolution
Regenerate after any change:
```bash
mkimage -A arm64 -T script -C none -d boot.cmd boot.scr
```

---

## Issue 11: Linker Script Targets Wrong Architecture

### File: `boot/lscript.ld`

```c
// WRONG - Zynq-7000 (ps7)
MEMORY
{
   ps7_ram_0_S_AXI_BASEADDR : ORIGIN = 0x00000000
}

// CORRECT - Zynq UltraScale+ (psu)
MEMORY
{
   psu_ram_0_S_AXI_BASEADDR : ORIGIN = 0x00000000
}
```

### Note
This linker script is for FSBL, not the kernel. For the kernel, we used `-Ttext=0x00080000` linker flag instead.

---

## Issue 12: SD Card Location

### Symptom
```
Failed to load 'pxeboot/system.dtb'
```

### Root Cause
SD card mmc device number mismatch.

### Resolution
Know your SD card location:
- `mmc 0` = eMMC (onboard, not used)
- `mmc 1` = SD card slot

Use `mmc 1:1` for first partition on SD card.

---

## Boot Mode Override (Temporary)

For true SD card boot like traditional Zynq:

```uboot
ZynqMP> mw 0xff5e0200 0x00000005
ZynqMP> reset
```

**Warning:** This is temporary. Hard power cycle reverts to QSPI boot.

---

## Final Working Configuration

### boot.cmd (v1.2)
```bash
echo ========================================
echo IMP Boot Sequence v1.2 (aarch64)
echo ========================================

# 1. Program FPGA fabric
echo [1/5] Programming FPGA...
load mmc 1:1 0x01000000 system_wrapper.bin
fpga load 0 0x01000000 $filesize

# 2. Load Kernel
echo [2/5] Loading kernel to 0x00080000...
load mmc 1:1 0x00080000 imp/kernel.bin

# 3. Load 9B Model
echo [3/5] Loading model_9b.isp to 0x10000000...
load mmc 1:1 0x10000000 imp/model_9b.isp

# 4. Load Feeder
echo [4/5] Loading feeder.isp to 0xA0000000...
load mmc 1:1 0xA0000000 imp/feeder.isp

# 5. Execute
echo [5/5] Starting IMP kernel at 0x00080000...
go 0x00080000
```

### Compile Command
```bash
cd /path/to/imp
aarch64-linux-gnu-gcc -nostdlib -static -march=armv8-a -mlittle-endian \
    -ffreestanding -O2 -Ttext=0x00080000 \
    -Wl,--section-start=.text.start=0x00080000 \
    -o arm/kernel.elf arm/kernel.c
aarch64-linux-gnu-objcopy -O binary arm/kernel.elf arm/kernel.bin
```

---

## Key Takeaways

1. **KV260 is not a traditional Zynq** - It's Linux-first with opaque boot
2. **QSPI is mandatory** - No boot mode switches, must work with factory firmware
3. **Serial console is essential** - Can't debug without UART
4. **Memory map must be validated** - 4GB sounds big until you fit 9B+0.5B models
5. **Toolchain must be 64-bit** - ARMv8-A requires aarch64-*, not arm-*
6. **Static linking required** - No dynamic loader in bare-metal
7. **Binary entry point matters** - Ensure `_start` is first in binary
8. **File formats matter** - .bin vs .bit vs .elf have different headers

---

## Files Reference

### Ready-to-Use Files
| File | Location | Size |
|------|----------|------|
| boot.scr | `boot/boot.scr` | 1.2KB |
| system_wrapper.bin | `boot/system_wrapper.bin` | 7.5MB |
| kernel.bin | `arm/kernel.bin` | 3.6MB |
| model_9b.isp | `weights/model_9b.isp` | 2.2GB |
| feeder.isp | `weights/feeder.isp` | 828MB |

### Boot Memory Map
```
0x00080000  - Kernel entry (load address)
0x01000000  - Bitstream loading (temporary)
0x10000000  - 9B Model weights
0xA0000000  - Feeder weights
0xD4000000  - Working RAM
0x8000A000  - FPGA MMIO (AXI4-Lite)
```

---

## Next Steps (If Continuing)

1. Test boot on hardware with corrected configuration
2. Verify FPGA programs successfully
3. Verify kernel executes and prints to UART
4. Debug any remaining issues
5. (Optional) Burn to QSPI for production appliance mode
