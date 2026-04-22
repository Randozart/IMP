# IMP - Inference Machine Pipeline

![IMP Logo](Imp.svg)

## ⚠️ DEVELOPMENT STATUS - UNTESTED ON PHYSICAL HARDWARE ⚠️

This project is in active development. The system has been:
- ✅ Designed with correct KV260 memory constraints (single 512KB BRAM buffer)
- ✅ Compiled through brief-compiler to valid SystemVerilog
- ✅ Verified with Verilator lint and simulation
- ❌ **NOT YET tested on actual KV260 hardware**

**Do not deploy to production hardware without physical validation.**

---

## The IMP Project

The IMP project is a response to the centralization of AI into subscription-based cloud services. Over two weeks of development, I created a custom language called Brief to map neural network operations directly to FPGA gate logic. By combining 1.58-bit ternary quantization with Gated Delta Networks, the system enables a 9B parameter model to run on a standard $250 Kria KV260 board. Executing bare-metal on the ARM processor removes the overhead of a traditional operating system, maximizing memory availability and reducing the 19.2 GB/s bandwidth bottleneck.

I am open-sourcing the IMP engine and the Brief compiler under the GPLv2 license to ensure the logic remains a public, reciprocal resource. This architecture significantly lowers the environmental footprint of AI by replacing data-center power requirements with efficient, edge-native silicon logic. The goal is to provide individuals with the hardware design tools and model access usually reserved for large corporations. By moving AI from a rented service to locally-owned hardware, we ensure that the ability to process and generate information remains a permanent utility under the user's direct control.

---

## Architecture

```
                    ┌─────────────────┐
                    │  ARM Cortex-A53 │
                    │  (Brief Kernel) │
                    └────────┬────────┘
                             │ AXI4-Lite MMIO
                             ▼
                    ┌─────────────────┐
                    │  FPGA Neural    │
                    │  Core Engine    │
                    │  (SystemVerilog)│
                    └────────┬────────┘
                             │
                    ┌────────▼────────┐
                    │     DDR4        │
                    │  (Model Weights) │
                    └─────────────────┘
```

**Key Features:**
- Ternary computation (-1, 0, +1) for 1.58-bit quantization
- Single 512KB BRAM buffer streamed from DDR4
- Bare-metal ARM execution (no OS overhead)
- Brief language compiles to both ARM and FPGA

---

## Quick Start

### Prerequisites
- KV260 board
- Rust toolchain for ARM (`thumbv7neon-none-eabihf`)
- Xilinx Vivado (for FPGA synthesis)
- Verilator (for simulation)

### Build & Simulate
```bash
# Generate hardware from Brief specification
./brief-compiler verilog neuralcore.ebv --hw hardware.toml -o generated/

# Run Verilator simulation
./run_sim.sh

# View waveforms
gtkwave sim_build/waveform.vcd
```

### Deploy to SD Card
```bash
./build_sdcard.sh /path/to/sdcard
```

---

## Research Foundations

This project builds on established research in binary neural networks and edge AI acceleration:

- **Ternary Quantization**: {-1, 0, +1} weights enabling 1.58-bit per parameter
- **Binary Neural Networks (XNOR-Net)**: Courbariaux et al., 2016
- **Gated Delta Networks**: Low-bandwidth recurrent architectures
- **Edge AI Compilation**: FPGA-accelerated inference on resource-constrained devices

See [RESEARCH_BIBLIOGRAPHY.md](RESEARCH_BIBLIOGRAPHY.md) for full citation list.

---

## Project Structure

```
imp/
├── neuralcore.ebv       # FPGA neural engine (Brief)
├── kernel.ebv           # ARM kernel specification (Brief)
├── hardware.toml        # KV260 memory map & constraints
├── arm/
│   ├── kernel.rs        # ARM bare-metal implementation
│   └── memory.ld        # Linker script (DDR4 at 0x0)
├── generated/           # Compiled SystemVerilog
├── run_sim.sh           # Verilator simulation
├── build_sdcard.sh      # SD card builder
├── SPEC_v0.1.md         # Full architecture specification
└── Imp.svg              # Project logo
```

---

## Documentation

| Document | Purpose |
|----------|---------|
| [SPEC_v0.1.md](SPEC_v0.1.md) | Full architecture specification |
| [INFERENCE_GUIDE.md](INFERENCE_GUIDE.md) | Usage and TCP protocol |
| [Build_Workflow.md](Build_Workflow.md) | Build pipeline |
| [FLASH_GUIDE.md](FLASH_GUIDE.md) | SD card deployment |
| [Hardware_Config_Guide.md](Hardware_Config_Guide.md) | hardware.toml reference |

---

## Known Limitations

- **Weight Loading**: DDR4→FPGA streaming not fully implemented
- **Tokenizer**: Simple fallback (no BPE vocabulary loaded)
- **TCP Stack**: Stub (needs LwIP integration)
- **FPGA Synthesis**: Not yet run through Vivado
- **Physical Testing**: No hardware validation performed

---

## License

Copyright (C) 2026 Randy Smits-Schreuder Goedheijt

See [LICENSE](LICENSE) file for details.

---

## Acknowledgments

This project was made possible by the foundational research of the binary neural network community. See [RESEARCH_BIBLIOGRAPHY.md](RESEARCH_BIBLIOGRAPHY.md) for the papers and resources that informed this work.