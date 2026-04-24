# IMP KV260 Automated Build Script
# 
# USAGE:
#   1. Copy neuralcore.sv to same directory as this script
#   2. Run: vivado -mode batch -source build_imp.tcl
#
# REQUIREMENTS:
#   - Xilinx Vivado 2023.1 or later
#   - neuralcore.sv in the same directory

# ============================================================
# CONFIGURATION
# ============================================================
# KV260 part number: xck26-sfvc784-2LV-c (actual chip on KV260 board)
set part_number "xck26-sfvc784-2LV-c"
set project_name "imp_kv260"
set top_module "neuralcore"
set sv_file "neuralcore.sv"

puts "=== IMP KV260 Automated Build ==="
puts "Part: $part_number"
puts "Top module: $top_module"

# ============================================================
# CLEANUP
# ============================================================
if {[file exists $project_name]} {
    puts "Removing existing project..."
    file delete -force $project_name
}
if {[file exists "ip_repo"]} {
    file delete -force "ip_repo"
}
if {[file exists "ip_packager_proj"]} {
    file delete -force "ip_packager_proj"
}

# ============================================================
# VERIFY SOURCE FILE EXISTS
# ============================================================
if {![file exists $sv_file]} {
    puts "ERROR: Source file not found: $sv_file"
    puts "Please copy generated/neuralcore.sv to this directory"
    exit 1
}

# ============================================================
# PACKAGE SYSTEMVERILOG AS IP
# ============================================================
puts "Packaging SystemVerilog as IP..."

# Create temporary project for packaging
create_project -force ip_packager_proj ./ip_packager_proj -part $part_number
add_files $sv_file
set_property top $top_module [current_fileset]
update_compile_order -fileset sources_1

# Package as IP
ipx::package_project -root_dir ./ip_repo -vendor user.org -library user -taxonomy /UserIP -import_files

# Save and close
set core [ipx::current_core]
ipx::save_core $core
close_project

puts "Creating main project..."

# ============================================================
# CREATE MAIN PROJECT
# ============================================================
create_project -force $project_name . -part $part_number

# Add custom IP repository
set_property ip_repo_paths "[pwd]/ip_repo" [current_project]
update_ip_catalog

# ============================================================
# ADD SOURCES
# ============================================================
puts "Adding source files..."
add_files -fileset sources_1 $sv_file
set_property top $top_module [current_fileset]

# ============================================================
# CREATE BLOCK DESIGN
# ============================================================
puts "Creating block design..."
create_bd_design "system"

# Add Zynq UltraScale+ - use simpler VLNV
if {[catch {create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 zynq_ps} err]} {
    puts "Trying alternate Zynq IP..."
    create_bd_cell -type ip -vlnv xilinx.com:ip:sys_block:1.0 zynq_ps
}

# ============================================================
# RUN BLOCK AUTOMATION (DDR, CLOCKS)
# ============================================================
puts "Running block automation..."
if {![catch {apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 -config [get_bd_intf_pins zynq_ps/PS7] [get_bd_cells zynq_ps]} err]} {
    puts "Block automation completed"
}

# ============================================================
# ADD NEURALCORE IP
# ============================================================
puts "Adding neuralcore module..."
if {![catch {create_bd_cell -type module -reference $top_module neuralcore_0} err]} {
    puts "Neuralcore module added"
}

# ============================================================
# CONNECT CLOCK
# ============================================================
puts "Connecting clock..."
if {[get_bd_pins zynq_ps/FCLK_CLK0] != ""} {
    connect_bd_net [get_bd_pins zynq_ps/FCLK_CLK0] [get_bd_pins neuralcore_0/clk]
}

# ============================================================
# CONNECT RESET
# ============================================================
puts "Connecting reset..."
if {[get_bd_pins zynq_ps/FCLK_RESET0_N] != ""} {
    connect_bd_net [get_bd_pins zynq_ps/FCLK_RESET0_N] [get_bd_pins neuralcore_0/rst_n]
}

# ============================================================
# SAVE BLOCK DESIGN
# ============================================================
puts "Saving block design..."
save_bd_design

# ============================================================
# GENERATE BITSTREAM
# ============================================================
puts "Generating bitstream..."

# Run synthesis
puts "Running synthesis..."
launch_runs synth_1 -jobs 4
wait_on_run synth_1

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
puts "- Output: $project_name.runs/impl_1/design_1.bit"

exit 0
