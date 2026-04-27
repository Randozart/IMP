# Bare-Metal Failures: IMP Development Diary

## Overview

This document chronicles the extensive debugging journey of attempting to boot a custom bare-metal kernel on the KV260 Vision AI Starter Kit. It serves as both a learning record and a warning for future developers.

**Status: ABANDONED in favor of PetaLinux**

---

## Timeline of Failures

### 2026-04-24: Initial Setup
- Created custom linker script placing kernel at `0x00000000`
- Compiled kernel as ELF executable
- Booted via `fatload mmc 1:1 0x00100000 kernel.elf`
- Result: **Synchronous Abort** (esr 0x02000000)

### 2026-04-24: ELF Header Disaster
- **Root Cause**: U-Boot's `bootelf` command parsed ELF metadata
- **Symptom**: CPU tried to execute `.ELF` string as ARM instructions
- **Bytes**: `7f 45 4c 46` interpreted as invalid ARM opcode
- **Lesson**: Bare-metal cannot use ELF; must use raw binary

### 2026-04-25: Memory Collision Crisis
- **Root Cause**: U-Boot actively using low memory regions
- **Symptom**: U-Boot corrupted, system became unstable
- **Addresses Confused**:
  - Kernel at `0x00120000` (U-Boot's load zone)
  - Stack/heap at `0x00100000` (U-Boot's working memory)
- **Lesson**: Never load code where U-Boot is executing

### 2026-04-25: Address Migration Attempts
- **Attempt 1**: Move kernel to `0x10000000` → Failed (model weights conflict)
- **Attempt 2**: Move kernel to `0x20000000` → Partially worked
- **Attempt 3**: Use separate DDR4 bank `0x80000000` → Failed (bank not accessible)

### 2026-04-26: Model Loading Catastrophe
- **Root Cause**: U-Boot memory reservations for "loaded files"
- **Symptom**: `fatload` fails with "Reading file would overwrite reserved memory"
- **Attempted Addresses**:
  - `0x10000000` → Reserved by U-Boot
  - `0x40000000` → Reserved by U-Boot
  - `0x80000000` → Reserved by U-Boot
- **Model Size Problem**: 2.2GB model too large for contiguous space in bank 0
- **Lesson**: U-Boot's malloc pool and file loading subsystem are opaque

### 2026-04-26: QSPI Boot Mode Complications
- **Root Cause**: KV260 boots from QSPI by default (no switches for SD boot)
- **Symptom**: `boot.scr` not auto-executed
- **Partial Solution**: Manual boot sequence required each power cycle
- **Lesson**: KV260 hardware has limited boot mode selection

### 2026-04-26: Kernel Stubs vs Real Implementation
- **Problem**: Kernel `sd_init()` and `fat_read_file()` were stubs
- **Consequence**: Even with correct boot, model couldn't load from kernel
- **Realization**: Full SD/FAT driver implementation required for bare-metal
- **Lesson**: "Stubs that print OK" are not the same as "working drivers"

---

## Root Cause Analysis

### Why U-Boot's Memory Management Is Opaque

1. **Internal Reservations**: U-Boot tracks loaded files internally
2. **No Public API**: No way to query available memory ranges
3. **Dynamic Allocation**: `bdinfo` shows reserves but values change
4. **Documentation Gap**: Xilinx forums have conflicting advice

### Why Bare-Metal SD Access Is Hard

1. **No Filesystem Driver**: FAT parsing requires significant code
2. **No DMA**: CPU-bound block reads are slow
3. **No Interrupt Handling**: Polling required, timeouts complex
4. **No Memory Management**: Fragmentation if loading large files

### Why 2.2GB Model Breaks Everything

1. **Contiguous Requirement**: Model must be in one physical chunk
2. **U-Boot Reservations**: 132MB+ of bank 0 is reserved
3. **Bank 1 Uncertainty**: `0x80000000` region unclear if accessible
4. **DDR4 Topology**: KV260 has 2x2GB in non-interleaved mode?

---

## What We Tried

| Attempt | Address | Result | Problem |
|---------|---------|--------|---------|
| ELF at 0x0 | 0x00000000 | Crash | Executed ELF header |
| ELF at 0x10000000 | 0x10000000 | Crash | Memory collision |
| ELF at 0x00100000 | 0x00100000 | Crash | U-Boot working memory |
| Raw at 0x20000000 | 0x20000000 | Partial | Kernel boots, no model |
| Model at 0x10000000 | 0x10000000 | Failed | U-Boot reserved |
| Model at 0x40000000 | 0x40000000 | Failed | U-Boot reserved |
| Model at 0x80000000 | 0x80000000 | Failed | U-Boot reserved |
| Feeder at 0x70000000 | 0x70000000 | Unknown | Not tested |

---

## Technical Data Collected

### U-Boot Memory Map (from `bdinfo`)

```
DRAM bank 0: 0x0000000000000000 - 0x0000000080000000 (2GB)
DRAM bank 1: 0x0000000800000000 - 0x0000000880000000 (2GB)

reserved[0]: 0x7b8100a0 - 0x7fdfffff (~132MB)
reserved[1]: 0x7ff00000 - 0x7fffffff (1MB)
```

### U-Boot File Load Reservations

```
Load segment with RWX permissions: kernel.elf
  Physical memory mapping detected
  -> fatload tracks loaded regions internally
  -> No way to release without reset
```

---

## Key Files Involved

| File | Purpose | Problem |
|------|---------|---------|
| `arm/linker.ld` | Memory layout | Original 0x0 address |
| `arm/memory.ld` | Alternative script | Still collides |
| `arm/kernel.c` | Kernel source | SD/FAT stubs |
| `boot/boot.cmd` | Boot script | Wrong addresses |
| `boot/boot.scr` | Compiled script | Not auto-executed |

---

## Lessons Learned

### Hardware Lessons

1. **Always read the memory map first**: U-Boot + Linux + FPGA all compete
2. **QSPI boot is default on KV260**: SD boot requires manual intervention
3. **No boot mode switches on KV260**: Unlike other Xilinx boards
4. **4GB RAM is in two banks**: Non-interleaved, different access

### Software Lessons

1. **ELF is for OS, not bare-metal**: Always use raw binary with `go`
2. **Link address != Load address**: Must match exactly
3. **U-Boot `fatload` is not free**: It allocates and tracks memory
4. **Stub functions are lies**: "Implemented" ≠ "Works"

### Debug Lessons

1. **`bdinfo` is essential**: Shows actual memory layout
2. **Serial console is mandatory**: No other way to see errors
3. **`reset` clears reservations**: U-Boot state not persistent
4. **Hex dump everything**: Verify actual bytes, not assumptions

---

## Alternative Approaches Considered

### Option 1: TFTP Network Load (Rejected)
- Requires network infrastructure
- Model still needs DDR4 storage
- Adds complexity without solving root problem

### Option 2: Custom U-Boot Build (Rejected)
- Would require modifying U-Boot source
- Long rebuild times
- Uncertain if it would solve memory issues

### Option 3: Chain Loading (Rejected)
- Custom second-stage bootloader
- Essentially reimplementing Linux
- Beyond project scope

### Option 4: Linux Driver for Model Loading (Chosen)
- Let Linux manage memory
- Standard filesystem access
- Proven, maintainable solution

---

## Why We Switched to PetaLinux

1. **Memory Management**: Linux MMU handles fragmentation
2. **Filesystem**: Normal `open()`/`read()` for 2.2GB file
3. **Drivers**: Built-in SD card, no custom code needed
4. **Reliability**: Standard boot process, no manual commands
5. **Maintenance**: Well-documented, community-supported

---

## Final Recommendations for Future Developers

### If You Insist on Bare-Metal

1. **Use a tiny test model** (< 1MB) to verify boot first
2. **Implement SD driver from scratch** (don't use stubs)
3. **Allocate memory statically** (don't rely on malloc)
4. **Add memory dump command** to U-Boot for debugging
5. **Consider ARM Trusted Firmware** for memory isolation

### If You Want Best Results

1. **Start with PetaLinux** (this project now recommends this)
2. **Use Xilinx XDMA** for FPGA access (not custom MMIO)
3. **Follow Xilinx reference designs** for memory maps
4. **Test incrementally**: Boot → FPGA → Model → Inference

---

## Appendices

### A. Serial Output: First Crash

```
Synchronous Abort
esr 0x02000000
ec 0x92000061
...
Code: 05000000 1e000000 06000000 1e000000 (464c457f)
```

### B. Serial Output: Memory Reservation Error

```
ZynqMP> fatload mmc 1:1 0x10000000 imp/model_9b.isp
** Reading file would overwrite reserved memory **
Failed to load 'imp/model_9b.isp'
```

### C. Commands That Were Tried

```uboot
# Attempt 1: Direct ELF boot
fatload mmc 1:1 0x00100000 kernel.elf
bootelf 0x00100000

# Attempt 2: Raw binary with go
fatload mmc 1:1 0x20000000 kernel.bin
go 0x20000000

# Attempt 3: Explicit memory clear
setenv filesize
fatload mmc 1:1 0x10000000 imp/model_9b.isp

# Attempt 4: Using alternative bank
fatload mmc 1:1 0x80000000 imp/model_9b.isp

# Attempt 5: Chunk loading (never finished)
setenv filesize 536870912
fatload mmc 1:1 0x10000000 imp/model_9b.bin
```

### D. Links to Relevant Documentation

- [Xilinx KV260 Documentation](https://www.xilinx.com/support/documentation/boards_and_kits/1.4/ug-kria-vision-ai-starter-kit.pdf)
- [U-Boot Memory Management](https://u-boot.readthedocs.io/en/latest/)
- [ARM64 Bare Metal Programming](https://github.com/alexheal/AArch64-Bare-Metal-Setup)
- [PetaLinux Tools Documentation](https://docs.xilinx.com/r/2023.2-English/ug1144-petalinux-tools-reference.pdf)

---

## Conclusion

The bare-metal approach failed because:

1. **Memory complexity**: U-Boot + bare-metal + 2.2GB model doesn't fit
2. **Time constraints**: Full SD/FAT driver would take weeks
3. **Risk**: No guarantee even with full implementation

The pragmatic solution was to use PetaLinux, which handles all the memory management and filesystem issues that killed this project.

**Status**: Project continuing with PetaLinux. See `PETA_LINUX_SETUP.md` and `IMP_QUICK_START.md`.

---

*Document created: 2026-04-26*
*Reason for abandonment: Persistent memory management issues with U-Boot prevent model loading*