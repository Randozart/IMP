# IMP Boot Script v1.5 - Brief-Generated Split Model
# Memory Map:
#   0x00000000 - Model Part A (~1.1GB)
#   0x00100000 - Kernel (loaded first to avoid overlap)
#   0x46800000 - Context Cache A (~1.45GB)
#   GAP (2GB)   - MMIO registers
#   0x800000000 - Model Part B (~1.1GB)
#   0x86C000000 - Context Cache B (~984MB)

echo ========================================
echo IMP Boot v1.5 (Brief-Generated)
echo ========================================

# 1. Program FPGA fabric
echo [1/6] Programming FPGA...
load mmc 1:1 0x01000000 system_wrapper.bin
fpga load 0 0x01000000 $filesize

# 2. Load Kernel (at 0x00100000 to avoid model overlap)
echo [2/6] Loading kernel to 0x00100000...
load mmc 1:1 0x00100000 imp/kernel.bin

# 3. Load Model Part A (Low Bank - fills to gap at 0x46800000)
echo [3a/6] Loading model Part A to Low Bank...
load mmc 1:1 0x00000000 imp/model_part.aa

# 4. Load Model Part B (High Bank)
echo [3b/6] Loading model Part B to High Bank...
load mmc 1:1 0x800000000 imp/model_part.ab

# 5. Memory setup complete
echo [4/6] Memory initialized...
echo [5/6] Model loaded...

# 6. Boot kernel
echo [6/6] Starting IMP at 0x00100000...
echo ========================================
go 0x00100000
