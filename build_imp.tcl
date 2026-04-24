# IMP KV260 Automated Build Script
# 
# USAGE:
#   1. Copy this script to your Vivado machine
#   2. Copy generated/neuralcore.sv to the same directory
#   3. Run: vivado -mode batch -source build_imp.tcl
#
# REQUIREMENTS:
#   - Xilinx Vivado 2024.1 or later
#   - neuralcore.sv in the same directory as this script

# ============================================================
# CONFIGURATION
# ============================================================
# KV260 KV260 part number: xck26-sfvc784-2LV-c
# This is the actual chip on the KV260 Vision AI Starter Kit
set part_number "xck26-sfvc784-2LV-c"
# Alternative part numbers that may work if above doesn't:
# - xczu4ev-sfvc784-1 (older stand-in, requires full Vivado install)
# - xczu4ev-sfvc784-1-e (commercial temp grade)
# - xczu4ev-sfvc784-1-i (industrial temp grade)

# ============================================================
# PROJECT SETUP
# ============================================================
puts "=== IMP KV260 Automated Build ==="
puts "Part: $part_number"
puts "Top module: $top_module"

# Create project (overwrite if exists)
if {[file exists $project_name]} {
    puts "Removing existing project..."
    file delete -force $project_name
}

puts "Creating project: $project_name"
create_project $project_name . -part $part_number -force

# ============================================================
# ADD SOURCE FILES
# ============================================================
if {[file exists $sv_file]} {
    puts "Adding source: $sv_file"
    add_files -fileset sources_1 $sv_file
    set_property top $top_module [current_fileset]
} else {
    puts "ERROR: Source file not found: $sv_file"
    exit 1
}

# ============================================================
# CREATE BLOCK DESIGN
# ============================================================
puts "Creating block design..."
create_bd_design "system"

# Add Zynq UltraScale+ processing system
create_bd_cell -type ip -vlnv xilinx.com:ip:zynq_ultra_ps_e:3.4 zynq_ps

# Run block automation for Zynq (DDR, clocks, etc.)
apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 -config [get_bd_intf_pins zynq_ps/ps7/GP0] [get_bd_cells zynq_ps]

# Add our neuralcore module
create_bd_cell -type module -reference $top_module neuralcore_0

# ============================================================
# CONNECT CLOCK AND RESET
# ============================================================
puts "Connecting clock and reset..."

# Create clock pin from Zynq FCLK0
create_bd_pin -dir I -type clk zynq_ps_fclk0
set_property CONFIG.FREQ_HZ 100000000 [get_bd_pins zynq_ps_fclk0]
connect_bd_net [get_bd_pins zynq_ps/fclk_clk0] [get_bd_pins neuralcore_0/clk]

# Create reset pin
create_bd_pin -dir I -type rst zynq_ps_rst0
connect_bd_net [get_bd_pins zynq_ps/aux_resetn] [get_bd_pins neuralcore_0/rst_n]

# ============================================================
# AXI CONNECTION
# ============================================================
puts "Connecting AXI interface..."

# KV260 uses M_AXI_GP0 or M_AXI_HPM0_LPD depending on Vivado version
# Try HPM0_LPD first (newer Vivado), fall back to GP0
setaxi_port "M_AXI_HPM0_LPD"

if {[catch {apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config [list Master $setaxi_port] [get_bd_intf_pins neuralcore_0/S_AXI]} err]} {
    puts "First AXI port failed ($err), trying GP0..."
    setaxi_port "M_AXI_GP0"
    apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config [list Master $setaxi_port] [get_bd_intf_pins neuralcore_0/S_AXI]
}

puts "Connected to $setaxi_port"

# ============================================================
# ASSIGN ADDRESSES (CRITICAL)
# ============================================================
puts "Assigning addresses..."

# Get the address segment
set addr_seg [get_bd_addr_segs neuralcore_0/S_AXI/reg0]

# Set address to 0x8000_0000 for KV260 (Zynq UltraScale+ FPGA range)
set_property offset 0x80000000 $addr_seg
set_property range 64K $addr_seg

# Verify address
set assigned_offset [get_property OFFSET $addr_seg]
puts "Assigned base address: $assigned_offset"

if {$assigned_offset == "0x80000000"} {
    puts "✓ Address correctly set to 0x80000000"
} else {
    puts "WARNING: Address is $assigned_offset, expected 0x80000000"
}

# ============================================================
# GENERATE BITSTREAM
# ============================================================
puts "Generating bitstream..."

# Run synthesis
puts "Running synthesis..."
launch_runs synth_1 -jobs 4
wait_on_run synth_1

# Check for synthesis errors
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    puts "ERROR: Synthesis failed"
    exit 1
}
puts "Synthesis complete"

# Open synthesized design
open_run synth_1

# Run implementation  
puts "Running implementation..."
launch_runs impl_1 -jobs 4
wait_on_run impl_1

# Check for implementation errors
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    puts "ERROR: Implementation failed"
    exit 1
}
puts "Implementation complete"

# Open implemented design
open_run impl_1

# Generate bitstream
puts "Generating bitstream..."
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

puts "=== BUILD COMPLETE ==="
puts "Bitstream: $project_name.runs/impl_1/design_1.bit"

# ============================================================
# SUMMARY
# ============================================================
puts ""
puts "Build Summary:"
puts "- Project: $project_name"
puts "- Part: $part_number"
puts "- Top module: $top_module"
puts "- Address space: 0x80000000 (64K)"
puts "- Output: $project_name.runs/impl_1/design_1.bit"

exit 0