# IMP KV260 Kernel Build & Deployment

## Files Created

```
arm/
├── kernel.elf          # Compiled kernel (72KB) - COPY THIS TO SD
├── kernel_full.c       # Full implementation source
├── kernel_minimal.c     # Minimal test version
├── linker.ld           # Linker script
├── memory.ld           # Memory layout
└── startup.s           # ARM64 startup assembly
```

## Current Kernel Features

1. **UART** - Debug output @ 115200 baud
2. **SD Card** - Initialization (stub)
3. **FAT Filesystem** - File listing (stub)
4. **Model Loading** - ISP format parsing (stub)
5. **FPGA Communication** - AXI4-Lite MMIO at 0x8000A000:
   - control: Command register
   - status: FPGA state
   - opcode: Layer type
   - token_count: Number of tokens
   - write_data / write_addr / write_en: Mailbox
   - read_data / read_en: Readback

## Boot Process

1. **U-Boot loads kernel.elf from SD to DDR4 @ 0x00120000**
2. **U-Boot executes `go 0x00120000`**
3. **Kernel initializes:**
   - UART0 (@ 0xFF0A0000)
   - SD card
   - FAT filesystem
   - Model loading from `imp/model_9b.isp` and `imp/feeder.isp`
   - FPGA verification

## Commands (via UART)

| Key | Action |
|-----|--------|
| 1 | Load weights to FPGA |
| 2 | Send input tokens |
| 3 | Execute layer |
| 4 | Read results |
| h | Help |

## Testing with U-Boot

```
ZynqMP> fatload mmc 1:1 0x00120000 kernel.elf
ZynqMP> go 0x00120000
```

## Expected Output

```
========================================
IMP Kernel v1.0 - KV260
Ternary Neural Network Inference
========================================

[1/6] Initializing UART... OK
[2/6] Initializing SD card... OK
[3/6] Initializing FAT filesystem... OK
[4/6] Loading model_9b.isp to DDR4 @ 0x10000000... ...... done
[5/6] Loading feeder.isp to DDR4 @ 0x70000000... ...... done
[6/6] Verifying FPGA connection... OK (status=0x0)

========================================
IMP Ready for Inference!
========================================

MMIO Registers:
  0x8000A000 - control   (write)
  0x8000A004 - status    (read)
...

Commands:
  1 - Start inference (load weights to FPGA)
  2 - Send input tokens
  3 - Execute layer
  4 - Read results

IMP> 
```

## To Do

- [x] Build minimal kernel with UART ✅
- [x] Build full kernel with FPGA MMIO ✅
- [ ] Implement actual SD card reading (needs Xilinx BSP or custom driver)
- [ ] Implement FAT filesystem parsing
- [ ] Implement model streaming from DDR4 to FPGA
- [ ] Test on actual hardware

## Next Steps After Testing

Once kernel boots successfully:
1. Implement `sd_read_block()` using Xilinx SD host controller
2. Implement FAT filesystem parsing3. Add model streaming from DDR4 to FPGA BRAM
4. Add inference loop