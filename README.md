# IMP - Inference Machine Pipeline

![IMP Logo](Imp.svg)

## Status: PetaLinux Transition Complete ⚠️

The bare-metal approach has been **abandoned** in favor of PetaLinux. See [BAREMETAL_FAILURES.md](BAREMETAL_FAILURES.md) for the complete story of what went wrong.

**Current Status:**
- ✅ FPGA bitstream built (`system_wrapper.bit`)
- ✅ PetaLinux setup documented
- ✅ SD card deployment scripts prepared
- ❌ **PetaLinux not yet installed on build PC**
- ❌ **Not yet tested on hardware**

---

## The IMP Project

The IMP project aims to run a 9B parameter neural network on a standard $250 KV260 board using ternary (1.58-bit) quantization and Gated Delta Networks. The system uses the FPGA for inference acceleration while an ARM processor manages loading, preprocessing, and orchestration.

Originally designed for bare-metal execution to maximize performance, the project has transitioned to PetaLinux due to persistent memory management issues.

---

## Architecture

```
                    ┌─────────────────┐
                    │   PetaLinux      │
                    │   (ARM A53)      │
                    └────────┬────────┘
                             │ /dev/uio0, /dev/mem
                             ▼
                    ┌─────────────────┐
                    │  FPGA Neural    │
                    │  Core Engine    │
                    │  (AXI4-Lite)    │
                    └────────┬────────┘
                             │
                    ┌────────▼────────┐
                    │     DDR4        │
                    │  (Model Weights)│
                    └─────────────────┘
```

**Key Features:**
- Ternary computation (-1, 0, +1) for 1.58-bit quantization
- FPGA for high-throughput inference
- Linux-based host for reliable model loading
- Brief language for neural network specification

---

## Quick Start (PetaLinux)

### Prerequisites
- KV260 Vision AI Starter Kit
- SD card (16GB+)
- Xilinx Vivado + PetaLinux 2023.2
- USB-UART cable for serial console

### Build & Deploy

```bash
# 1. Install PetaLinux tools
source ~/petalinux/settings.sh

# 2. Create project from BSP
petalinux-create -t project -s xilinx-kr260-starterboard-2023.2.bsp

# 3. Build
cd imp-platform
petalinux-build

# 4. Package for SD
petalinux-package --boot \
    --fsbl images/linux/zynqmp_fsbl.elf \
    --u-boot images/linux/u-boot.elf \
    --atf images/linux/bl31.elf \
    --kernel images/linux/image.ub \
    -o images/linux/BOOT.BIN

# 5. Flash to SD card (see PETA_LINUX_SETUP.md for full instructions)
```

### First Boot

```bash
# Serial console
screen /dev/ttyUSB1 115200

# Login: root / root

# Load FPGA
cat neuralcore.bit > /dev/fpga0

# Load model
cp model_9b.isp /var/models/

# Run inference
imp-inference "Hello, world"
```

---

## Documentation

| Document | Purpose |
|----------|---------|
| **[PETA_LINUX_DOWNLOADS.md](PETA_LINUX_DOWNLOADS.md)** | Download links & account setup |
| **[PETA_LINUX_SETUP.md](PETA_LINUX_SETUP.md)** | Complete PetaLinux setup guide |
| **[IMP_QUICK_START.md](IMP_QUICK_START.md)** | Detailed quick start |
| **[IMP_QUICK_CARD.md](IMP_QUICK_CARD.md)** | One-page reference card |
| **[DEPLOYMENT_CHECKLIST.md](DEPLOYMENT_CHECKLIST.md)** | Step-by-step deployment |
| **[BAREMETAL_FAILURES.md](BAREMETAL_FAILURES.md)** | Why bare-metal failed |
| **[SPEC_v0.1.md](SPEC_v0.1.md)** | Full architecture specification |
| **[INFERENCE_GUIDE.md](INFERENCE_GUIDE.md)** | Usage and protocol |

---

## Memory Map (KV260 DDR4)

| Region | Address | Size | Usage |
|--------|---------|------|-------|
| Linux RAM | 0x00000000 | 2GB | Kernel + userspace |
| FPGA Space | 0x80000000 | 2GB | FPGA + reserved |
| FPGA MMIO | 0x8000A000 | 4KB | Register access |
| FPGA BRAM | 0x88000000 | 512MB | On-chip memory |

---

## Project Structure

```
imp/
├── PETA_LINUX_SETUP.md     # PetaLinux guide (NEW)
├── IMP_QUICK_START.md      # Detailed quick start (NEW)
├── IMP_QUICK_CARD.md       # One-page reference (NEW)
├── BAREMETAL_FAILURES.md   # Bare-metal postmortem (NEW)
├── arm/
│   ├── kernel.c           # Bare-metal kernel (archived)
│   ├── linker.ld          # Linker script
│   └── kernel.bin         # Raw binary (unused)
├── boot/
│   ├── BOOT.BIN           # FSBL + bitstream
│   ├── system_wrapper.bit # FPGA bitstream
│   └── boot.cmd           # U-Boot script
├── brief-compiler/         # Brief language compiler
├── generated/             # Compiled SystemVerilog
├── scripts/
│   ├── create_sd_card.sh  # SD card prep script
│   └── build_and_deploy.sh # Build & deploy script
└── weights/
    ├── model_9b.isp       # 9B model weights (2.2GB)
    └── feeder.isp          # 0.5B feeder weights (867MB)
```

---

## Bare-Metal to PetaLinux Transition

### Why We Switched

| Issue | Bare-Metal | PetaLinux |
|-------|-----------|-----------|
| Model loading (2.2GB) | Blocked by U-Boot | `cat model.bin > /dev/...` |
| Boot reliability | Manual commands each time | Automatic on power-on |
| SD card access | Custom driver required | Built-in |
| Memory management | Manual, error-prone | Handled by kernel |
| Development speed | Slow (memory debugging) | Fast (standard tools) |

### Bare-Metal Postmortem Summary

1. **ELF vs Raw Binary**: `bootelf` parsed ELF header as instructions → Fixed by `objcopy`
2. **Memory Collision**: Kernel at 0x0 overwrote U-Boot → Fixed by using 0x20000000
3. **Model Loading**: U-Boot reservations blocked 2.2GB file at multiple addresses → **UNFIXABLE** without redesign
4. **Boot Mode**: KV260 boots from QSPI by default, no auto-execute from SD → Manual boot required

**See [BAREMETAL_FAILURES.md](BAREMETAL_FAILURES.md) for full details.**

---

## Research Foundations

This project builds on established research:

- **Ternary Quantization**: {-1, 0, +1} weights enabling 1.58-bit per parameter
- **Binary Neural Networks (XNOR-Net)**: Courbariaux et al., 2016
- **Gated Delta Networks**: Low-bandwidth recurrent architectures
- **Edge AI Compilation**: FPGA-accelerated inference on resource-constrained devices

See [RESEARCH_BIBLIOGRAPHY.md](RESEARCH_BIBLIOGRAPHY.md) for full citation list.

---

## Next Steps

1. **Install PetaLinux tools** on development PC
2. **Download KV260 BSP** from Xilinx
3. **Build PetaLinux project** (~2 hours)
4. **Flash SD card** with prepared scripts
5. **Boot KV260** and verify
6. **Load FPGA bitstream** and test
7. **Run first inference** on hardware

---

## License

Copyright (C) 2026 Randy Smits-Schreuder Goedheijt

See [LICENSE](LICENSE) file for details.

---

## Acknowledgments

This project was made possible by the foundational research of many intelligent individuals. See [RESEARCH_BIBLIOGRAPHY.md](RESEARCH_BIBLIOGRAPHY.md) for the papers and resources that informed this work.