# IMP Research Bibliography & Theoretical Foundation

This document serves as the formal theoretical grounding for the **Inference Machine Pipeline (IMP)**. It outlines the specific academic breakthroughs in quantization, linear attention, hardware-level speculative decoding, and FPGA co-design that make the IMP architecture physically viable on edge silicon.

For LLM-assisted development or verification, this file provides the necessary context window to understand the engineering constraints and mathematical strategies used in `neuralcore.ebv` and `kernel.ebv`.

---

## I. Ternary & 1.58-Bit Quantization (Bypassing DSP Limits)
*The mathematical foundation that allows the IMP to replace costly DSP multiplier blocks with purely combinational logic (LUTs) by constraining weights to `{-1, 0, 1}`.*

1. **The Era of 1-bit LLMs: All Large Language Models are in 1.58 Bits**
   * *Authors:* Shuming Ma, Hongyu Wang, et al. (Microsoft Research)
   * *Published:* February 2024
   * *Link:*[arXiv:2402.17764](https://arxiv.org/abs/2402.17764)
   * *Relevance to IMP:* The foundational BitNet b1.58 paper proving that ternary representation achieves parity with FP16 models, unlocking the ability to map neural weights directly to FPGA logic cells instead of DSPs.

2. **TeLLMe: An Energy-Efficient Ternary LLM Accelerator for Prefill and Decode on Edge FPGAs**
   * *Authors:* Ye Qiao, Zhiheng Cheng, et al. (UC Irvine)
   * *Published:* April 2025
   * *Link:*[arXiv:2504.16266](https://arxiv.org/abs/2504.16266)
   * *Relevance to IMP:* Demonstrates the exact feasibility of running 1.58-bit LLMs on the AMD Kria KV260 board utilizing Table-Lookup Matrix Multiplication (TLMM) under strict power budgets (< 7W).

3. **TerEffic: Highly Efficient Ternary LLM Inference on FPGA**
   * *Published:* February 2025
   * *Link:* [arXiv:2502.16434](https://arxiv.org/abs/2502.16434)
   * *Relevance to IMP:* Details compute-memory alignment strategies for ternary matrices, proving that on-chip execution of 1.58-bit models maximizes FPGA BRAM/UltraRAM utilization.

---

## II. Persistent-State Linear Attention (Bounding the KV Cache)
*The architectural foundation that prevents the Context Window from overflowing the KV260's 4GB DDR4 limit by replacing standard attention with Gated Delta Networks.*

4. **Gated Delta Networks: Improving Mamba2 with Delta Rule**
   * *Authors:* Songlin Yang, et al. (ICLR 2025)
   * *Published:* December 2024 (Camera Ready Mar 2025)
   * *Link:*[arXiv:2412.06464](https://arxiv.org/abs/2412.06464)
   * *Relevance to IMP:* The theoretical basis for the Qwen 3.5 9B architecture. It proves that combining adaptive memory control (gating) with precise memory modification (delta rule) creates a fixed-size, persistent hidden state that solves the memory-bound constraints of long-context generation.

5. **A Persistent-State Dataflow Accelerator for Memory-Bound Linear Attention Decode on FPGA**
   * *Published:* March 2026
   * *Link:* [arXiv:2603.05931](https://arxiv.org/abs/2603.05931)
   * *Relevance to IMP:* The physical hardware blueprint for why the IMP maps the KV cache to UltraRAM. Proves that GDN recurrence can be pipelined in hardware to perform only one read/write pass per token, neutralizing the sequence-length scaling tax.

---

## III. Hardware-Accelerated Speculative Decoding
*The algorithmic strategy that artificially widens the 19.2 GB/s AXI-DMA bandwidth limit by parallelizing token verification.*

6. **HADES: Hardware Accelerated Decoding for Efficient Speculation in Large Language Models**
   * *Authors:* Ze Yang, Yihong Jin, Xinhe Xu
   * *Published:* December 2024
   * *Link:* [arXiv:2412.19925](https://arxiv.org/abs/2412.19925)
   * *Relevance to IMP:* The first major paper exploring hardware-level support for speculative decoding. Proves that hardware accelerators can execute the verification phase of drafted tokens vastly faster and with exponentially higher energy efficiency than flagship GPUs.

7. **SpecMamba: Accelerating Mamba Inference on FPGA with Speculative Decoding**
   * *Authors:* Linfeng Zhong, et al. (Peking University / ICCAD 2025)
   * *Published:* September 2025
   * *Link:* [arXiv:2509.19873](https://arxiv.org/abs/2509.19873)
   * *Relevance to IMP:* Details the precise system-level co-design (Memory-aware hybrid backtracking, FIFO tree verification) required to make speculative decoding function efficiently on an AMD FPGA platform without hardware workload mismatch.

---

## IV. Edge FPGA Implementation & Co-Design
*The systems-engineering principles confirming that bare-metal execution on the Zynq UltraScale+ architecture is the optimal path for inference.*

### 8. PD-Swap
**PD-Swap: Prefill–Decode Logic Swapping for End-to-End LLM Inference on Edge FPGAs via Dynamic Partial Reconfiguration**
*   **Authors:** Yifan Zhang, Zhiheng Chen, Ye Qiao, Sitao Huang (UC Irvine)
*   **Published:** December 12, 2025
*   **arXiv ID:** `2512.11550`
*   **Link:**[https://arxiv.org/abs/2512.11550](https://arxiv.org/abs/2512.11550)
*   **Relevance to IMP:** This paper explicitly explores the "prefill-decode asymmetry." It validates your strategy of separating the compute-heavy prefill (matrix operations) from the bandwidth-heavy decoding (KV-cache traffic), and outlines how Dynamic Partial Reconfiguration (DPR) on edge FPGAs can prevent the quadratic cost of sequence lengths from crippling your 19.2 GB/s DDR4 limit.

### 9. TENET
**TENET: An Efficient Sparsity-Aware LUT-Centric Architecture for Ternary LLM Inference On Edge**
*   **Authors:** Zhirui Huang, Rui Ma, Shijie Cao, et al.
*   **Published:** September 17, 2025
*   **arXiv ID:** `2509.13765`
*   **Link:**[https://arxiv.org/abs/2509.13765](https://arxiv.org/abs/2509.13765)
*   **Relevance to IMP:** This is the smoking gun for your ternary math pipeline. It introduces the "Sparse Ternary LUT (STL) Core," proving that mapping `-1, 0, 1` weights directly to Lookup Tables (LUTs) rather than DSPs or add-only trees cuts power consumption by nearly 46% and area by 52%. It mathematically grounds your Brief compiler's approach to translating ternary operations into combinational logic.

---
*Generated for IMP v0.1 — April 2026*