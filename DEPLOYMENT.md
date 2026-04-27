# IMP Kernel Build & Deployment Guide

## Overview

This document details the complete build process for the IMP (Inference Machine Pipeline) kernel for KV260.

## Hardware Memory Map

| Address | Size | Description |
|---------|------|-------------|
| 0x00000000 | 512MB | U-Boot + Low RAM |
| 0x20000000 | 512KB | IMP Kernel (entry point) |
| 0x20080000 | 512KB | Stack |
| 0x10000000 | 512MB | Model weights (9B) |
| 0x70000000 | 128MB | Feeder weights (0.5B) |
| 0x8000A000 | 4KB | FPGA MMIO (AXI4-Lite) |
| 0xFF0A0000 | 4KB | UART0 |

## Build Process

### Prerequisites

```bash
# Install ARM64 cross-compiler
sudo apt install gcc-aarch64-linux-gnu

# Verify installation
aarch64-linux-gnu-gcc --version
```

### Building the Kernel

```bash
cd /home/randozart/Desktop/Projects/imp
chmod +x scripts/build_kernel.sh
./scripts/build_kernel.sh
```

### Output Files

| File | Size | Purpose |
|------|------|---------|
| `arm/kernel.elf` | 73KB | ELF executable (debug) |
| `arm/kernel.bin` | 5.5KB | Raw binary (production) |

### Build Verification

```bash
# Check entry point
aarch64-linux-gnu-nm arm/kernel.elf | grep _start

# Check disassembly
aarch64-linux-gnu-objdump -d arm/kernel.elf | head -30

# Verify binary header (should NOT start with 7f 45 4c 46)
xxd -l 16 arm/kernel.bin
```

## Deployment

### SD Card Layout

```
/boot/
├── BOOT.BIN           (9.1MB - FSBL + bitstream)
├── system_wrapper.bit (7.5MB - FPGA bitstream)
├── kernel.elf         (73KB - for testing)
├── kernel.bin         (5.5KB - production)
├── imp/
│   ├── model_9b.isp   (2.2GB - 9B model)
│   ├── feeder.isp     (828MB - 0.5B model)
│   └── neuralcore.bit (7.5MB - backup)
```

### U-Boot Commands (KV260)

#### Step 1: Program FPGA (if not using BOOT.BIN)
```uboot
fatload mmc 1:1 0x08000000 imp/neuralcore.bit
fpga loadb 0 0x08000000 $filesize
```

#### Step 2: Load Kernel
```uboot
fatload mmc 1:1 0x20000000 imp/kernel.bin
```

#### Step 3: Execute
```uboot
go 0x20000000
```

### Expected Output

```
========================================
IMP Kernel v1.0 - KV260
Ternary Neural Network Inference
========================================

Build: Apr 26 2026 19:39:12
Entry: 0x20000000
Stack: 0x20080000

[1/6] Initializing UART... OK
[2/6] Initializing SD card... OK
[3/6] Initializing FAT filesystem... OK
[4/6] Loading model_9b.isp to DDR4 @ 0x10000000... SKIPPED
[5/6] Loading feeder.isp to DDR4 @ 0x70000000... SKIPPED
[6/6] Verifying FPGA connection... OK (status=0x0)

========================================
IMP Ready for Inference!
========================================

MMIO Registers:
  0x8000A000 - control   (write)
  0x8000A004 - status    (read)
  0x8000A008 - opcode    (write)
  0x8000A00C - token_count
  0x8000A040 - write_data
  0x8000A050 - read_data

Commands:
  1 - Load weights to FPGA
  2 - Send input tokens
  3 - Execute layer
  4 - Read results
  h - Help

IMP>
```

## Troubleshooting

### Synchronous Abort (esr 0x02000000)

**Cause**: Executing ELF header as ARM instructions

**Solution**: Use raw binary (`kernel.bin`) not ELF (`kernel.elf`)

### Memory Collision

**Cause**: Kernel at 0x00120000 conflicting with U-Boot

**Solution**: Use address 0x20000000 (safe zone)

### FPGA Not Responding

**Cause**: Bitstream not loaded

**Solution**: 
```uboot
fatload mmc 1:1 0x08000000 imp/neuralcore.bit
fpga loadb 0 0x08000000 $filesize
```

## Kernel Commands (Interactive)

| Key | Action |
|-----|--------|
| 1 | Load weights to FPGA |
| 2 | Send input tokens |
| 3 | Execute layer |
| 4 | Read results |
| h | Help |

## Source Files

```
arm/
├── kernel.c           # Main kernel source
├── linker.ld         # Linker script (0x20000000)
├── kernel.elf        # Built ELF executable
├── kernel.bin        # Built raw binary
├── README.md         # This guide
└── build_kernel.sh   # Build script
```

## Memory Layout (Linker Script)

```ld
MEMORY
{
    KERNEL (rwx) : ORIGIN = 0x20000000, LENGTH = 0x00080000
    STACK       : ORIGIN = 0x20080000, LENGTH = 0x00080000
}

SECTIONS
{
    .text 0x20000000 : { *(.text.start) } > KERNEL
    .data : { *(.data) } > KERNEL
    .bss  : { *(.bss) } > KERNEL
    .stack : { *(.stack) } > STACK
}
```

## Version History

| Date | Version | Changes |
|------|---------|---------|
| 2026-04-26 | 1.0 | Initial build with UART, SD, FAT, FPGA MMIO |
| 2026-04-26 | 1.1 | Fixed linker script for 0x20000000 base |

## Notes

- Kernel loads at 0x20000000 (safe zone above U-Boot)
- Raw binary (not ELF) required for `go` command
- FPGA must be programmed before kernel runs
- UART0 at 115200 baud, 8N1