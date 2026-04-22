<!--
IMP Inference Guide - Running LLM inference on KV260
    Copyright (C) 2026 Randy Smits-Schreuder Goedheijt
-->

# Inference Guide: Running LLM Inference on KV260

This guide covers running inference on the IMP (Inference Machine Pipeline) system running on the Xilinx Kria KV260.

## Prerequisites

- KV260 board powered on and connected to network
- TCP client (netcat, curl, or custom)
- Model weights downloaded (see below)
- SD card with IMP boot image

## Quick Start

### 1. Connect to the Board

The board listens on TCP port 7777:

```bash
# Connect via netcat
nc <kv260-ip> 7777

# Or using curl (for simple requests)
curl -X POST -d "Hello, how are you?" <kv260-ip>:7777
```

### 2. Send an Inference Request

Send a text prompt and receive tokenized response:

```bash
# Interactive session
$ nc 192.168.1.100 7777
Hello, how are you?
I'm doing well, thank you for asking!
```

## Protocol

### Request Format

Send raw text (UTF-8) terminated by newline `\n`:

```
<User input text>\n
```

### Response Format

The board returns decoded text (UTF-8):

```
<Model output text>\n
```

## Memory Layout

```
DDR4 (4GB):
├── 0x1000_0000: Qwen 9B weights (~1.77GB, ternary quantized)
├── 0x7000_0000: BPE vocabulary (~100KB)
└── 0x7400_0000: Working memory

FPGA BRAM:
├── 0x4000_A000: MMIO registers (ARM <-> FPGA control)
├── 0x40A0_A000: KV cache K
├── 0x40A6_0000: KV cache V
├── 0x40A8_0000: Input embedding
├── 0x40AA_0000: Output logits
├── 0x40AC_0000: MLP gate weights
├── 0x40AE_0000: MLP up weights
├── 0x40B0_0000: MLP down weights
└── 0x40B2_0000: Attention QKV weights
```

## MMIO Control Interface

ARM writes to these registers to control FPGA:

| Register | Address | Purpose |
|----------|---------|---------|
| `control` | 0x4000_A000 | Command (20 = execute layer) |
| `status` | 0x4000_A004 | FPGA status (2 = done) |
| `opcode` | 0x4000_A008 | Layer type (1-4) |
| `token_count` | 0x4000_A00C | Number of tokens |

### Control Flow

```c
// Example: Trigger attention layer
control = 20;           // Execute command
opcode = 1;             // Layer type: 1=attention, 2=mlp_gate, etc.
status = 0;            // Clear status

// Wait for completion
while (status != 2) { }

// Read result from 0x40AA_0000
output = *(volatile uint16_t*)0x40AA_0000;
```

## Downloading Model Weights

### Option 1: Pre-loaded SD Card

Create a `weights/` directory on your SD card:

```bash
# Mount SD card
mount /dev/sdc1 /mnt

# Create weights directory
mkdir -p /mnt/weights

# Download Qwen 1.58-bit quantized weights
# Note: You'll need to find/obtain the ternary-quantized weights
# This is typically a custom format from model quantization

# Download BPE vocabulary
wget https://huggingface.co/Qwen/Qwen-9B/raw/main/tokenizer.json -O weights/vocab.json
```

### Option 2: Download at Boot (Future)

The kernel can load weights from network at boot time. This feature requires implementing TFTP client in the bare-metal kernel.

## Tokenizer

The system uses Qwen's BPE tokenizer:

- **Vocabulary size**: 151,936 tokens
- **Format**: JSON from HuggingFace
- **Loading**: At boot, vocab loaded to 0x7000_0000 in DDR4

### Token IDs

| Token | ID | Description |
|-------|-----|-------------|
| `<|endoftext|>` | 151643 | End of sequence |
| `<|im_start|>` | 151644 | Start of user message |
| `<|im_end|>` | 151645 | End of assistant message |

## Troubleshooting

### No Connection

1. Check Ethernet cable is connected
2. Verify IP address: `ip addr show eth0`
3. Ping the board: `ping <kv260-ip>`

### Connection Refused

1. Verify kernel is running (check UART debug output)
2. Ensure port 7777 is open
3. Check if kernel panicked (UART output)

### Garbage Response

1. Check weights are loaded correctly
2. Verify vocabulary is valid
3. Check for memory corruption (run diagnostics)

### Slow Inference

- 262,144 elements per layer at 100MHz = ~2.6ms per layer
- Full inference: ~10-20 layers = 26-52ms
- If slower, check FPGA clock and memory bandwidth

## Architecture Details

### ARM Kernel (kernel.rs)

1. Receives TCP request
2. Tokenizes input text → token IDs
3. Copies input tokens to FPGA BRAM via AXI
4. Triggers FPGA layer processing via MMIO
5. Reads output tokens from FPGA BRAM
6. De-tokenizes and sends response via TCP

### FPGA (neuralcore.sv)

1. Receives layer type via MMIO
2. Loads weights from on-chip BRAM
3. Performs ternary matrix multiplication:
   - `weight == 1`: `result += input`
   - `weight == -1`: `result -= input`
   - `weight == 0`: skip
4. Outputs result to output_logits buffer

### Ternary Encoding

Each byte contains 4 ternary values (2 bits each):

```
Byte: [7:6] [5:4] [3:2] [1:0]
       val3  val2  val1  val0

Encoding:
00 = 0
01 = 1
10 = -1
11 = 0 (error/reserved)
```

### Timing

| Operation | Time |
|-----------|------|
| 1 layer (262k elements) | 2.6ms |
| Attention + MLP (4 layers) | 10.4ms |
| Full token generation | ~100ms |
| Network latency | +5-20ms |
| **Total per token** | **~110ms (~9 t/s)** |

## Debugging

### UART Output

Connect to KV260 UART at 115200 baud:

```bash
# Find serial port
ls /dev/ttyUSB*

# Connect
screen /dev/ttyUSB0 115200
```

### Memory Dump

Read FPGA memory via ARM:

```c
// Dump 256 bytes of BRAM
for (int i = 0; i < 256; i += 2) {
    uint16_t val = *(volatile uint16_t*)(0x40A80000 + i);
    printf("%04x: %04x\n", 0x40A80000 + i, val);
}
```

### Status Codes

| Status | Meaning |
|--------|---------|
| 0 | Idle |
| 1 | Processing attention |
| 2 | Processing MLP gate |
| 3 | Processing MLP up |
| 4 | Processing MLP down |
| 5 | Layer complete |
| 2 (final) | Full inference complete |