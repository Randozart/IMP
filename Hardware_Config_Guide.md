<!--
IMP Hardware Configuration Guide - Memory mapping for hardware generation
    Copyright (C) 2026 Randy Smits-Schreuder Goedheijt
-->

# Hardware Configuration Guide

This guide explains how to configure `hardware.ooml` for your FPGA target, specifically optimized for the KV260 but applicable to any FPGA.

## Quick Reference

### Memory Types

| Type | Use Case | Example |
|------|----------|---------|
| `flipflop` | Control registers, single values | `size = 1` |
| `bram` | Medium buffers (1K-256K elements) | `size = 65536` |
| `ultraram` | Large buffers (256K-2M elements) | `size = 262144` |
| `ddr4` | Very large (requires AXI DMA) | Future |

### KV260 Physical Limits

- **BRAM**: 518KB (144 × 36Kb blocks)
- **UltraRAM**: 2.25MB (64 × 288Kb blocks)  
- **Logic Cells**: 256K
- **DSP**: 1,200

### Address Width

The address width must be large enough to address your buffer size:

```
bits_needed = ceil(log2(elements))
```

| Elements | Min Bits | Recommended |
|----------|----------|-------------|
| 1K | 10 | 16 |
| 64K | 16 | 18 |
| 256K | 18 | 18 |
| 1M | 20 | 20 |

**CRITICAL**: If you have 256K elements, you MUST use at least 18-bit address. The compiler will fail or generate incorrect code otherwise.

## Example: KV260 Neural Core

```toml
[project]
name = "imp"
version = "0.1.0"

[target]
fpga = "xczu4ev-sfvc784-1"  # KV260
clock_hz = 100_000_000

[interface]
name = "axi4-lite"  # Use axi4-ful for DMA
address_width = 18  # Must match max buffer size!
data_width = 32

[memory]
# Control registers (flipflop)
"0x4000A000" = { size = 1, type = "flipflop", element_bits = 8 }
"0x40000a04" = { size = 1, type = "flipflop", element_bits = 8 }

# CPU interface (18-bit address for 262K elements)
"0x40000a40" = { size = 1, type = "flipflop", element_bits = 16 }  # write_data
"0x40000a44" = { size = 1, type = "flipflop", element_bits = 18 }  # write_addr - 18-bit!
"0x40000a48" = { size = 1, type = "flipflop", element_bits = 1 }   # write_en

# BRAM buffers (fits in 518KB)
"0x40010000" = { size = 65536, type = "bram", element_bits = 16 }  # ~128KB
"0x40020000" = { size = 65536, type = "bram", element_bits = 16 }  # ~128KB

# UltraRAM buffers (fits in 2.25MB)
"0x40030000" = { size = 262144, type = "ultraram", element_bits = 16 }  # 512KB
"0x40050000" = { size = 262144, type = "ultraram", element_bits = 16 }  # 512KB
```

## Common Mistakes

### 1. Address bits too small

```toml
# WRONG - 16-bit address can only address 65K elements
"0x40000a44" = { size = 1, type = "flipflop", element_bits = 16 }

# CORRECT - 18-bit for 262K elements
"0x40000a44" = { size = 1, type = "flipflop", element_bits = 18 }
```

### 2. Buffer too large for memory type

```toml
# WRONG - 1M elements needs ~2MB, BRAM only has 518KB
"0x400a0000" = { size = 1048576, type = "bram", element_bits = 16 }

# CORRECT - Use UltraRAM for large buffers
"0x400a0000" = { size = 262144, type = "ultraram", element_bits = 16 }  # 512KB
```

### 3. Not using RAM template for large vectors

The compiler automatically detects memory type:
- `type = "bram"` or `type = "ultraram"` → generates RAM template (single always_ff)
- `type = "flipflop"` → generates unrolled for-loop (broken for large arrays)

This is the fix from the second review - prevents Vivado from trying to synthesize millions of flip-flops.

## AXI Interface Selection

### AXI4-Lite (Current)
- CPU controls everything
- One word at a time
- ~10-50 MB/s
- OK for control registers

### AXI4-Full (Future)
- FPGA has DMA engine
- Burst reads/writes
- ~19 GB/s
- Required for DDR4 model weights

## File Locations

Hardware specs are in `brief-compiler/hardware_ooml/`:
- `targets/` - Target device specs
- `memory/` - Memory type definitions  
- `interfaces/` - AXI interface definitions

User hardware.ooml files override these defaults.

---

*Last updated: April 2026*