<!--
IMP Research Notes - Technical analysis and architecture decisions
    Copyright (C) 2026 Randy Smits-Schreuder Goedheijt
-->

# The Inference Machine Pipeline (Imp): Technical Specifications for Edge-Native LLM Acceleration

*Please note: The engineering and architectural guidance provided in this document is for informational purposes only and does not constitute professional or safety-critical engineering advice. Hardware deployment carries inherent operational risks.*

*   **The Hardware Reality:** The Xilinx Kria KV260 is a highly capable platform for edge AI, featuring 4GB of DDR4 memory, an integrated quad-core Arm Cortex-A53 CPU, and a Field Programmable Gate Array (FPGA) fabric with 256K logic cells.
*   **The Bottleneck Math:** The physical limit of direct memory access (DMA) bandwidth is roughly 19.2 GB/s. Reading a 1.58-bit quantized 9-billion-parameter model (~1.77 GB) for every single token caps throughput at roughly 10 tokens per second (t/s). The feeder model architecture circumvents this bottleneck.
*   **The Neural Synergy:** Qwen 3.5 9B utilizes Gated Delta Network (GDN) architecture that maintains a nearly fixed-size memory state, preventing context cache from overflowing the 4GB RAM limit.
*   **The Bootloader Context:** Arm Trusted Firmware and U-Boot dictate that the custom kernel, written in Brief, must function as a compliant payload within the Zynq UltraScale+ boot sequence.

The Inference Machine Pipeline (Imp) addresses one of the most pressing challenges in artificial intelligence: executing massive transformer models on low-power, edge-native hardware. By combining extreme ternary quantization (1.58-bit weights) with a hardware-level SystemVerilog implementation and speculative decoding via a 0.5B "feeder" model, the system constructs an Application-Specific Integrated Circuit (ASIC) experience on a consumer-priced FPGA. This document serves as the comprehensive architectural blueprint.

## Executive Summary

1. **The KV260 Board Capabilities:** The AMD/Xilinx Kria KV260 is an excellent fit for custom silicon logic, boasting a Zynq UltraScale+ architecture that pairs a multi-core ARM processor with an expansive FPGA fabric. The 4GB memory constraint is the primary bottleneck. A custom bare-metal kernel entirely bypasses Linux overhead, allowing maximum hardware utilization.
2. **The Viability of the Imp Architecture:** The Imp is mathematically rigorous. By integrating 1.58-bit ternary quantization with Qwen 3.5 9B's memory-efficient Gated Delta Network, a massive foundation model fits entirely in the KV260's DDR4 RAM. Speculative decoding via an auxiliary 0.5B feeder model mitigates the board's ~19.2 GB/s memory bandwidth cap, theoretically tripling text generation speed.
3. **Licensing:** Apache 2.0 licensing protects the work while enabling broad adoption.

## 1. Hardware Foundation: The Xilinx Kria KV260 Vision AI Starter Kit

The AMD/Xilinx Kria KV260 (part number SK-KV260-G) is a Multi-Processor System-on-Chip (MPSoC). This combines a traditional central processing unit (CPU) with a programmable hardware fabric (the FPGA) on a single die, allowing software and custom hardware circuits to interact with minimal latency.

### 1.1 The Processing System (PS) and Programmable Logic (PL)

The board divides into two main domains: the Processing System (PS) and the Programmable Logic (PL).

*   **The Processing System (PS):** Features a quad-core Arm Cortex-A53 processor complex running at up to 1.5 GHz, alongside a dual-core Arm Cortex-R5F real-time processing unit. The Brief-compiled software kernel resides here.
*   **The Programmable Logic (PL):** The blank canvas of the FPGA. The KV260 features 256K system logic cells, 144 Block RAM (BRAM) units, 64 UltraRAM blocks, and 1.2K Digital Signal Processing (DSP) slices. The Brief-to-SystemVerilog transpiled transformer architecture instantiates here.

### 1.2 Anti-Use Cases

The KV260 excels when AI mathematical operations are quantized to integer or logic-gate levels. It is not suitable for:
- Training large models from scratch
- Running unquantized multi-billion parameter dense transformers
- High-fidelity 3D graphics rendering
- Massive parallel floating-point operations (FP32 or FP16)

Traditional GPUs drastically outperform the KV260 in floating-point throughput.

### 1.3 Memory Constraints and Bandwidth Limits

The KV260 is equipped with 4 GB of non-ECC DDR4 memory. The most formidable opponent in LLM inference is memory bandwidth, not computational power.

To move data between the 4GB DDR4 and the custom hardware in the PL, the board utilizes AXI-DMA. The highest throughput data-transfer mechanism between the processing unit and programmable logic caps at roughly 19.2 GB/s.

Autoregressive text generation requires loading the entire model's weights from RAM into the processing unit for every single token generated. A quantized 9B model requiring ~1.8 GB of memory yields a maximum theoretical rate of slightly over 10 tokens per second.

### 1.4 The Boot Sequence: U-Boot and Arm Trusted Firmware

The Zynq UltraScale+ architecture utilizes a multi-stage boot process. First, a ROM executes, loading a First Stage Bootloader (FSBL). This hands off to Arm Trusted Firmware (ATF)—which provides secure monitor functionality—and then to U-Boot, an open-source bootloader. U-Boot initializes the DDR4 memory controllers and loads an operating system payload.

The custom Brief language kernel must compile into a standard executable format (ELF or raw binary with U-Boot header) that U-Boot recognizes and can boot into memory. This constitutes a "bare-metal" application replacing the standard Ubuntu Linux environment.

#### 1.4.1 Procedural Implementation: Prepping the Bare-Metal Payload

To ensure U-Boot successfully targets and launches the Brief-compiled kernel directly from an SD card:

1.  **Generate the Device Tree:** Create a modified Device Tree Blob (`system.dtb`) ensuring standard OS drivers are suppressed and full access to memory and PL peripherals is yielded to the payload.
2.  **Write the Boot Command Script:** Create `boot.cmd` with sequential memory load instructions. For example: `fatload mmc 0:1 ${fdt_addr} system.dtb` and `fatload mmc 0:1 ${kernel_addr} kernel.elf`. Conclude with `booti ${kernel_addr} - ${fdt_addr}`.
3.  **Compile the U-Boot Script:** Run `mkimage -A arm -T script -C none -n "Brief Kernel Boot Script" -d boot.cmd boot.scr`.
4.  **Assemble the Artifacts:** Using Xilinx `bootgen` utility and a BIF file, compile FSBL, Arm Trusted Firmware, U-Boot, and the FPGA bitstream into `BOOT.BIN`.
5.  **SD Card Structure:** Place `BOOT.BIN`, `boot.scr`, `system.dtb`, and `kernel.elf` into the FAT32 boot partition.

## 2. Neural Architecture

### 2.1 The Gated DeltaNet Advantage

Standard transformer models suffer from expanding Key-Value (KV) caches. As a conversation grows, memory required to store context grows linearly, quickly causing out-of-memory errors on a 4GB board.

Qwen 3.5 9B utilizes Gated Delta Networks (GDN). Instead of expanding memory indefinitely, GDN architectures maintain a mostly fixed memory state, absorbing prior context into a compressed mathematical representation. This allows the model to support up to 262,144 tokens of native context without exponentially eating into the 4GB VRAM limit. This architectural shift, combined with sparse Mixture-of-Experts, makes running a 9B model on the KV260 viable.

### 2.2 Ternary Quantization (1.58-bit) Physics

To fit 9 billion parameters into 4GB of RAM, extreme quantization is required. Traditional models use 16-bit floating-point numbers (FP16). By converting to ternary weights (1.58 bits), every parameter rounds to one of three values: -1, 0, or 1.

A 9B parameter model at 1.58 bits occupies only about 1.77 GB of memory. Multiplying any number by -1, 0, or 1 does not require actual multiplication—it only requires addition, subtraction, or skipping the operation entirely.

The KV260 possesses only 1.2K DSP slices, the hardware blocks responsible for complex multiplication. By using ternary weights, the DSP bottleneck is completely bypassed. The transpiled SystemVerilog uses the 256K logic cells to construct thousands of simple adders and subtractors, turning the FPGA fabric into a highly specialized, parallelized ternary matrix multiplication engine.

## 3. Speculative Decoding

A 10 t/s limit exists. The solution bypasses this using a small feeder model—a technique formally known as speculative decoding or speculative drafting.

### 3.1 The Feeder Model: Qwen 2.5 Coder 0.5B

A 0.5B parameter "feeder" model is recommended. The Qwen 2.5 architecture has improved knowledge coverage, structured JSON outputs, and code-generation capabilities. A 0.5B model (ternary quantized) occupies slightly under 100 MB of RAM. It possesses enough syntactical logic to accurately guess the next string of tokens without consuming excessive memory bandwidth, acting as an efficient drafter for the 9B target model.

### 3.2 The Mechanics of Speculative Decoding

In standard autoregressive generation, generating 5 tokens requires passing the entire 1.8 GB model through memory 5 separate times. Memory bandwidth is fixed at 19.2 GB/s, making this take nearly half a second.

The Imp architecture utilizes a dual-model approach:
1.  **The Draft Phase:** The small 0.5B parameter drafter model rapidly generates a speculative sequence of 4-5 tokens. Because it is so small, loading it takes only a fraction of memory bandwidth.
2.  **The Verification Phase:** The large 9B target model takes these drafted tokens and evaluates them in parallel. Verifying 5 tokens requires exactly the same single forward pass and memory load of the 9B model as generating 1 token.

### 3.3 The Acceptance Rate Multiplier

The core metric determining architecture success is the "token acceptance rate." This rate dictates the probability of the large target model accepting a token proposed by the draft model, conditioned on the acceptance of all prior drafted tokens.

If the 9B model agrees with the 0.5B model's sequence, 5 tokens generate in the time it usually takes to generate 1. Standard acceptance rates averaging between 60% and 70% for well-aligned draft models effectively transform sequential generation into highly parallel compute-bound verification, boosting throughput from 10 t/s to roughly 25-30 tokens per second.

## 4. Software-to-Hardware Transpilation: The Brief Language Ecosystem

The core innovation of The Imp is the tooling. Brief compiles both the software OS and transpiles directly to SystemVerilog for hardware. This practice—translating high-level programming constructs into HDL—is known as High-Level Synthesis (HLS).

### 4.1 SystemVerilog Transpilation Strategy

Transpiling Brief into SystemVerilog for the KV260 requires mapping high-level concepts to Xilinx-specific FPGA primitives.

*   **Memory Controllers:** SystemVerilog must instantiate AXI4 master interfaces to read ternary weights from DDR4 memory.
*   **On-Chip Buffering:** The KV260 has 144 BRAM and 64 UltraRAM blocks. Transpiled code must intelligently cache KV state entirely within these ultra-fast on-chip memory blocks, avoiding round-trips to DDR4 RAM for context lookups.

**Illustrative Example:**
Consider a standard matrix multiplication instruction written in Brief: `Matrix_C = Matrix_A * Matrix_B`. In a traditional compiler targeting GPU or CPU, this triggers heavy usage of floating-point units.

However, because weights are constrained to ternary values (-1, 0, 1), the Brief-to-SystemVerilog transpiler overrides traditional mathematical synthesis. Instead of routing this operation to the KV260's limited DSP slices, the compiler generates combinational logic:
- Multiplication by `-1` transpiles directly to a "two's complement" negation circuit
- Multiplication by `0` synthesizes into a multiplexer that completely disables the data path
- Multiplication by `1` synthesizes as a simple wire pass-through

The transpiler collapses complex DSP matrix math into a massively parallel array of simple addition and subtraction gates spread across the board's 256K Programmable Logic cells.

### 4.2 The Custom Kernel Setup

Instead of running an OS which introduces unpredictable latency, Brief compiles a Real-Time Operating System (RTOS) bare-metal loop.

The kernel loads by U-Boot. Its primary interface for receiving user prompts is the board's UART or Ethernet connection. Its responsibilities include managing the UART stream, initializing AXI DMA engines, tokenizing text, triggering the FPGA PL fabric for speculative decoding, and returning the de-tokenized output. By stripping out Linux, maximum DDR4 allocation is secured purely for the neural network architecture.

***

# Technical Specification: The Inference Machine Pipeline (Imp)

## 1. System Overview

The Imp is an edge-native, hardware-accelerated LLM pipeline targeting the AMD/Xilinx Kria KV260 MPSoC. It achieves high-throughput inference by coupling a ternary-quantized foundation model with a smaller speculative decoding model, orchestrated entirely by a custom bare-metal kernel and hardware logic generated via the Brief programming language.

## 2. Hardware Target

*   **Platform:** Xilinx Kria KV260 Vision AI Starter Kit (SK-KV260-G)
*   **Processing System (PS):** Quad-core Arm Cortex-A53
*   **Programmable Logic (PL):** Zynq UltraScale+ (256K Logic Cells, 144 BRAM, 64 UltraRAM, 1.2K DSP)
*   **Memory:** 4 GB DDR4 (19.2 GB/s theoretical max bandwidth via AXI-DMA)
*   **Power Budget:** < 15W active cooling

## 3. Neural Architecture

*   **Primary Foundation Model:** Qwen 3.5 9B
    *   **Architecture:** Gated Delta Network (GDN) & sparse Mixture-of-Experts
    *   **Advantage:** Fixed-state memory profiling prevents KV cache from overflowing the 4 GB limit
    *   **Quantization:** 1.58-bit (Ternary: -1, 0, 1). Memory footprint: ~1.77 GB
*   **Feeder Model (Drafting):** Qwen 2.5 Coder 0.5B
    *   **Quantization:** 1.58-bit. Memory footprint: ~100 MB
    *   **Function:** Generates 4-5 speculative tokens per cycle
*   **Decoding Strategy:** Speculative Decoding. The 0.5B model drafts tokens rapidly, mitigating memory bandwidth bottleneck, while the 9B model verifies all drafted tokens in a single parallel memory pass. Targeting 60-70% acceptance rate to achieve 25+ t/s effective throughput.

## 4. Software Stack & Boot Flow

1.  **Bootloader Sequence:** Zynq ROM -> FSBL -> Arm Trusted Firmware -> U-Boot (reading compiled `boot.scr`)
2.  **Kernel:** An ELF bare-metal operating environment written entirely in Brief-lang. Bypasses standard Linux overhead to reserve maximum DDR4 memory for model weights.
3.  **Transpilation:** Brief-lang transpiles inference logic directly to SystemVerilog
4.  **Hardware Execution:** SystemVerilog utilizes PL logic cells for ternary addition (bypassing limited DSP slices), with KV caches buffered in zero-latency BRAM/UltraRAM blocks.

## 5. IP & Licensing

*   **License:** Apache 2.0

***

## Conclusion

The convergence of ternary quantization, Gated Delta Networks, and speculative decoding on a low-cost $250 hardware platform represents a paradigm shift in local AI deployment. By writing the entire ecosystem from kernel to silicon in Brief, dependency on bloated corporate middleware is drastically reduced. Focus immediate efforts on integrating the Brief kernel as a valid U-Boot ELF payload via `mkimage` scripting, verifying AXI-DMA memory read speeds, and simulating the ternary math within the SystemVerilog PL fabric.

## Sources

1. [suse.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQH_16SMLc_cy4OdkeGLYXwOYStDfStGoWvTy3c7OnFwCwlylQBoVQUk21-z_OAEBgRUbmwBd-LrNEXkBd79vz7U-Yt1mj5lfXNIxVrRHHymAJHIDiRPxxDLXrtrYHix5Ms4NhyeTm3Vlpov3k8gJP18cQSzvY2FPGboLA==)
2. [reddit.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQF3ozfRSJN_5gY4LbbnVx-cxd_1MLQS2noF-aiDsBCv-LOufcCYiNGTw5Axt48RlP3F74rZKfbrXp2xP7ffPVJ_BY7R0b2ZYfkywQoglLz2ZKCs5-75MdqGSnc16Jq5BLLiHm-605B3-b8Y_kx0mamk94D7v5Vo2AlZmOSW)
3. [github.io](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQEpZUnboznt7c1P_irqAwqOnTDqxpD_3OMXP984Y1u1NcDtMqrovH2lvViGMCC1JfAB_ynXY5zBFr2bVcMWpjB55qrfZLEr6sloH16T_jrth5BQzYVnyzjbaTfqOxB3UXppGkaAgWkyPWGvG1W1vLfbM0oN_OBjr_tq_8NzJXWl93xNgWXVTNr7aeivpQUB8zRpYsc1NZL11y7TKeeV8ULr_HH8CP_PQDVPy2qPzy9U_8ng6u9rX1sj22DnZ_Yn)
4. [u-boot.org](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQEICt4_s3CtNgs5hRU-PX4e3dsuhwL2mms8GSsflIExZM9fE867M3Kf-MP0Xu2jfGQMl95PDfTbJUr1ncjyDIzLVMgs-5Q30ooxrQEe-e5fCavZetY3dXPDqIwhvXE2ge-genREIYe_mzCVLw==)
5. [yairgadelov.me](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQG9VXWlsIz7MrHDBwwH8-BaLFCcx--y3PdQtSNBwUUk3Gwb7Pc-sLIX5WYHEvge7IRhb0pc8zVjxlQeDYI140gbevPvMJ1Qqlkd-s_3dGUMitgnqIk9j0MzrtJuJh9oV7F_AMWIxl97w8Cr5nhwNGyyOFYmWLE=)
6. [huggingface.co](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQEwjf6z0XnqI7MuGudMPQt5a5mqlkqhnmtDz2TgVnZ7NzaaVwlsuvTzliBUIBmTkcnFvF2LPVR4O7dZ8Ii5iTMm05CZcGgq9iYci4YrwYPhTJ3WVIB_x0bm1rhfzQ==)
7. [lmstudio.ai](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQFoS4kp--iQRRmMzijMSX8XpllzqLsvbhlZfqAJfweus_Xg5tW7A0NroVXuf_BJmGuT6Kfc56eDJPPA2vfBLVaEh3kVvwDR0GpxGX-yQQD-jvsIjNG2yV2ffI9bEG6aCrA=)
8. [artificialanalysis.ai](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQGXzFnfZhxupEvUikTCCqkR4_u8tG7OFmdrEYP9mBCPAK8hImdGgby6q6lulVyyNKbtbRFM9QVuXbL54fdeY_i9P9TzD-BNiUq4-HHC_z1LrywJVkzqU9mNnXoB6bH12rfGif4H-AAoQ7HRy7AiC22KNA==)
9. [xda-developers.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQEMpRV0AOcFK_shsdki4p6472I4RVclL_zG67M27UbqzfNqR6bxT-XN8wzzEwDZIzdbH7ROgwefamNbFzRoEZMNVxhFpVsP5LraQFb3mZHRgsS6rGQ4exBiPgiTlFqk0Xi23KuZECS0T7MI0CbcbYboLuBv0wYgG5gswSNlwOcxY6o0gihWdvI=)
10. [openrouter.ai](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQHxIJoiDAzWa-vO624qEJIxfmO4dc7s_hTFWSgu0Zh_gv_dGm_6pcUVfLdEn_fJNXaWSshLoVosauOasBeyIOdZTYaP6Kw4SURSAY4_Q7qeZArTbl1rkAMrlwi7)
11. [arxiv.org](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQHfhHkJDNjBg5_d6JeK9kM741fN-ITzlQsRsVLgfqRaYXrCNOUNK5lp0rrynv2X8dxR1xU9TdfdKMDCGo3jadiz1hOKf1-ydLmQ9RBXEfaWr--5vf86GkDWzw==)
12. [arxiv.org](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQHClwHX29Dk_ShQ9n962H6pe1Z9VGkDCJMdiitzSGJX9PV0bjAX3lC7VbxtBv9rjsX-4Q3h5Dv8g3ieMILxP0S2vcomOsNzCjOOIaOvTXWQ1Ekzi4dsW4Udtw==)
13. [philkrav.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQHm8XamVX3R0Ub861CpRVru0PsEVRHN-MEvaodQDIH6V0GklBuKp4s_SjQ9LIqaern2o46c3sCY8WHgMMvtJoeIDX-0EiDKfsFrS4OwIeMsG8ByzCCOyP25NGu-WjY=)
14. [ollama.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQG5UXrDEWhZZGuupdBPgaK1PSEvCqJRtx6RHzLddVN_c2jUhcjWPDc8GKFkXK-eHDx85bOKZwMFe714bj8mmozz7ReY8QZZ6wQ3NSMSUu9tkItE9TnSALUjrBPicJny)
15. [huggingface.co](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQGz9GzViMDl8xDLseNp3YoeFS6michOgQLFt-R7fOKjC2RniH-8SfEVemTFwlfvxMBfV1kBgNSO1g1lgL3nvFoPYsvFgsOyAgoN3ipLUXrVV5wjwbJreA-3jPIWJss9mh4Ejfw5j5xZNg==)
16. [github.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQE1QIwfJ4pbK0BRCpMSu63lH89Fdw_PeS3s5lMj0Da7q4BaUeiAznjoZmI_d0KGVsjYIK-WoCX6oRzVntzAOZpm0SwQR3dhAtk8av-pr7JGCO7P9XlalNyKwlrFMx6S1UNQBka_)
17. [openreview.net](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQFaJt-kpjQLOscQuS1MrSLowO69S8SkRGw2MPGU6SzjPOiY6G3vjqK_REsDhPdnIDJYeFZhzpTVPX7IanRCRo582Oo3-LI7sH8hysSElvgelq0RURb_J83VKB0OriWi)