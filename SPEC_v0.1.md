<!--
IMP Architecture Specification - Technical design for edge-native LLM acceleration
    Copyright (C) 2026 Randy Smits-Schreuder Goedheijt
-->

# SPEC_v0.1 - The Inference Machine Pipeline (Imp)

## 1. Overview

**IMP (Inference Machine Pipeline)** is an edge-native, hardware-accelerated LLM inference system targeting the AMD/Xilinx Kria KV260 MPSoC. The system achieves high-throughput inference by combining a ternary-quantized foundation model with speculative decoding, orchestrated by a custom bare-metal kernel written in Brief.

### 1.1 Purpose

Implement a fully functional LLM inference pipeline that:
- Runs a 9B parameter foundation model (Qwen 3.5 9B, ternary quantized to 1.77GB)
- Uses a 0.5B feeder model for speculative decoding
- Compiles to both software (ARM executable) and hardware (SystemVerilog for FPGA)

### 1.2 Target Platform

- **Board**: AMD/Xilinx Kria KV260 Vision AI Starter Kit (SK-KV260-G)
- **Processing System**: Quad-core Arm Cortex-A53 (up to 1.5 GHz)
- **Programmable Logic**: Zynq UltraScale+ (256K logic cells, 144 BRAM, 64 UltraRAM, 1.2K DSP)
- **Memory**: 4 GB DDR4 (19.2 GB/s theoretical max AXI-DMA bandwidth)
- **Power Budget**: < 15W active cooling

---

## 2. Architecture

### 2.1 System Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                     IMP System Architecture                         │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │              SOFTWARE LAYER (ARM Cortex-A53 PS)            │    │
│  │  ┌─────────────────────────────────────────────────────┐  │    │
│  │  │              Brief Kernel (kernel.ebv)              │  │    │
│  │  │  • UART/I2C Control    • Tensor Orchestration      │  │    │
│  │  │  • Model Loading       • DMA Control              │  │    │
│  │  └─────────────────────────────────────────────────────┘  │    │
│  └─────────────────────────────────────────────────────────────┘    │
│                              │                                       │
│                              ▼ AXI4-Lite                            │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │           HARDWARE LAYER (FPGA Programmable Logic)          │    │
│  │  ┌─────────────────────────────────────────────────────┐  │    │
│  │  │          Neural Core Engine (neuralcore.ebv)       │  │    │
│  │  │  • Ternary Matrix Multiplier  • KV Cache Buffer     │  │    │
│  │  │  • Speculative Decoder       • Token Embedding     │  │    │
│  │  └──────────────────��──────────────────────────────────┘  │    │
│  └─────────────────────────────────────────────────────────────┘    │
│                              │                                       │
│                              ▼ DDR4 Memory                           │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │                    DDR4 Memory (4GB)                       │    │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐     │    │
│  │  │ Kernel Image │  │  9B Weights  │  │ 0.5B Feeder │     │    │
│  │  │   (~1MB)    │  │   (~1.77GB)  │  │  (~100MB)   │     │    │
│  │  └──────────────┘  └──────────────┘  └──────────────┘     │    │
│  └─────────────────────────────────────────────────────────────┘    │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### 2.2 Memory Architecture (Critical)

**The on-chip FPGA memory (BRAM/UltraRAM) CANNOT hold the full model.**

| Storage Location | Capacity | Contents |
|------------------|----------|----------|
| DDR4 (4GB) | ~4GB | 9B weights (1.77GB) + 0.5B feeder (100MB) + KV cache (inactive layers) |
| UltraRAM | 2.25MB | One layer's KV cache (active) |
| BRAM | 518KB | Activation buffers, token embeddings, working scratch |

**Data Flow:**
```
DDR4                           FPGA (On-chip)
────────────────────           ─────────────────────
9B ternary weights  ─────────►  One layer at a time
(1.77GB)                        (streamed, ~512KB/layer)

0.5B feeder model  ──────────►  Feeder cache
(~100MB)                        (loaded on demand)

KV cache (inactive) ◄─────────  UltraRAM buffering
(~512KB/layer)                  (streamed layer-by-layer)

Token buffers     ───────────►  BRAM
(~128KB)                        (prompt/response)
```

**The kernel orchestrates**: Load layer N weights → Compute → Stream to DDR4 → Load layer N+1 → Repeat.

### 2.3 Software/Hardware Split

| Component | Layer | Description |
|-----------|-------|-------------|
| UART Control | Software | Serial console I/O for prompts/responses |
| Layer Orchestration | Software | Streams weights/KV cache from DDR4 to FPGA |
| DMA Management | Software | (Future) AXI4-Full for high-bandwidth transfers |
| Ternary Matrix Multiply | Hardware | FPGA LUTs for add/sub (no DSP needed for -1/0/1) |
| KV Cache (active) | Hardware | UltraRAM buffering for current layer |
| Activation Compute | Hardware | BRAM-based tensor operations |

---

## 3. Hardware Target

### 3.1 KV260 Specifications

#### Processing System (PS)
- Quad-core Arm Cortex-A53 (up to 1.5 GHz)
- Dual-core Arm Cortex-R5F (real-time)
- ARM TrustZone security
- Supported by: Arm Trusted Firmware (ATF), U-Boot

#### Programmable Logic (PL)
- 256K system logic cells (LUT + flip-flop)
- 144 Block RAM (BRAM) blocks (36Kb each = 518KB total)
- 64 UltraRAM blocks (288Kb each = 2.25MB total)
- 1.2K DSP slices
- 120+ IO pins

### 3.2 Memory Map

| Address | Region | Size | Type | Purpose |
|---------|--------|------|------|---------|
| 0x0000_0000 | DDR4 Base | 256MB | DDR4 | Kernel + Runtime |
| 0x1000_0000 | Model Weights | 1.88GB | DDR4 | 9B + 0.5B quantized weights |
| 0x4000_0000 | Control Regs | 16KB | Flip-Flop | CPU-to-FPGA registers |
| 0x4000_4000 | PL BRAM | 2.25MB | UltraRAM | KV cache buffers |
| 0x4008_0000 | Input Tensors | 256KB | BRAM | Input embeddings |
| 0x4008_4000 | Output Tensors | 256KB | BRAM | Output logits |
| 0xFFFC_0000 | Boot ROM | 256KB | ROM | First stage bootloader |

### 3.3 AXI4-Lite Interface

The software kernel communicates with the hardware engine via AXI4-Lite:

| Register | Address | Bits | Description |
|----------|---------|------|-------------|
| control | 0x4000_0000 | 8 | 0=Idle, 1=Load Input, 2=Execute, 3=Read Output |
| status | 0x4000_0004 | 8 | 0=Idle, 1=Busy, 2=Done, 3=Error |
| opcode | 0x4000_0008 | 4 | 0=Forward, 1=Attention, 2=FeedForward |
| token_count | 0x4000_000C | 16 | Number of tokens to process |
| input_ptr | 0x4000_0010 | 32 | DDR4 pointer to input tensor |
| output_ptr | 0x4000_0014 | 32 | DDR4 pointer to output tensor |

---

## 4. Software Kernel (kernel.ebv)

The bare-metal kernel runs on the ARM Cortex-A53, handling system orchestration.

### 4.1 State Definitions

```brief
// === UART Control ===
let uart_rx_data: UInt @ 0x4000_1000 /0..7 = 0;
let uart_tx_data: UInt @ 0x4000_1004 /0..7 = 0;
let uart_status: UInt @ 0x4000_1008 /0..3 = 0;  // RX_ready, TX_busy, etc.
let uart_control: UInt @ 0x4000_100C /0..3 = 0;

// === Hardware Interface (AXI4-Lite) ===
let hw_control: UInt @ 0x4000_0000 /0..7 = 0;
let hw_status: UInt @ 0x4000_0004 /0..7 = 0;
let hw_opcode: UInt @ 0x4000_0008 /0..3 = 0;
let hw_token_count: UInt @ 0x4000_000C /0..15 = 0;
let hw_input_ptr: UInt @ 0x4000_0010 /0..31 = 0;
let hw_output_ptr: UInt @ 0x4000_0014 /0..31 = 0;

// === Model State ===
let prompt_buffer: Int[512] @ 0x4000_2000 / x16;
let response_buffer: Int[512] @ 0x4000_2100 / x16;
let token_count: UInt = 0;
let modelLoaded: Bool = false;

// === Ring Buffer for UART ===
let rx_head: UInt = 0;
let rx_tail: UInt = 0;
let rx_buffer: UInt[256] @ 0x4000_3000 / x8;
```

### 4.2 Transactions

```brief
// === UART Transactions ===
rct txn uart_read [uart_status.bit(0) == 1][uart_status.bit(0) == 0] {
    &prompt_buffer[token_count] = uart_rx_data.sign_extend();
    &token_count = token_count + 1;
    &uart_status = uart_status.bit(0) = 0;
    term;
};

rct txn uart_write [uart_status.bit(1) == 0][true] {
    &uart_tx_data = response_buffer[0];
    &uart_status.bit(1) = 1;
    term;
};

// === Hardware Control ===
rct txn load_input [hw_control == 1][hw_control == 1] {
    &hw_input_ptr = prompt_buffer.address;
    &hw_token_count = token_count;
    term;
};

rct txn execute_inference [hw_control == 2][hw_status == 2] {
    &hw_control = 2;
    term;
};

rct txn read_output [hw_control == 3][hw_status.bit(1) == 1] {
    &response_buffer = hw_output_ptr.deref();
    term;
};

// === Model Loading ===
rct txn init_model [!modelLoaded][modelLoaded == true] {
    // Initialize model weights from pre-loaded DDR4 region
    &modelLoaded = true;
    term;
};

// === Main Inference Cycle ===
rct txn run_inference [modelLoaded && token_count > 0][response_buffer.len() > 0] {
    // Full pipeline: UART -> Hardware -> UART
    &hw_control = 1;  // Load input
    wait hw_status == 1;
    &hw_control = 2;  // Execute
    wait hw_status == 2;
    &hw_control = 3;  // Read output
    term;
};
```

### 4.3 Contracts

| Transaction | Precondition | Postcondition |
|------------|-------------|-------------|
| uart_read | UART RX ready | Data in buffer |
| uart_write | UART TX idle | Data transmitted |
| load_input | Hardware idle | Input pointer set |
| execute_inference | Input loaded | Execution complete |
| read_output | Execution done | Output in buffer |
| init_model | Model not loaded | Model state ready |

---

## 5. Hardware Engine (neuralcore.ebv)

The FPGA fabric handles computationally intensive tensor operations.

### 5.1 State Definitions

```brief
// === CPU Interface (from ARM) ===
trg cpu_control: UInt @ 0x40000000 /0..7;
trg cpu_status: UInt @ 0x40000004 /0..7;
trg cpu_opcode: UInt @ 0x40000008 /0..3;
trg cpu_token_count: UInt @ 0x4000000C /0..15;
trg cpu_input_ptr: UInt @ 0x40000010 /0..31;
trg cpu_output_ptr: UInt @ 0x40000014 /0..31;

// === Internal Control ===
let control: UInt @ 0x40000000 /0..7 = 0;
let status: UInt @ 0x40000004 /0..7 = 0;
let opcode: UInt @ 0x40000008 /0..3 = 0;

// === Tensor Buffers (BRAM) ===
// Input: 256 tokens x 4096 embedding = 1M elements = 2MB
let input_embedding: Int[256*4096] @ 0x40084000 / x16;

// Output: 256 tokens x 4096 logits = 1M elements = 2MB
let output_logits: Int[256*4096] @ 0x400A4000 / x16;

// KV Cache (UltraRAM): 32 layers x 2 heads x 4096 context x 128kv = 256K elements
let kv_cache_k: Int[32*2*4096*128] @ 0x40040000 / x16;
let kv_cache_v: Int[32*2*4096*128] @ 0x40060000 / x16;

// === Ternary Weights Cache ===
let mlp_gate: Int[4096*11008] @ 0x40080000 / x2;  // Ternary: -1, 0, 1
let mlp_up: Int[4096*11008] @ 0x400A0000 / x2;
let mlp_down: Int[11008*4096] @ 0x400C0000 / x2;
```

### 5.2 Ternary Matrix Operations

```brief
// === Ternary Matrix Multiply ===
// For weights in {-1, 0, 1}, operation becomes:
//   result += input  (weight == 1)
//   result -= input (weight == -1)
//   result unchanged (weight == 0)
defn ternary_matmul(input: Int[N], weights: Int[M], bias: Int) -> Int [true][true] {
    let result: Int = 0;
    for i in 0..N {
        [weights[i] == 1] result = result + input[i];
        [weights[i] == -1] result = result - input[i];
        [weights[i] == 0] result = result + 0;
    };
    term result + bias;
};

// === Attention with KV Cache ===
defn attention(q: Int, k_cache: Int, v_cache: Int) -> Int [true][true] {
    // Simplified attention: Q * K^T * V for ternary weights
    let scores: Int = 0;
    let result: Int = 0;
    for pos in 0..4096 {
        scores = scores + q * k_cache[pos];
    };
    for head in 0..128 {
        result = result + scores * v_cache[head];
    };
    term result;
};

// === MLP Layer with Ternary Weights ===
defn mlp_layer(x: Int) -> Int [true][true] {
    let gate = ternary_matmul(x, mlp_gate, 0);
    let up = ternary_matmul(x, mlp_up, 0);
    let down = ternary_matmul(gate * up, mlp_down, 0);
    term down;
};
```

### 5.3 Control Transactions

```brief
// === CPU Interface ===
rct txn update_control [cpu_control != control] [control == cpu_control] {
    &control = cpu_control;
    &opcode = cpu_opcode;
    term;
};

rct txn load_input_tensor [cpu_control == 1 && control == 1][input_embedding.valid] {
    // Read input tensor from DDR4 via AXI
    term;
};

rct txn execute_forward [cpu_control == 2 && control == 2][status == 2] {
    // Execute full transformer forward pass
    &input_embedding = attention(input_embedding);  // Simplified
    &output_logits = mlp_layer(input_embedding);
    &status = 2;
    term;
};

rct txn read_output_tensor [cpu_control == 3 && control == 3][output_logits.valid] {
    // Write output tensor to DDR4 via AXI
    term;
};
```

---

## 6. Memory Allocation

### 6.1 DDR4 Layout

```
Offset (0x1000_0000)
+0x0000_0000: 9B Model Weights (1,771,200,000 bytes / ~1.77GB)
    - Qwen 3.5 9B (ternary quantized)
    - Header: layer count, embedding size, attention heads
+0x7000_0000: 0.5B Feeder Weights (104,857,600 bytes / ~100MB)
    - Qwen 2.5 Coder 0.5B (ternary quantized)
+0x7400_0000: Working Memory (50MB)
    - Token buffers
    - Temporary activations
+0x7500_0000: (Reserved for future SD card loading)
```

### 6.2 BRAM/UltraRAM Allocation

```
0x4000_0000: Control Registers (Flip-Flop)
0x4004_0000: KV Cache K (2.25MB UltraRAM)
0x4006_0000: KV Cache V (2.25MB UltraRAM)
0x4008_0000: Input Embeddings (1MB BRAM)
0x400A_0000: Output Logits (1MB BRAM)
0x400C_0000: MLP Weights Cache (512KB BRAM)
0x400E_0000: Embedding Table (512KB BRAM)
```

---

## 7. Boot Sequence

### 7.1 Zynq UltraScale+ Boot Flow

```
┌─────────────────────────────────────────────────────────────────────────┐
│               Boot Sequence                                    │
├─────────────────────────────────────────────────────────────────────────┤
│  1. ROM (Read-Only Memory)                              │
│     - Initial boot from SD/Flash                          │
│     - Loads First Stage Bootloader (FSBL)               │
│                                                          │
│  2. FSBL (First Stage Bootloader)                        │
│     - Initializes DDR4 controllers                      │
│     - Loads Arm Trusted Firmware (ATF)                  │
│                                                          │
│  3. ATF (Arm Trusted Firmware)                         │
│     - Secure monitor functionality                       │
│     - Loads U-Boot                                       │
│                                                          │
│  4. U-Boot                                             │
│     - Reads boot.scr from SD card                      │
│     - Loads Brief kernel.elf to 0x0000_0000           │
│     - Jumps to kernel entry point                       │
│                                                          │
│  5. Brief Kernel (kernel.ebv)                      │
│     - Initializes UART/DMA                               │
│     - Validates model weights in DDR4                     │
│     - Ready for inference requests                    │
└─────────────────────────────────────────────────────────────────────────┘
```

### 7.2 Boot Artifacts

| Artifact | Source | Description |
|----------|--------|-------------|
| BOOT.BIN | bootgen | FSBL + ATF + U-Boot + FPGA bitstream |
| boot.scr | mkimage | U-Boot script |
| system.dtb | dtc | Device tree blob |
| kernel.elf | Brief compiler | Compiled kernel (ARM) |
| neuralcore.bit | Brief compiler | Compiled hardware (FPGA) |

---

## 8. Phase 1 Deliverables (v0.1)

### 8.1 File Structure

```
imp/
├── SPEC_v0.1.md           # This specification
├── kernel.ebv             # Bare-metal kernel (software layer)
├── neuralcore.ebv          # Hardware engine (FPGA layer)
├── hardware.toml          # Complete KV260 target config
└── README.md            # Build and deployment instructions
```

### 8.2 Build Commands

```bash
# Build software kernel (ARM executable)
cargo build --release
./target/release/brief-compiler verilog kernel.ebv --hw hardware.toml --out out/

# Build hardware engine (SystemVerilog)
./target/release/brief-compiler verilog neuralcore.ebv --hw hardware.toml --out out/
```

### 8.3 Success Criteria

- [ ] kernel.ebv compiles without errors
- [ ] neuralcore.ebv compiles without errors
- [ ] hardware.toml validates against KV260 constraints
- [ ] UART interface defined
- [ ] AXI4-Lite control interface defined
- [ ] Memory map respects 4GB DDR4 limit

---

## 9. Future Considerations

### 9.1 Model Loading from SD Card

*Not implemented in v0.1 - noted for future development*

- Load quantized weights from microSD card on boot
- Support for model switching (different base models)
- Enable updating weights without reflashing

### 9.2 Expanded Features

| Feature | Description | Priority |
|---------|-------------|----------|
| SD Loading | Load weights from SD card | Future |
| Multi-model | Support different model sizes | Future |
| Ethernet | Network input/output | Future |
| Flash | eMMC boot storage | Future |

### 9.3 Performance Targets

| Metric | Target | Notes |
|--------|--------|-------|
| Tokens/second | 25-30 t/s | With 60-70% acceptance rate |
| Memory bandwidth | 19.2 GB/s | AXI-DMA theoretical max |
| Power | < 15W | Active cooling |

---

## 10. Compiler Implementation Notes

### 10.1 SystemVerilog Generation Strategy

The Brief compiler generates SystemVerilog based on memory type from `hardware.toml`:

| Memory Type | Generation Style | Result |
|-------------|------------------|--------|
| `bram` | Single `always_ff` with address mux | RAM inference |
| `ultraram` | Single `always_ff` with address mux | UltraRAM inference |
| `flipflop` | `generate for` loop | Individual registers |

**Is this overtuned?** 

No. The approach is **universal but target-aware**:

1. The compiler reads `hardware.toml` to understand memory types
2. It uses existing memory type info (`bram` vs `flipflop`) to choose generation strategy
3. Same universal backend handles all targets - just different `.toml` configs
4. New targets (like different FPGAs) just need new `.toml` files, not compiler changes

The fix was adding one conditional: "if memory type is bram/ultraram, use RAM template; otherwise use generate for".

### 10.2 Configuration Negotiation

User-facing knobs in `hardware.toml`:
- `address_width` - bits to address buffer (e.g., 18 for 262K elements)
- Memory `type` - bram/ultraram/flipflop
- Target constraints from `hardware_lib/targets/`

This keeps the compiler universal while allowing users to configure for their specific FPGA.

---

## 11. References

- Xilinx Kria KV260 Documentation
- Qwen 3.5 9B Model (HuggingFace)
- Qwen 2.5 Coder 0.5B (Ollama)
- Speculative Decoding (Leviathan et al., 2023)
- Zynq UltraScale+ Technical Reference Manual
- Brief Language Specification (brief-compiler)

---

*Document version: 0.1*
*Last updated: April 2026*
*Based on: INITIAL_RESEARCH.md*