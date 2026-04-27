# IMP v1.4 - Implementation with Brief Link Syntax

**Date:** 2026-04-27
**Purpose:** Demonstrate how the new `@ link` syntax solves IMP's cross-target IO linkage requirements

---

## Executive Summary

The new `@ link` syntax enables IMP's `.ebv` files to share IO signals between SystemVerilog (FPGA) and Rust/C (ARM software) without hardcoding addresses. A `linkage.toml` file provides the concrete mappings for each target.

---

## The Problem IMP Solves

### Cross-Target IO Linkage

IMP has two compilation targets:
1. **SystemVerilog** → FPGA bitstream (neuralcore.sv)
2. **Rust/C** → ARM bare-metal kernel

Both targets need to communicate via hardware registers. Traditionally:

```brief
// Hardcoded in .ebv - works but:
// - Address 0x8000A040 is ARM-specific, meaningless in SV context
// - If address changes, must update .ebv AND SV/C code manually
trg cpu_write_addr: UInt @ 0x8000A044 /0..17;
```

With `@ link` syntax:

```brief
// .ebv - no concrete addresses, just logical names
trg cpu_write_addr: UInt @ link cpu_write_addr;

// linkage.toml - maps to concrete targets
[links]
cpu_write_addr = { sv = "s_axi_awaddr", rust = "0x8000A044", c = "0x8000A044" }
```

---

## IMP Project Files with Link Syntax

### 1. neuralcore.ebv (FPGA Hardware)

Current (hardcoded addresses):
```brief
// === CPU Interface (from ARM via AXI4-Lite) ===
trg cpu_control: UInt @ 0x8000a000 /0..7;
trg cpu_status: UInt @ 0x8000a004 /0..7;
trg cpu_opcode: UInt @ 0x8000a008 /0..3;
trg cpu_token_count: UInt @ 0x8000a00C /0..15;
trg cpu_write_data: Int @ 0x8000a040 / x16;
trg cpu_write_addr: UInt @ 0x8000a044 /0..17;
trg cpu_write_en: Bool @ 0x8000a048;
trg cpu_read_en: Bool @ 0x8000a04C;
```

With `@ link` syntax:
```brief
// === CPU Interface (linked to AXI signals) ===
trg cpu_control: UInt @ link cpu_control;
trg cpu_status: UInt @ link cpu_status;
trg cpu_opcode: UInt @ link cpu_opcode;
trg cpu_token_count: UInt @ link cpu_token_count;
trg cpu_write_data: Int @ link cpu_write_data;
trg cpu_write_addr: UInt @ link cpu_write_addr;
trg cpu_write_en: Bool @ link cpu_write_en;
trg cpu_read_en: Bool @ link cpu_read_en;
```

### 2. linkage.toml (Shared Configuration)

```toml
# IMP Linkage Configuration
# Maps .ebv link references to concrete SV wires and ARM addresses

[links]
# AXI4-Lite slave interface signals
cpu_control = { sv = "s_axi_awaddr[7:0]", rust = "0x8000A000", c = "0x8000A000" }
cpu_status = { sv = "s_axi_awaddr[15:8]", rust = "0x8000A004", c = "0x8000A004" }
cpu_opcode = { sv = "s_axi_awaddr[19:16]", rust = "0x8000A008", c = "0x8000A008" }
cpu_token_count = { sv = "s_axi_awaddr[31:16]", rust = "0x8000A00C", c = "0x8000A00C" }
cpu_write_data = { sv = "s_axi_wdata", rust = "0x8000A040", c = "0x8000A040" }
cpu_write_addr = { sv = "s_axi_awaddr[33:16]", rust = "0x8000A044", c = "0x8000A044" }
cpu_write_en = { sv = "s_axi_wvalid", rust = "0x8000A048", c = "0x8000A048" }
cpu_read_en = { sv = "s_axi_arvalid", rust = "0x8000A04C", c = "0x8000A04C" }

# FPGA internal BRAM (not accessible from ARM)
weight_buffer = { sv = "weight_buffer", rust = "ERROR", c = "ERROR" }
scratch = { sv = "scratch", rust = "ERROR", c = "ERROR" }
```

### 3. kernel.ebv (ARM Software Interface)

```brief
// Hardware Interface (triggers from FPGA) - linked to AXI interface
trg hw_control: UInt @ link hw_control;
trg hw_status: UInt @ link hw_status;
trg hw_opcode: UInt @ link hw_opcode;
```

```toml
[links]
# ARM to FPGA control signals (via AXI)
hw_control = { sv = "m_axi_awaddr[7:0]", rust = "0x40000000", c = "0x40000000" }
hw_status = { sv = "m_axi_awaddr[15:8]", rust = "0x40000004", c = "0x40000004" }
hw_opcode = { sv = "m_axi_awaddr[19:16]", rust = "0x40000008", c = "0x40000008" }
```

---

## How It Works

### Compilation Flow

```
neuralcore.ebv ──────────────────────────────────────┐
    │                                                  │
    ├─ verilog neuralcore.sv ◄── reads linkage.toml ────┤
    │                        (SV wire names)             │
    │                                                  │
    └─ rust/c codegen ◄──── reads linkage.toml ────────┘
         (ARM addresses)
```

### Generated Outputs

**SystemVerilog (neuralcore.sv):**
```systemverilog
module neuralcore (
    input wire s_axi_aclk,
    input wire s_axi_aresetn,
    input wire [17:0] s_axi_awaddr,
    input wire [31:0] s_axi_wdata,
    input wire s_axi_wvalid,
    // ...
);

// Internal BRAM - linked reference (no address, just wire)
// wire cpu_write_addr;  // Error: NOT accessible from ARM
trg cpu_write_addr: UInt @ link cpu_write_addr;
```

**Rust (for ARM):**
```rust
const CPU_CONTROL: *mut u32 = 0x8000A000 as *mut u32;
const CPU_STATUS: *mut u32 = 0x8000A004 as *mut u32;
// ...
```

---

## Addressing IMP Requirements

### Requirement 1: Memory Region Definitions

**Status:** Already in hardware.toml

```toml
[memory]
"0x8000A000" = { size = 1, type = "flipflop", element_bits = 8 }
"0x40A80000" = { size = 262144, type = "bram", element_bits = 16 }
```

No new syntax needed - link syntax is for **IO signals**, memory is in TOML.

### Requirement 2: Gap-Jumping Address Translation

**Status:** Already supported with ternary expressions

```brief
let phys_addr = (virtual_idx < MODEL_PART_A_SIZE)
    ? 0x0 + virtual_idx
    : 0x800000000 + (virtual_idx - MODEL_PART_A_SIZE);
```

### Requirement 3: Cache Allocation

**Status:** Already via hardware.toml + vectors

```brief
let kv_cache: Int[262144] @ 0x40B00000 / x16;
```

Compiler queries hardware.toml to find available memory.

### Requirement 4: DMA Descriptor Setup

**Status:** Already via transactions + triggers

```brief
trg dma_src: UInt @ link dma_src;
trg dma_dst: UInt @ link dma_dst;
trg dma_len: UInt @ link dma_len;

rct txn setup_dma [true] {
    &dma_src = get_weight_addr(current_idx);
    &dma_dst = FPGA_BRAM_BASE;
    &dma_len = 524288;
    term;
};
```

### Requirement 5: Multi-Bank Memory Access

**Status:** Already via transaction preconditions

```brief
rct txn read_weight_a [idx < PART_A_SIZE] {
    &phys_addr = 0x0 + idx;
    term;
};

rct txn read_weight_b [idx >= PART_A_SIZE] {
    &phys_addr = 0x800000000 + (idx - PART_A_SIZE);
    term;
};
```

### Requirement 6: Weight Streaming

**Status:** Already via transactions (implicit loops)

```brief
rct txn stream_weights [pending > 0] {
    &ddr_addr = get_weight_addr(offset);
    &bram_addr = offset;
    &pending = pending - 1;
    term;
};
```

### Requirement 7: Cache Coherency (NEW: asm syntax)

**Status:** Phase 2 feature - `asm` keyword

```brief
txn flush_cache [true] {
    asm "DC CIVAC X0, X1" { "x0", "x1" };
    asm "DSB SY" {};
    term;
};
```

### Requirement 8: Peripheral Registers

**Status:** Already via `trg @ address` - link is for cross-target linkage

```brief
// Traditional (still works)
trg fpga_reg: UInt @ 0x8000A040 /0..7;

// New: when same signal needed in both SV and Rust/C
trg fpga_reg: UInt @ link fpga_reg;
```

### Requirement 9: Interrupt Handling

**Status:** Already via triggers - backend generates ISR

```brief
trg layer_complete_irq: Bool @ link layer_complete_irq;

rct txn handle_irq [layer_complete_irq] [layer_complete_irq == false] {
    &pending_layers = pending_layers - 1;
    term;
};
```

### Requirement 10: Memory Isolation

**Status:** Via hardware.toml regions + OS

```toml
[memory.isolation]
kernel = "0x00100000..0x00400000"
model_a = "0x00000000..0x7FFFFFFF"
context = "0x800000000..0x87FFFFFFF"
```

---

## Migration Path

### Step 1: Create linkage.toml

```toml
# linkage.toml for neuralcore.ebv
[links]
cpu_control = { sv = "s_axi_awaddr[7:0]", rust = "0x8000A000", c = "0x8000A000" }
# ... rest of AXI signals
```

### Step 2: Update .ebv files

```brief
// Before:
trg cpu_control: UInt @ 0x8000a000 /0..7;

// After:
trg cpu_control: UInt @ link cpu_control;
```

### Step 3: Verify SV output

```bash
brief verilog neuralcore.ebv --hw hardware.toml
# Generated SV should have proper wire assignments
```

### Step 4: Verify Rust/C output

```bash
brief codegen neuralcore.ebv --hw hardware.toml --output rust
# Generated Rust should have 0x8000A000 constants
```

---

## Example: IMP Full Linkage

### neuralcore.ebv
```brief
// IMP Neural Core - with link syntax
trg cpu_control: UInt @ link cpu_control;
trg cpu_status: UInt @ link cpu_status;
trg cpu_opcode: UInt @ link cpu_opcode;
trg cpu_token_count: UInt @ link cpu_token_count;
trg cpu_write_data: Int @ link cpu_write_data;
trg cpu_write_addr: UInt @ link cpu_write_addr;
trg cpu_write_en: Bool @ link cpu_write_en;
trg cpu_read_en: Bool @ link cpu_read_en;

let control: UInt @ link cpu_control = 0;
let status: UInt @ link cpu_status = 0;
// ...
```

### linkage.toml
```toml
[links]
cpu_control = { sv = "s_axi_awaddr[7:0]", rust = "0x8000A000", c = "0x8000A000" }
cpu_status = { sv = "s_axi_awaddr[15:8]", rust = "0x8000A004", c = "0x8000A004" }
cpu_opcode = { sv = "s_axi_awaddr[19:16]", rust = "0x8000A008", c = "0x8000A008" }
cpu_token_count = { sv = "s_axi_awaddr[31:16]", rust = "0x8000A00C", c = "0x8000A00C" }
cpu_write_data = { sv = "s_axi_wdata", rust = "0x8000A040", c = "0x8000A040" }
cpu_write_addr = { sv = "s_axi_awaddr[33:16]", rust = "0x8000A044", c = "0x8000A044" }
cpu_write_en = { sv = "s_axi_wvalid", rust = "0x8000A048", c = "0x8000A048" }
cpu_read_en = { sv = "s_axi_arvalid", rust = "0x8000A04C", c = "0x8000A04C" }
```

### Generated SV
```systemverilog
module neuralcore (
    input s_axi_aclk,
    input s_axi_aresetn,
    input [17:0] s_axi_awaddr,
    input [31:0] s_axi_wdata,
    // ...

    // Linked signals
    logic cpu_control /* link: s_axi_awaddr[7:0] */;
    logic cpu_status /* link: s_axi_awaddr[15:8] */;
    // ...
);
```

---

## Summary

| Feature | Solution | Status |
|---------|----------|--------|
| Cross-target IO linkage | `@ link` + `linkage.toml` | ✅ Implemented |
| Memory regions | `hardware.toml` `[memory]` | ✅ Existing |
| Gap-jumping address calc | Ternary `? :` | ✅ Existing |
| DMA setup | Transactions + triggers | ✅ Existing |
| Multi-bank access | Transaction preconditions | ✅ Existing |
| Weight streaming | Transactions as loops | ✅ Existing |
| Cache coherency | `asm` keyword | 🔜 Phase 2 |
| Peripheral registers | `trg @ address` | ✅ Existing |
| Interrupt handling | Triggers + backend ISR | ✅ Existing |
| Memory isolation | `hardware.toml` + OS | ✅ Existing |

The `@ link` syntax solves the **only genuinely new requirement** from the FEATURE_REQUIREMENTS.md: cross-target IO linkage between SystemVerilog and Rust/C without hardcoding addresses.

---

*End of Plan*
