# IMP Model Downloads

This document describes how to download and prepare quantized ternary models for the KV260 FPGA inference engine.

## Download Instructions

### 1. Ternary-Bonsai-8B (9B model weights)

```bash
pip install huggingface_hub
huggingface-cli download prism-ml/Ternary-Bonsai-8B-mlx-2bit model.safetensors
```

Or with Python:
```python
from huggingface_hub import hf_hub_download
path = hf_hub_download(repo_id="prism-ml/Ternary-Bonsai-8B-mlx-2bit", filename="model.safetensors")
```

**Size:** 2.3 GB
**Source:** https://huggingface.co/prism-ml/Ternary-Bonsai-8B-mlx-2bit

### 2. BitCPM4-0.5B (feeder model)

```bash
huggingface-cli download openbmb/BitCPM4-0.5B model.safetensors
mv model.safetensors feeder_0.5b.bin
```

Or directly:
```bash
curl -L -o feeder_0.5b.bin "https://huggingface.co/openbmb/BitCPM4-0.5B/resolve/main/model.safetensors"
```

**Size:** 868 MB
**Source:** https://huggingface.co/openbmb/BitCPM4-0.5B

## Preparation

Convert models to ISP format for FPGA loading:

```bash
cd imp
mkdir -p weights
# Copy downloaded files to weights/

python3 scripts/prepare_model.py --model weights/model.safetensors --output weights/model_9b.isp --type qwen9b
python3 scripts/prepare_model.py --model weights/feeder_0.5b.bin --output weights/feeder.isp --type feeder
```

## SD Card Layout

Copy to FAT32 SD card:

```
/BOOT.BIN              # Bitstream + FSBL + kernel
/model_9b.isp          # 9B model weights (~2.2 GB)
/feeder.isp            # Feeder model (~828 MB)
```

## Memory Map

| Model | DDR4 Address | Size |
|-------|-------------|------|
| 9B | 0x1000_0000 | 2.2 GB |
| Feeder | 0x7000_0000 | 828 MB |

## Notes

- Models are ternary quantized (1.58-bit weights)
- FPGA has 512KB BRAM for active layer
- Weights streamed from DDR4 via AXI mailbox
- No full model fits in BRAM - must stream per layer