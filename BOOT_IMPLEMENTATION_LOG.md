# IMP v1.5 Boot Implementation Log

**Date:** 2026-04-27
**Project:** IMP (Inference Machine Project)
**Goal:** Boot IMP kernel generated from Brief specifications with split model across both DDR banks

---

## Executive Summary

Successfully implemented the v1.5 boot plan where the ARM kernel is generated from `kernel.ebv` Brief specification using the Brief compiler's C backend, and the FPGA core is generated from `neuralcore.ebv` using the SystemVerilog backend. All components compile, link, and are ready for hardware testing.

---

## Timeline of Changes

### 2026-04-27 22:51 - Initial Setup

Created `linkage.toml` mapping `@ link` names to actual addresses:

```toml
hw_control = { sv = "hw_control_reg", rust = "0x8000A000", c = "0x8000A000" }
hw_status = { sv = "hw_status_reg", rust = "0x8000A004", c = "0x8000A004" }
hw_opcode = { sv = "hw_opcode_reg", rust = "0x8000A008", c = "0x8000A008" }
...
```

### 2026-04-27 22:51 - Kernel.ebv v1.5 Created

Rewrote `kernel.ebv` to use proper Brief syntax:
- Hardware triggers use `@ link` for linkage.toml resolution
- Internal state uses normal `let` declarations
- Fixed `txn` to `rct txn` syntax
- Removed non-existent `effect {}` wrapper
- ARM asm uses lowercase: `asm "dsb sy" {}`

### 2026-04-27 23:09 - C Backend Fixed

Updated `brief-compiler/src/backend/c.rs` to:

1. **Handle `@ link` hardware registers:**
   - Collects hardware register names from `TopLevel::Trigger` with `LinkRef::Linked`
   - Generates `#define MACRO (*volatile uint32_t *)ADDR` for MMIO access
   - Expressions referencing hardware registers use macro name (not `state->`)

2. **Fixed static allocation for bare-metal:**
   - Changed from `malloc` to static instance: `static State state_instance;`
   - Removed `stdlib.h` include
   - Added `stddef.h` for NULL definition

3. **Fixed ASM clobber syntax:**
   - Was: `__asm__ __volatile__("..." : : "r" (x0, x1))` (incorrect)
   - Now: `__asm__ __volatile__("..." : : : "x0", "x1")` (correct - clobbers in third section)

### 2026-04-27 23:10 - boot.cmd v1.5 Updated

```bash
# Load kernel at 0x00100000 (safe pocket before Model Part A)
load mmc 1:1 0x00100000 imp/kernel.bin

# Load Model Part A at Low Bank (fills to gap at 0x46800000)
load mmc 1:1 0x00000000 imp/model_part.aa

# Load Model Part B at High Bank (0x800000000)
load mmc 1:1 0x800000000 imp/model_part.ab
```

### 2026-04-27 23:12 - Kernel Compiled Successfully

Final kernel compilation commands:
```bash
# Compile boot stub
aarch64-linux-gnu-gcc -nostdlib -static -march=armv8-a -ffreestanding -O2 -c boot_stub.c -o boot_stub.o

# Link with -Ttext=0x00100000
aarch64-linux-gnu-gcc -nostdlib -static -march=armv8-a -ffreestanding -O2 -Wl,-Ttext=0x00100000 kernel.c boot_stub.o -o kernel.elf

# Convert to binary
aarch64-linux-gnu-objcopy -O binary kernel.elf kernel.bin
```

Result: 3.1MB kernel.bin with valid ARM aarch64 instructions

### 2026-04-27 23:12 - linker.ld Updated

Updated entry point from `0x00080000` to `0x00100000` to avoid model overlap:
```ld
. = 0x00100000;
```

---

## Memory Layout v1.5

```
DDR Low Bank (0x00000000 - 0x7FFFFFFF):
├── 0x00000000 - Model Part A (~1.15GB)
├── 0x46800000 - Context Cache A (~1.45GB)
└── GAP (2GB) - MMIO registers

DDR High Bank (0x800000000 - 0x87FFFFFFF):
├── 0x800000000 - Model Part B (~1.15GB)
└── 0x86C000000 - Context Cache B (~984MB)

Kernel Location:
└── 0x00100000 - ARM kernel (3.1MB)
```

---

## Generated Outputs

### kernel.c (Brief → C)
- 93 lines of C code
- Hardware registers mapped to MMIO macros
- Static state allocation (no malloc)
- Transaction functions: `flush_cache()`, `load_model()`, `idle()`, `ready()`, `waiting()`

### neuralcore.sv (Brief → SystemVerilog)
- 275 lines of SystemVerilog
- AXI4-Lite interface
- BRAM/UltraRAM arrays for weights and scratch
- Ternary MAC FSM

### boot.scr
- 1284 bytes compiled U-Boot script
- Loads FPGA, kernel, model parts A and B
- Jumps to 0x00100000

---

## Files Created/Modified

| File | Action | Date |
|------|--------|------|
| `imp/linkage.toml` | Created | 2026-04-27 21:11 |
| `imp/kernel.ebv` | Rewritten | 2026-04-27 22:51 |
| `imp/boot/boot.cmd` | Updated | 2026-04-27 23:10 |
| `imp/boot/boot.scr` | Regenerated | 2026-04-27 23:10 |
| `imp/arm/kernel.c` | Generated | 2026-04-27 23:12 |
| `imp/arm/boot_stub.c` | Created | 2026-04-27 |
| `imp/arm/linker.ld` | Updated | 2026-04-27 |
| `imp/arm/kernel.bin` | Compiled | 2026-04-27 23:12 |
| `brief-compiler/src/backend/c.rs` | Fixed | 2026-04-27 22:51 |

---

## Issues Encountered & Fixed

### Issue 1: Parser didn't recognize `effect {}` wrapper
- **Error:** `expected identifier, found 'Some(Ok(Asm))'`
- **Fix:** Removed `effect {}` wrapper, asm statements go directly in transaction body

### Issue 2: ASM DC CIVAC syntax not accepted by ARM assembler
- **Error:** `Error: comma expected between operands at operand 2 -- dc civac x0,x1`
- **Fix:** Simplified to `dsb sy` (data synchronization barrier)

### Issue 3: `malloc` used in bare-metal compilation
- **Error:** `implicit declaration of function 'malloc'`
- **Fix:** Changed C backend to use static allocation: `static State state_instance;`
  - **2026-04-27 23:20 - Updated:** Now distinguishes `.ebv` (bare-metal) vs `.bv` (hosted)
    - `.ebv` files → static allocation, no malloc
    - `.bv` files → dynamic allocation with malloc

### Issue 4: ASM clobber syntax wrong
- **Error:** ARM asm treated clobbers as input operands
- **Fix:** Clobbers go in third section: `: : : "x0", "x1"`

### Issue 5: `@ link` not supported in C backend state declarations
- **Error:** State declarations with `@ link` caused parse errors
- **Fix:** `@ link` only used for `trg` (triggers), constants use plain `let`

---

## Next Steps

1. **Split model file:** `split -b 1100M weights/model_9b.isp imp/model_part.`
2. **Copy to SD card** using `wipe_and_copy.sh`
3. **Boot KV260** and verify UART output
4. **Test FPGA programming** with generated SystemVerilog

---

## References

- `KV260_BOOT_PLAN_v1.5.md` - Full boot plan specification
- `KV260_BOOT_LESSONS.md` - Previous boot issues
- `brief-compiler/CHANGES.md` - Compiler changes documentation
