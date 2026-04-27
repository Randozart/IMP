# ============================================================
# CONFIGURATION
# ============================================================
set project_name "imp_kv260"
set part_number "xck26-sfvc784-2LV-c"
set board_part "xilinx.com:kv260_som:part0:1.4"
set top_module "neuralcore_axi"
set wrapper_file "neuralcore_axi.sv"
set logic_file "neuralcore.sv"

puts "=== IMP KV260 Automated Build ==="

# Clean up any failed runs
file delete -force $project_name
file delete -force ./ip_repo
file delete -force ./ip_packager_proj

# ============================================================
# STEP 1: PACKAGE WRAPPER + LOGIC AS IP
# ============================================================
puts "Packaging AXI Wrapper and Logic as IP..."
create_project -force ip_packager_proj ./ip_packager_proj -part $part_number
add_files [list $wrapper_file $logic_file]
set_property top $top_module [current_fileset]
update_compile_order -fileset sources_1

ipx::package_project -root_dir ./ip_repo -vendor user.org -library user -taxonomy /UserIP -import_files
set core [ipx::current_core]
ipx::save_core $core
close_project

# ============================================================
# STEP 2: CREATE MAIN PROJECT
# ============================================================
puts "Creating main project..."
create_project -force $project_name . 
set_property board_part $board_part [current_project]

# MANDATORY FOR KRIA: Link the SOM module to the Vision Carrier Card
set_property board_connections {som240_1_connector xilinx.com:kv260_carrier:som240_1_connector:1.3} [current_project]

set_property ip_repo_paths "[pwd]/ip_repo" [current_project]
update_ip_catalog

# ============================================================
# STEP 3: BLOCK DESIGN SETUP
# ============================================================
puts "Creating block design..."
create_bd_design "system"

create_bd_cell -type ip -vlnv xilinx.com:ip:zynq_ultra_ps_e zynq_ps

# 1. Apply Board Presets
apply_bd_automation -rule xilinx.com:bd_rule:zynq_ultra_ps_e -config {apply_board_preset "1"} [get_bd_cells zynq_ps]

# 2. THE FIX: Explicitly disable the unused "High Power" gates and enable your "Low Power" gate
set_property -dict [list \
    CONFIG.PSU__USE__M_AXI_GP0 {0} \
    CONFIG.PSU__USE__M_AXI_GP1 {0} \
    CONFIG.PSU__USE__M_AXI_GP2 {1} \
] [get_bd_cells zynq_ps]

# 3. Add Neuralcore
create_bd_cell -type ip -vlnv user.org:user:neuralcore_axi:1.0 neuralcore_0

# 4. Connect Clock and Reset
connect_bd_net [get_bd_pins zynq_ps/pl_clk0] [get_bd_pins neuralcore_0/s_axi_aclk]
connect_bd_net [get_bd_pins zynq_ps/pl_resetn0] [get_bd_pins neuralcore_0/s_axi_aresetn]

# 5. Automate AXI Connection
apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config { Master /zynq_ps/M_AXI_HPM0_LPD Clk_master {Auto} Clk_slave {Auto} Clk_xbar {Auto} Slave /neuralcore_0/s_axi } [get_bd_intf_pins neuralcore_0/s_axi]

# 6. Set Address (The Situs)
set target_seg [get_bd_addr_segs -of_objects [get_bd_cells zynq_ps] -filter {NAME =~ "*neuralcore_0*"}]
set_property offset 0x80000000 $target_seg
set_property range 64K $target_seg

# 7. Final Validation Rite (Ensures all pins are Moored)
validate_bd_design
save_bd_design

# 8. Force Global Synthesis for RAM safety
set_property synth_checkpoint_mode None [get_files system.bd]

# 9. Create Wrapper
set wrapper_path [make_wrapper -files [get_files system.bd] -top]
add_files -norecurse $wrapper_path
set_property top system_wrapper [current_fileset]

# ============================================================
# STEP 4: BUILD BITSTREAM
# ============================================================
puts "Running synthesis and implementation (15-30 mins)..."
generate_target all [get_files system.bd]
export_ip_user_files -of_objects [get_files system.bd] -no_script -force
launch_runs impl_1 -to_step write_bitstream -jobs 1
wait_on_run impl_1

if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    puts "ERROR: Build failed. Check the logs."
    exit 1
}

puts "=== SUCCESS ==="
puts "Bitstream generated at: $project_name.runs/impl_1/system_wrapper.bit"
exit 0