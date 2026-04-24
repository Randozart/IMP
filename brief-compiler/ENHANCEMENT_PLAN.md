# Brief Compiler Enhancement Plan

## Status: AXI4-Lite Support Needed

The current neuralcore.sv only exposes `clk` and `rst_n` ports. Vivado needs AXI4-Lite ports to auto-connect the Zynq ARM processor to the FPGA fabric.

---

## 1. AXI4-Lite Interface Generation (HIGH PRIORITY)

### Problem
`hardware.toml` specifies `interface = "axi4-lite"` but the compiler ignores this and generates only clock/reset ports.

### Current Output
```systemverilog
module neuralcore (
    input logic clk,
    input logic rst_n
);
    // Internal registers only
```

### Required Output
```systemverilog
module neuralcore (
    input wire s_axi_aclk,
    input wire s_axi_aresetn,
    input wire [17:0] s_axi_awaddr,
    input wire [2:0] s_axi_awprot,
    input wire s_axi_awvalid,
    output logic s_axi_awready,
    // ... full AXI4-Lite interface
);
```

### Implementation Steps
1. Create `hardware_lib/interfaces/axi4_lite.toml` (ported from `imp/TARGET_ABSTRACTION.md`)
2. Add AXI port templates to `hardware_lib/` directory
3. Modify `src/backend/verilog.rs`:
   - Detect `interface = "axi4-lite"` in `hardware.toml`
   - Generate AXI ports instead of bare `clk`/`rst_n`
   - Generate address decode logic that maps `s_axi_awaddr` → internal registers

### Address Decode Template
```systemverilog
always_ff @(posedge s_axi_aclk) begin
    if (!s_axi_aresetn) begin
        // reset logic
    end else if (s_axi_wvalid && s_axi_awvalid) begin
        case (s_axi_awaddr)
            18'h00000: control <= s_axi_wdata[7:0];
            18'h00004: status <= s_axi_wdata[7:0];
            // ... map from hardware.toml addresses
        endcase
    end
end
```

---

## 2. Vivado Block Design Automation (MEDIUM PRIORITY)

### Problem
`build_imp.tcl` fails when creating Zynq IP block.

### Current Script
```tcl
create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5
```

### Required Fix
For Zynq UltraScale+ (KV260), use:
```tcl
create_bd_cell -type ip -vlnv xilinx.com:ip:zynq_ultra_ps_e:3.3
```

### Alternative
Use `apply_bd_automation` which auto-wires AXI interfaces:
```tcl
apply_bd_automation -rule xilinx.com:rule_bd:mem_and_periph_automation -obj [get_bd_cells zynq_ps]
```

---

## 3. Hardware Library Structure (LOW PRIORITY)

### Current
`interfaces/` contains only `.ebv` files (embedded values).

### Proposed Structure
```
hardware_lib/
├── interfaces/
│   ├── axi4_lite.toml      # NEW: AXI4-Lite port definition
│   ├── axi4_full.toml      # FUTURE: Full AXI for high-bandwidth
│   └── apb.toml            # FUTURE: APB for simple peripherals
├── templates/
│   ├── memory_map.sv       # Reusable memory map logic
│   └── interrupt_ctrl.sv  # Reusable interrupt handling
└── values/
    └── (existing .ebv files)
```

---

## 4. Immediate Workaround (CURRENT)

A manual AXI wrapper was created at `imp/neuralcore_axi.sv`. This file:
- Exposes full AXI4-Lite slave interface
- Instantiates the generated `neuralcore` module
- Maps AXI addresses to internal register ports

**To use:**
1. Include `neuralcore_axi.sv` in Vivado as top module
2. Use `apply_bd_automation` or connect `S_AXI` interface to Zynq

**Limitation:** Manual - must be regenerated if `neuralcore.sv` changes.

---

## References
- `imp/TARGET_ABSTRACTION.md` - Target-agnostic interface definitions
- `imp/neuralcore_axi.sv` - Working AXI wrapper example
- Xilinx PG059 - AXI Reference Guide