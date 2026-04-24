# ============================================================
# CONFIGURATION
# ============================================================
set project_name "imp_kv260"
set part_number "xck26-sfvc784-2LV-c"
set top_module "neuralcore_axi"
set wrapper_file "neuralcore_axi.sv"
set logic_file "neuralcore.sv"

puts "=== IMP KV260 Automated Build (AXI Mode) ==="

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
create_project -force $project_name . -part $part_number
set_property ip_repo_paths "[pwd]/ip_repo" [current_project]
update_ip_catalog

# ============================================================
# STEP 3: BLOCK DESIGN SETUP
# ============================================================
puts "Creating block design..."
create_bd_design "system"

create_bd_cell -type ip -vlnv xilinx.com:ip:zynq_ultra_ps_e zynq_ps
apply_bd_automation -rule xilinx.com:bd_rule:zynq_ultra_ps_e -config {apply_board_preset "1"} [get_bd_cells zynq_ps]
create_bd_cell -type ip -vlnv user.org:user:neuralcore_axi:1.0 neuralcore_0

connect_bd_net [get_bd_pins zynq_ps/pl_clk0] [get_bd_pins neuralcore_0/s_axi_aclk]
connect_bd_net [get_bd_pins zynq_ps/pl_resetn0] [get_bd_pins neuralcore_0/s_axi_aresetn]

apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config { Master /zynq_ps/M_AXI_HPM0_LPD Clk_master {Auto} Clk_slave {Auto} Clk_xbar {Auto} Slave /neuralcore_0/s_axi } [get_bd_intf_pins neuralcore_0/s_axi]

set target_seg [get_bd_addr_segs -of_objects [get_bd_cells zynq_ps] -filter {NAME =~ "*neuralcore_0*"}]
set_property offset 0x80000000 $target_seg
set_property range 64K $target_seg

set_property synth_checkpoint_mode None [get_files system.bd]

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