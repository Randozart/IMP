# IMP Automated Boot Script for KV260 (v1.2 Fixed)
# Memory Map (Safe for 4GB DDR):
#   0x00080000  - Kernel entry (256MB region starting at 0x00000000)
#   0x10000000  - 9B Model (2.25GB)
#   0xA0000000  - Feeder Model (867MB)
#   0xD4000000  - Working RAM (~700MB)

echo ========================================
echo IMP Boot Sequence v1.2 (aarch64)
echo ========================================

# 1. Program FPGA fabric
echo [1/5] Programming FPGA...
load mmc 1:1 0x01000000 system_wrapper.bin
fpga load 0 0x01000000 $filesize

# 2. Load Kernel (Load this early so weights don't sit on it)
echo [2/5] Loading kernel to 0x00080000...
load mmc 1:1 0x00080000 imp/kernel.bin

# 3. Load Foundation model (9B) - 2.2GB
echo [3/5] Loading model_9b.isp to 0x10000000...
echo WARNING: This takes approximately 2-3 minutes...
load mmc 1:1 0x10000000 imp/model_9b.isp

# 4. Load Drafter model (0.5B)
echo [4/5] Loading feeder.isp to 0xA0000000...
load mmc 1:1 0xA0000000 imp/feeder.isp

# 5. Execute
echo [5/5] Starting IMP kernel at 0x00080000...
echo ========================================
go 0x00080000

# If we get here, kernel exited
echo KERNEL EXITED