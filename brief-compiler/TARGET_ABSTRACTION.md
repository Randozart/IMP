# Target Abstraction Layer

**Goal:** Make the Brief compiler portable across FPGA targets by abstracting vendor-specific details into configuration files.

---

## Philosophy

Brief stays pure. Vendor magic goes in TOML.

```
+------------------+     +-----------------------+     +------------------+
|   Brief Source   | --> |   brief-compiler     | --> |  Target Config   |
|   (pure .ebv)    |     |   (pure logic)       |     |  (vendor.toml)   |
+------------------+     +-----------------------+     +------------------+
                                                           |
                                                           v
                                                    +------------+
                                                    | Generated |
                                                    | Output    |
                                                    +------------+
```

---

## Interface Specification

### AXI4-Lite Slave Interface (S_AXI)

Vivado auto-detects ports named `s_axi_*` and creates an `S_AXI` interface.

#### Port List
```systemverilog
module <module_name> (
    // Clock and Reset
    input  wire        s_axi_aclk,      // Clock
    input  wire        s_axi_aresetn,   // Active-low reset
    
    // Write Address Channel
    input  wire [17:0] s_axi_awaddr,    // Write address (byte addressable)
    input  wire [2:0]  s_axi_awprot,    // Protection mode
    input  wire        s_axi_awvalid,    // Write address valid
    output logic       s_axi_awready,   // Write address ready
    
    // Write Data Channel
    input  wire [31:0] s_axi_wdata,     // Write data
    input  wire [3:0]  s_axi_wstrb,     // Write strobes
    input  wire        s_axi_wvalid,    // Write data valid
    output logic       s_axi_wready,    // Write data ready
    
    // Write Response Channel
    output logic [1:0] s_axi_bresp,     // Write response
    output logic       s_axi_bvalid,     // Write response valid
    input  wire        s_axi_bready,    // Write response ready
    
    // Read Address Channel
    input  wire [17:0] s_axi_araddr,    // Read address
    input  wire [2:0]  s_axi_arprot,    // Protection mode
    input  wire        s_axi_arvalid,   // Read address valid
    output logic       s_axi_arready,   // Read address ready
    
    // Read Data Channel
    output logic [31:0] s_axi_rdata,    // Read data
    output logic [1:0] s_axi_rresp,     // Read response
    output logic       s_axi_rvalid,    // Read data valid
    input  wire        s_axi_rready     // Read data ready
);
```

#### Register Address Map
| Address | Register | Access | Description |
|---------|----------|--------|-------------|
| 0x00 | CONTROL | RW | Command register |
| 0x04 | STATUS | RO | FSM status (read-only) |
| 0x08 | OPCODE | RW | Operation code |
| 0x0C | TOKEN_COUNT | RW | Token count |
| 0x40 | WRITE_DATA | WO | Mailbox write data |
| 0x44 | WRITE_ADDR | WO | Mailbox write address |
| 0x48 | WRITE_EN | WO | Mailbox write enable |
| 0x4C | READ_EN | WO | Mailbox read enable |
| 0x50 | READ_DATA | RO | Mailbox read data (read-only) |

---

## Target Configuration Format

### hardware.toml
```toml
[target]
name = "kv260"
part = "xck26-sfvc784-2LV-c"

[interface]
name = "axi4-lite"
base_address = "0x8000A000"

[memory]
bram_size = "512KB"

[constraints]
max_frequency = 100
```

---

## Implementation Checklist

- [x] Define interface port spec (this document)
- [x] Define address map
- [ ] Create `hardware_lib/interfaces/axi4_lite.toml`
- [ ] Add AXI port generation to `src/backend/verilog.rs`
- [ ] Add address decode logic generation
- [ ] Add block design automation support to TCL generator
- [ ] Test on KV260 hardware

---

## References

- Xilinx PG059: AXI Reference Guide
- Xilinx UG583: UltraScale Architecture-Based Design
- KV260 Technical Reference