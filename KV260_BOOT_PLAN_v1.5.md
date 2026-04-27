# IMP v1.5 Boot Plan: Brief-Generated Split-Model Kernel

**Date:** 2026-04-27
**Status:** SPECIFICATION
**Goal:** Boot IMP kernel generated from Brief specifications with split model across both DDR banks

---

## Executive Summary

This boot plan specifies the complete IMP v1.5 system where:
1. **Kernel software** is generated from `kernel.ebv` Brief spec via `brief-compiler c`
2. **FPGA logic** is generated from `neuralcore.ebv` Brief spec via `brief-compiler sv`
3. **Linkage** between SV and C is defined in `linkage.toml`
4. **Model** is split across both DDR banks (v1.4 architecture)

---

## Memory Architecture

### Zynq UltraScale+ DDR4 Layout

```
┌─────────────────────────────────────────────────────────────────────┐
│  LOW BANK (2GB)                    │ MMIO GAP (2GB) │ HIGH BANK (2GB)│
│  0x00000000 - 0x7FFFFFFF           │ 0x80000000      │ 0x800000000-    │
│                                   │ - 0x7FFFFFFF    │ 0x87FFFFFFF     │
└─────────────────────────────────────────────────────────────────────┘
```

| Region | Address Range | Size | Purpose |
|--------|--------------|------|---------|
| Model Part A | 0x00000000 | ~1.1GB | Foundation model weights |
| Context Cache A | 0x46800000 | ~1.45GB | KV cache, activations |
| **GAP** | 0x80000000 - 0x7FFFFFFF | 2GB | MMIO registers (NO USE) |
| Model Part B | 0x800000000 | ~1.1GB | Foundation model continuation |
| Context Cache B | 0x86C000000 | ~984MB | KV cache, activations |
| Kernel | 0x00100000 | 4MB | ARM bare-metal kernel |

### Model Split Logic

```
Virtual Model Index (0 to ~2.2GB)
         │
         ▼
┌─────────────────┐
│ < 1.1GB (A_SIZE)?│
└────────┬────────┘
         │
    YES  │  NO
         ▼    │
┌─────────v─────────┐    ┌─────────────────────────────────┐
│ PHYSICAL_A_BASE  │    │ PHYSICAL_B_BASE +                 │
│ + virt_idx       │    │ (virt_idx - A_SIZE)              │
└─────────────────┘    └─────────────────────────────────┘
```

---

## Brief Specification Files

### 1. kernel.ebv (ARM Software Layer)

**File:** `imp/kernel.ebv`

```brief
// IMP Kernel v1.5 - ARM Software Layer
// Generated to C for bare-metal ARM execution

// === Hardware Interface (from FPGA via AXI4-Lite) ===
trg hw_control: UInt @ link hw_control;
trg hw_status: UInt @ link hw_status;
trg hw_opcode: UInt @ link hw_opcode;

// === Memory Regions (split model) ===
let MODEL_A_BASE: UInt = 0x00000000;
let MODEL_B_BASE: UInt = 0x800000000;
let MODEL_A_SIZE: UInt = 0x46800000;  // ~1.1GB
let CACHE_A_BASE: UInt = 0x46800000;
let CACHE_B_BASE: UInt = 0x86C000000;

// === State ===
let kernel_state: UInt = 0;
let model_parts_loaded: Bool = false;

// === Cache Coherency (ARM DC CIVAC) ===
txn flush_cache [[true]] [[true]] {
    effect {
        // DC CIVAC X0, X1 - clean and invalidate cache line
        // DSB SY - ensure memory ordering
        asm "DC CIVAC X0, X1" { "x0", "x1" };
        asm "DSB SY" {};
    };
};

// === Model Loading (called from boot) ===
txn load_model_parts [[model_parts_loaded == false]] [[model_parts_loaded == true]] {
    &kernel_state = 1;
    term;
};

// === Gap-Jumping Weight Read ===
// Virtual index -> physical address across 2GB gap
txn read_weight [[kernel_state >= 1]] [[kernel_state >= 1]] {
    let virt_addr: UInt = 0;
    let phys_addr: UInt = 0;
    let value: Int = 0;
    term;
};

// === Main Loop ===
txn check_ready [[kernel_state == 1 && model_parts_loaded]] [[kernel_state == 2]] {
    &kernel_state = 2;
    term;
};

txn idle_loop [[kernel_state == 2]] [[kernel_state == 2]] {
    &kernel_state = 2;
    term;
};
```

### 2. neuralcore.ebv (FPGA Hardware Layer)

**File:** `imp/neuralcore.ebv`

```brief
// IMP Neural Core v1.5 - FPGA Hardware Layer
// Generated to SystemVerilog for Xilinx UltraScale+

// === CPU Interface (from ARM via AXI4-Lite) ===
trg cpu_control: UInt @ link cpu_control;
trg cpu_status: UInt @ link cpu_status;
trg cpu_opcode: UInt @ link cpu_opcode;
trg cpu_write_data: Int @ link cpu_write_data;
trg cpu_write_addr: UInt @ link cpu_write_addr;
trg cpu_write_en: Bool @ link cpu_write_en;
trg cpu_read_en: Bool @ link cpu_read_en;

// === BRAM for Active Layer Weights (512KB) ===
let weight_buffer: Int[262144] @ link weight_buffer;

// === BRAM for Activations/Scratch (2.25MB) ===
let scratch: Int[262144] @ link scratch;

// === FSM States ===
let calc_index: UInt = 0;
let calc_phase: UInt = 0;

// === TERNARY MAC Operations ===
txn ternary_mac [[calc_phase >= 1 && calc_phase <= 4 && calc_index < 262144]] [[true]] {
    let input_val: Int = scratch[calc_index];
    let weight_val: Int = weight_buffer[calc_index];
    let acc: Int = 0;
    // Ternary: +1 adds, -1 subtracts, 0 skips
    [weight_val == 1] acc = acc + input_val;
    [weight_val + 1 == 0] acc = acc - input_val;
    [weight_val == 0] acc = acc;
    term;
};
```

### 3. linkage.toml (Cross-Language Address Mapping)

**File:** `imp/linkage.toml`

```toml
# IMP v1.5 Linkage Configuration
# Maps Brief @ link names to actual addresses/signals per target

[links]

# FPGA MMIO (AXI4-Lite from ARM perspective)
hw_control = { sv = "hw_control_reg", rust = "0x8000A000", c = "0x8000A000" }
hw_status = { sv = "hw_status_reg", rust = "0x8000A004", c = "0x8000A004" }
hw_opcode = { sv = "hw_opcode_reg", rust = "0x8000A008", c = "0x8000A008" }
cpu_control = { sv = "cpu_control_reg", rust = "0x8000A000", c = "0x8000A000" }
cpu_status = { sv = "cpu_status_reg", rust = "0x8000A004", c = "0x8000A004" }
cpu_opcode = { sv = "cpu_opcode_reg", rust = "0x8000A008", c = "0x8000A008" }
cpu_write_data = { sv = "cpu_write_data_reg", rust = "0x8000A040", c = "0x8000A040" }
cpu_write_addr = { sv = "cpu_write_addr_reg", rust = "0x8000A044", c = "0x8000A044" }
cpu_write_en = { sv = "cpu_write_en_reg", rust = "0x8000A048", c = "0x8000A048" }
cpu_read_en = { sv = "cpu_read_en_reg", rust = "0x8000A04C", c = "0x8000A04C" }

# BRAM Addresses (FPGA fabric)
weight_buffer = { sv = "weight_bram", rust = "0x40A80000", c = "0x40A80000" }
scratch = { sv = "scratch_bram", rust = "0x40B00000", c = "0x40B00000" }

# DDR4 Memory Regions
model_a_base = { sv = "unused", rust = "0x00000000", c = "0x00000000" }
model_b_base = { sv = "unused", rust = "0x800000000", c = "0x800000000" }
cache_a_base = { sv = "unused", rust = "0x46800000", c = "0x46800000" }
cache_b_base = { sv = "unused", rust = "0x86C000000", c = "0x86C000000" }
```

---

## Build Pipeline

### Step 1: Generate SystemVerilog (FPGA)

```bash
cd /home/randozart/Desktop/Projects/imp
./brief-compiler sv neuralcore.ebv --hw hardware.toml --out verilog/
```

**Output:** `neuralcore.sv` with:
- AXI4-Lite slave interface for ARM communication
- BRAM instances for weight_buffer and scratch
- Ternary MAC FSM

### Step 2: Generate C (ARM Kernel)

```bash
cd /home/randozart/Desktop/Projects/imp
./brief-compiler c kernel.ebv --out arm/
```

**Output:** `kernel.c` with:
- Memory region definitions
- Gap-jumping weight read functions
- Cache coherency via `__asm__ __volatile__`
- Transaction state machine

### Step 3: Compile Kernel

```bash
cd /home/randozart/Desktop/Projects/imp/arm
aarch64-linux-gnu-gcc -nostdlib -static -march=armv8-a \
    -ffreestanding -O2 -T linker.ld -o kernel.elf kernel.c
aarch64-linux-gnu-objcopy -O binary kernel.elf kernel.bin
```

---

## boot.cmd (U-Boot Script)

**File:** `imp/boot/boot.cmd`

```bash
echo ========================================
echo IMP Boot v1.5 (Brief-Generated)
echo ========================================

# 1. Program FPGA
echo [1/6] Programming FPGA...
load mmc 1:1 0x01000000 system_wrapper.bin
fpga load 0 0x01000000 $filesize

# 2. Load Kernel
echo [2/6] Loading kernel to 0x00100000...
load mmc 1:1 0x00100000 imp/kernel.bin

# 3. Load Model Part A (Low Bank)
echo [3a/6] Loading model Part A...
load mmc 1:1 0x00000000 imp/model_part.aa

# 4. Load Model Part B (High Bank)
echo [3b/6] Loading model Part B...
load mmc 1:1 0x800000000 imp/model_part.ab

# 5. Setup done
echo [4/6] Memory initialized...
echo [5/6] Model loaded...

# 6. Boot kernel
echo [6/6] Starting IMP...
go 0x00100000
```

**Regenerate:**
```bash
cd /home/randozart/Desktop/Projects/imp/boot
mkimage -A arm64 -T script -C none -d boot.cmd boot.scr
```

---

## Model Splitting

### On Development PC

```bash
cd /home/randozart/Desktop/Projects/imp/weights
split -b 1100M model_9b.isp model_part.
```

### Copy to SD Card

```
/boot.scr
/system_wrapper.bin
/imp/
├── kernel.bin
├── model_part.aa      # ~1.1GB -> Low bank 0x00000000
└── model_part.ab      # ~1.1GB -> High bank 0x800000000
```

---

## Generated kernel.c (Expected Output)

```c
// IMP Kernel v1.5 - Generated from kernel.ebv
// DO NOT EDIT - Regenerate from Brief spec

#include <stdint.h>
#include <stdbool.h>

// Memory regions
#define MODEL_A_BASE    0x00000000
#define MODEL_B_BASE    0x800000000
#define MODEL_A_SIZE    0x46800000
#define CACHE_A_BASE    0x46800000
#define CACHE_B_BASE    0x86C000000

// FPGA MMIO
#define FPGA_CONTROL    (*(volatile uint32_t *)0x8000A000)
#define FPGA_STATUS     (*(volatile uint32_t *)0x8000A004)
#define FPGA_OPCODE     (*(volatile uint32_t *)0x8000A008)

// State
static uint32_t kernel_state = 0;
static bool model_parts_loaded = false;

// Cache coherency - ARM DC CIVAC
static void flush_cache(void *addr) {
    __asm__ __volatile__("DC CIVAC X0, X1" : : : "x0", "x1");
    __asm__ __volatile__("DSB SY" : : :);
}

// Gap-jumping weight read
static int8_t read_weight_uint8(uint64_t virt_idx) {
    uint64_t phys_addr;
    if (virt_idx < MODEL_A_SIZE) {
        phys_addr = MODEL_A_BASE + virt_idx;
    } else {
        phys_addr = MODEL_B_BASE + (virt_idx - MODEL_A_SIZE);
    }
    flush_cache((void *)phys_addr);
    return *(volatile int8_t *)phys_addr;
}

// Main
void main(void) {
    // ... initialization ...
}
```

---

## Expected Boot Output

```
IMP Boot v1.5 (Brief-Generated)
========================================
[1/6] Programming FPGA...
7797810 bytes read in 516 ms
FPGA programmed successfully.
[2/6] Loading kernel to 0x00100000...
3670396 bytes read in 262 ms
[3a/6] Loading model Part A...
1181116000 bytes read in 62310 ms
[3b/6] Loading model Part B...
1181116000 bytes read in 62310 ms
[4/6] Memory initialized...
[5/6] Model loaded...
[6/6] Starting IMP...
========================================
IMP Kernel v1.5 (Brief-Generated)
========================================
[1/4] Initializing hardware... OK
[2/4] Verifying model... OK (2.2GB split)
[3/4] Setting up cache coherency... OK
[4/4] Ready for inference... OK
========================================
```

---

## Testing Checklist

- [ ] `brief-compiler c kernel.ebv` generates valid C
- [ ] `brief-compiler sv neuralcore.ebv --hw hw.toml` generates valid SV
- [ ] `aarch64-linux-gnu-gcc` compiles generated C without errors
- [ ] Model splits correctly with `split -b 1100M`
- [ ] boot.cmd loads kernel at 0x00100000
- [ ] boot.cmd loads model_part.aa at 0x00000000
- [ ] boot.cmd loads model_part.ab at 0x800000000
- [ ] Kernel boots and prints to UART
- [ ] FPGA programs successfully
- [ ] Weight reads work across gap (virt_idx test)

---

## Files Summary

| File | Purpose | Generated |
|------|---------|-----------|
| `kernel.ebv` | ARM kernel specification | No |
| `neuralcore.ebv` | FPGA core specification | No |
| `linkage.toml` | Address mapping | No |
| `kernel.c` | Generated C kernel | **Yes** |
| `neuralcore.sv` | Generated SystemVerilog | **Yes** |
| `boot.cmd` | U-Boot boot script | No |
| `boot.scr` | Compiled boot script | **Yes** |
| `model_part.aa` | Model Part A (split) | **Yes** |
| `model_part.ab` | Model Part B (split) | **Yes** |

---

## References

- `KV260_BOOT_LESSONS.md` - Previous boot issues
- `IMPLEMENTATION_WITH_LINK_SYNTAX.md` - Brief @ link documentation
- `NATIVE_BACKENDS.md` - Brief compiler backends
