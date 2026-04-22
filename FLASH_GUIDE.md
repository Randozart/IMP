# KV260 Flashing Guide

This guide explains how to build and deploy the IMP (Inference Machine Pipeline) onto the Xilinx Kria KV260 board.

## Overview

The IMP system has two compilation targets:

| Layer | File | Output | Runs on |
|-------|------|--------|---------|
| Software | `kernel.ebv` | ARM ELF (`kernel.rs` → Rust) | Cortex-A53 (PS) |
| Hardware | `neuralcore.ebv` | SystemVerilog → Bitstream | FPGA (PL) |

## Prerequisites

- Xilinx Vivado (for SystemVerilog synthesis to bitstream)
- ARM cross-compiler: `arm-none-eabi-gcc`
- `mkimage` (from U-Boot tools)
- `bootgen` (from Xilinx SDK)
- SD card (FAT32 formatted)

---

## Step 1: Build the Software Kernel

```bash
# Generate ARM Rust code from kernel.ebv
./brief-compiler arm kernel.ebv -o arm/

# Compile Rust to ARM ELF
# (You'll need a Rust + ARM target setup)
rustc --target arm-none-eabi kernel.rs -o kernel.elf
```

**Note:** The `kernel.rs` generated is a state machine library. You'll need to write a `main.rs` that:
1. Instantiates the `State` struct
2. Casts it to the hardware MMIO address: `0x4000A000`
3. Runs the transaction loop

Example `main.rs`:
```rust
// Point to FPGA memory-mapped registers
let state = unsafe { &mut *(0x4000A000 as *mut State) };

loop {
    // Run transactions based on current state
    if state.control == 1 {
        kernel::load_input(state);
    } else if state.control == 2 {
        kernel::execute(state);
    }
    // ...
}
```

---

## Step 2: Build the FPGA Bitstream

```bash
# Generate SystemVerilog from neuralcore.ebv
./brief-compiler verilog neuralcore.ebv --hw hardware.toml -o ./

# This produces:
#   neuralcore.sv  - Your hardware design
#   neuralcore_tb.sv - Testbench
```

### In Vivado:

1. **Create new project** → Parts → `xczu4ev-sfvc784-1`
2. **Add sources** → `neuralcore.sv`
3. **Run synthesis:** `ynth_design`
4. **Run implementation:** `impl_design`
5. **Generate bitstream:** `write_bitstream -force neuralcore.bit`

This produces `neuralcore.bit` (your FPGA bitstream).

---

## Step 3: Create BOOT.BIN

The KV260 boot process:
```
ROM → FSBL → Arm Trusted Firmware → U-Boot → Your Kernel
```

### Required components:

| File | Source | Purpose |
|------|--------|---------|
| `FSBL.elf` | Xilinx BSP | First Stage Bootloader |
| `bl31.elf` | Xilinx BSP | ARM Trusted Firmware |
| `u-boot.elf` | Build U-Boot | Bootloader |
| `system.dtb` | You create | Device Tree |
| `kernel.elf` | Step 1 | Your bare-metal app |
| `neuralcore.bit` | Step 2 | FPGA bitstream |

### Create BIF file (`boot.bif`):
```bib
the_ROM_image:
{
    [fsbl] fsbl.elf
    [pmufw] pmufw.elf
    [trustzone] bl31.elf
    [bootloader] u-boot.elf
    [offset] 0x40000               @ FPGA bitstream offset
    neuralcore.bit
    [offset] 0x600000              @ Kernel offset
    kernel.elf
    [offset] 0x800000              @ DTB offset
    system.dtb
}
```

### Generate BOOT.BIN:
```bash
bootgen -image boot.bif -o BOOT.BIN -w
```

---

## Step 4: Prepare SD Card

```
SD Card (FAT32):
├── BOOT.BIN      # Complete boot image
├── boot.scr      # U-Boot script
└── system.dtb    # Device tree (if separate)
```

### Create boot.scr:
```bash
# Create boot.cmd
echo "fatload mmc 0:1 0x4000A000 kernel.elf" > boot.cmd
echo "bootelf 0x4000A000" >> boot.cmd

# Compile to boot.scr
mkimage -A arm -T script -C none -n "IMP Boot" -d boot.cmd boot.scr
```

---

## Step 5: Flash and Boot

1. **Format SD card** as FAT32
2. **Copy files:**
   ```bash
   cp BOOT.BIN /mnt/sdcard/
   cp boot.scr /mnt/sdcard/
   ```
3. **Insert SD card** into KV260
4. **Set boot mode** to SD card (SW4 switches)
5. **Power on** - the board will boot through the chain and launch your kernel

---

## Boot Mode Switches (SW4)

| Switch | Position | Boot Device |
|--------|----------|-------------|
| SW4.1 | OFF | QSPI |
| SW4.2 | OFF | SD Card |
| SW4.3 | ON | USB |
| SW4.4 | OFF | JTAG |

For SD card boot: **SW4.1=OFF, SW4.2=OFF, SW4.3=ON, SW4.4=OFF**

---

## Troubleshooting

### Kernel not loading
- Check U-Boot console output
- Verify `kernel.elf` is valid ARM executable: `file kernel.elf`
- Ensure address alignment in boot.scr

### FPGA not configuring
- Check if `neuralcore.bit` is valid: `file neuralcore.bit`
- Verify BOOT.BIN contains bitstream
- Check FPGA DONE LED

### No communication
- Verify MMIO addresses match (`0x4000A000`)
- Check UART connection (115200 baud)
- Use `devmem` to read/write registers from Linux if debugging

---

## Quick Reference Commands

```bash
# Generate all outputs
./brief-compiler arm kernel.ebv -o arm/
./brief-compiler verilog neuralcore.ebv --hw hardware.toml -o ./

# Build BOOT.BIN
bootgen -image boot.bif -o BOOT.BIN -w

# Create boot script
mkimage -A arm -T script -C none -n "IMP Boot" -d boot.cmd boot.scr
```