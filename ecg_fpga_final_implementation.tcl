# Set the reference directory to the script's location
set origin_dir "."

# Use origin directory path location variable, if specified in the tcl shell
if { [info exists ::origin_dir_loc] } {
  set origin_dir $::origin_dir_loc
}

# Set the project name
set _xil_proj_name_ "ecg_fpga_final_implementation"

# Use project name variable, if specified in the tcl shell
if { [info exists ::user_project_name] } {
  set _xil_proj_name_ $::user_project_name
}

variable script_file
set script_file "recreate_project.tcl"

# Help information for this script
proc print_help {} {
  variable script_file
  puts "\nDescription:"
  puts "Recreate a Vivado project from this script. The created project will be"
  puts "functionally equivalent to the original project for which this script was"
  puts "generated.\n"
  puts "Syntax:"
  puts "$script_file"
  puts "$script_file -tclargs \[--origin_dir <path>\]"
  puts "$script_file -tclargs \[--project_name <name>\]"
  puts "$script_file -tclargs \[--help\]\n"
  puts "Usage:"
  puts "Name                   Description"
  puts "-------------------------------------------------------------------------"
  puts "\[--origin_dir <path>\]  Determine source file paths wrt this path. Default"
  puts "                       origin_dir path value is \".\".\n"
  puts "\[--project_name <name>\] Create project with the specified name. Default"
  puts "                       name is the name of the project from where this"
  puts "                       script was generated.\n"
  puts "\[--help\]               Print help information for this script"
  puts "-------------------------------------------------------------------------\n"
  exit 0
}

if { $::argc > 0 } {
  for {set i 0} {$i < $::argc} {incr i} {
    set option [string trim [lindex $::argv $i]]
    switch -regexp -- $option {
      "--origin_dir"   { incr i; set origin_dir [lindex $::argv $i] }
      "--project_name" { incr i; set _xil_proj_name_ [lindex $::argv $i] }
      "--help"         { print_help }
      default {
        if { [regexp {^-} $option] } {
          puts "ERROR: Unknown option '$option' specified, please type '$script_file -tclargs --help' for usage info.\n"
          return 1
        }
      }
    }
  }
}

# Check that required source files exist
proc checkRequiredFiles { origin_dir } {
  set status true
  set files [list \
    "[file normalize "$origin_dir/src/fir_bandpass.vhd"]" \
    "[file normalize "$origin_dir/src/peak_detector.vhd"]" \
    "[file normalize "$origin_dir/src/tx_packetiser.vhd"]" \
    "[file normalize "$origin_dir/src/uart_tx.vhd"]" \
    "[file normalize "$origin_dir/src/top_ecg.vhd"]" \
    "[file normalize "$origin_dir/ip/xadc_wiz_0.xci"]" \
    "[file normalize "$origin_dir/constrs/CmodA7_ECG.xdc"]" \
  ]
  foreach ifile $files {
    if { ![file isfile $ifile] } {
      puts " Could not find local file $ifile "
      set status false
    }
  }
  return $status
}

# Validate files before proceeding
if { ![checkRequiredFiles $origin_dir] } {
  puts "ERROR: Not all required files found. Please check your repo structure."
  return
}

# Create project
create_project ${_xil_proj_name_} ./${_xil_proj_name_} -part xc7a35tcpg236-1

# Set the directory path for the new project
set proj_dir [get_property directory [current_project]]

# Set project properties
set obj [current_project]
set_property -name "default_lib" -value "xil_defaultlib" -objects $obj
set_property -name "enable_resource_estimation" -value "0" -objects $obj
set_property -name "enable_vhdl_2008" -value "1" -objects $obj
set_property -name "ip_cache_permissions" -value "disable" -objects $obj
set_property -name "ip_output_repo" -value "$proj_dir/${_xil_proj_name_}.cache/ip" -objects $obj
set_property -name "mem.enable_memory_map_generation" -value "1" -objects $obj
set_property -name "part" -value "xc7a35tcpg236-1" -objects $obj
set_property -name "revised_directory_structure" -value "1" -objects $obj
set_property -name "sim.central_dir" -value "$proj_dir/${_xil_proj_name_}.ip_user_files" -objects $obj
set_property -name "sim.ip.auto_export_scripts" -value "1" -objects $obj
set_property -name "simulator_language" -value "Mixed" -objects $obj
set_property -name "source_mgmt_mode" -value "DisplayOnly" -objects $obj

# Create 'sources_1' fileset (if not found)
if {[string equal [get_filesets -quiet sources_1] ""]} {
  create_fileset -srcset sources_1
}

# Import VHDL source files
set obj [get_filesets sources_1]
set files [list \
  [file normalize "${origin_dir}/src/fir_bandpass.vhd"] \
  [file normalize "${origin_dir}/src/peak_detector.vhd"] \
  [file normalize "${origin_dir}/src/tx_packetiser.vhd"] \
  [file normalize "${origin_dir}/src/uart_tx.vhd"] \
  [file normalize "${origin_dir}/src/top_ecg.vhd"] \
]
set imported_files [import_files -fileset sources_1 $files]

# Set file types for VHDL sources
foreach f {fir_bandpass.vhd peak_detector.vhd tx_packetiser.vhd uart_tx.vhd top_ecg.vhd} {
  set file_obj [get_files -of_objects [get_filesets sources_1] [list "*$f"]]
  set_property -name "file_type" -value "VHDL" -objects $file_obj
}

# Set 'sources_1' fileset properties
set obj [get_filesets sources_1]
set_property -name "dataflow_viewer_settings" -value "min_width=16" -objects $obj
set_property -name "top" -value "top_ecg" -objects $obj

# Import XADC IP
set files [list \
  [file normalize "${origin_dir}/ip/xadc_wiz_0.xci"] \
]
set imported_files [import_files -fileset sources_1 $files]

# Set IP file properties
set file "xadc_wiz_0/xadc_wiz_0.xci"
set file_obj [get_files -of_objects [get_filesets sources_1] [list "*$file"]]
set_property -name "generate_files_for_reference" -value "0" -objects $file_obj
set_property -name "registered_with_manager" -value "1" -objects $file_obj
if { ![get_property "is_locked" $file_obj] } {
  set_property -name "synth_checkpoint_mode" -value "Singular" -objects $file_obj
}

# Create 'constrs_1' fileset (if not found)
if {[string equal [get_filesets -quiet constrs_1] ""]} {
  create_fileset -constrset constrs_1
}

# Import constraints file
set obj [get_filesets constrs_1]
set file "[file normalize "$origin_dir/constrs/CmodA7_ECG.xdc"]"
set file_imported [import_files -fileset constrs_1 [list $file]]
set file_obj [get_files -of_objects [get_filesets constrs_1] [list "*CmodA7_ECG.xdc"]]
set_property -name "file_type" -value "XDC" -objects $file_obj

# Set 'constrs_1' fileset properties
set obj [get_filesets constrs_1]
set_property -name "target_constrs_file" -value "[get_files [list "*CmodA7_ECG.xdc"]]" -objects $obj
set_property -name "target_part" -value "xc7a35tcpg236-1" -objects $obj
set_property -name "target_ucf" -value "[get_files [list "*CmodA7_ECG.xdc"]]" -objects $obj

# Create 'sim_1' fileset (if not found)
if {[string equal [get_filesets -quiet sim_1] ""]} {
  create_fileset -simset sim_1
}

# Set 'sim_1' fileset properties
set obj [get_filesets sim_1]
set_property -name "top" -value "tb_top_ecg" -objects $obj
set_property -name "top_auto_set" -value "0" -objects $obj
set_property -name "top_lib" -value "xil_defaultlib" -objects $obj

set idrFlowPropertiesConstraints ""
catch {
  set idrFlowPropertiesConstraints [get_param runs.disableIDRFlowPropertyConstraints]
  set_param runs.disableIDRFlowPropertyConstraints 1
}

# Create 'synth_1' run (if not found)
if {[string equal [get_runs -quiet synth_1] ""]} {
  create_run -name synth_1 -part xc7a35tcpg236-1 -flow {Vivado Synthesis 2024} -strategy "Vivado Synthesis Defaults" -report_strategy {No Reports} -constrset constrs_1
} else {
  set_property strategy "Vivado Synthesis Defaults" [get_runs synth_1]
  set_property flow "Vivado Synthesis 2024" [get_runs synth_1]
}
set obj [get_runs synth_1]
set_property set_report_strategy_name 1 $obj
set_property report_strategy {Vivado Synthesis Default Reports} $obj
set_property set_report_strategy_name 0 $obj

if { [string equal [get_report_configs -of_objects [get_runs synth_1] synth_1_synth_report_utilization_0] ""] } {
  create_report_config -report_name synth_1_synth_report_utilization_0 -report_type report_utilization:1.0 -steps synth_design -runs synth_1
}

set obj [get_runs synth_1]
set_property -name "part" -value "xc7a35tcpg236-1" -objects $obj
set_property -name "auto_incremental_checkpoint" -value "1" -objects $obj
set_property -name "strategy" -value "Vivado Synthesis Defaults" -objects $obj

# set the current synth run
current_run -synthesis [get_runs synth_1]

# Create 'impl_1' run (if not found)
if {[string equal [get_runs -quiet impl_1] ""]} {
  create_run -name impl_1 -part xc7a35tcpg236-1 -flow {Vivado Implementation 2024} -strategy "Vivado Implementation Defaults" -report_strategy {No Reports} -constrset constrs_1 -parent_run synth_1
} else {
  set_property strategy "Vivado Implementation Defaults" [get_runs impl_1]
  set_property flow "Vivado Implementation 2024" [get_runs impl_1]
}
set obj [get_runs impl_1]
set_property set_report_strategy_name 1 $obj
set_property report_strategy {Vivado Implementation Default Reports} $obj
set_property set_report_strategy_name 0 $obj

# Create implementation report configs
foreach {rname rtype rstep} {
  impl_1_init_report_timing_summary_0        report_timing_summary:1.0   init_design
  impl_1_opt_report_drc_0                    report_drc:1.0              opt_design
  impl_1_opt_report_timing_summary_0         report_timing_summary:1.0   opt_design
  impl_1_power_opt_report_timing_summary_0   report_timing_summary:1.0   power_opt_design
  impl_1_place_report_io_0                   report_io:1.0               place_design
  impl_1_place_report_utilization_0          report_utilization:1.0      place_design
  impl_1_place_report_control_sets_0         report_control_sets:1.0     place_design
  impl_1_place_report_incremental_reuse_0    report_incremental_reuse:1.0 place_design
  impl_1_place_report_incremental_reuse_1    report_incremental_reuse:1.0 place_design
  impl_1_place_report_timing_summary_0       report_timing_summary:1.0   place_design
  impl_1_post_place_power_opt_report_timing_summary_0 report_timing_summary:1.0 post_place_power_opt_design
  impl_1_phys_opt_report_timing_summary_0    report_timing_summary:1.0   phys_opt_design
  impl_1_route_report_drc_0                  report_drc:1.0              route_design
  impl_1_route_report_methodology_0          report_methodology:1.0      route_design
  impl_1_route_report_power_0               report_power:1.0            route_design
  impl_1_route_report_route_status_0         report_route_status:1.0     route_design
  impl_1_route_report_timing_summary_0       report_timing_summary:1.0   route_design
  impl_1_route_report_incremental_reuse_0    report_incremental_reuse:1.0 route_design
  impl_1_route_report_clock_utilization_0    report_clock_utilization:1.0 route_design
  impl_1_route_report_bus_skew_0             report_bus_skew:1.1         route_design
  impl_1_post_route_phys_opt_report_timing_summary_0 report_timing_summary:1.0 post_route_phys_opt_design
  impl_1_post_route_phys_opt_report_bus_skew_0 report_bus_skew:1.1       post_route_phys_opt_design
} {
  if { [string equal [get_report_configs -of_objects [get_runs impl_1] $rname] ""] } {
    create_report_config -report_name $rname -report_type $rtype -steps $rstep -runs impl_1
  }
}

# Disable certain reports
foreach rname {
  impl_1_init_report_timing_summary_0
  impl_1_opt_report_timing_summary_0
  impl_1_power_opt_report_timing_summary_0
  impl_1_place_report_incremental_reuse_0
  impl_1_place_report_incremental_reuse_1
  impl_1_place_report_timing_summary_0
  impl_1_post_place_power_opt_report_timing_summary_0
  impl_1_phys_opt_report_timing_summary_0
} {
  set obj [get_report_configs -of_objects [get_runs impl_1] $rname]
  if { $obj != "" } {
    set_property -name "is_enabled" -value "0" -objects $obj
  }
}

# Set timing summary report options
foreach rname {
  impl_1_init_report_timing_summary_0
  impl_1_opt_report_timing_summary_0
  impl_1_power_opt_report_timing_summary_0
  impl_1_place_report_timing_summary_0
  impl_1_post_place_power_opt_report_timing_summary_0
  impl_1_phys_opt_report_timing_summary_0
  impl_1_route_report_timing_summary_0
  impl_1_post_route_phys_opt_report_timing_summary_0
} {
  set obj [get_report_configs -of_objects [get_runs impl_1] $rname]
  if { $obj != "" } {
    set_property -name "options.max_paths" -value "10" -objects $obj
    set_property -name "options.report_unconstrained" -value "1" -objects $obj
  }
}

# Set control_sets verbose
set obj [get_report_configs -of_objects [get_runs impl_1] impl_1_place_report_control_sets_0]
if { $obj != "" } {
  set_property -name "options.verbose" -value "1" -objects $obj
}

# Set bus_skew warn_on_violation
foreach rname {impl_1_route_report_bus_skew_0 impl_1_post_route_phys_opt_report_bus_skew_0} {
  set obj [get_report_configs -of_objects [get_runs impl_1] $rname]
  if { $obj != "" } {
    set_property -name "options.warn_on_violation" -value "1" -objects $obj
  }
}

# Set post_route_phys_opt timing summary warn_on_violation
set obj [get_report_configs -of_objects [get_runs impl_1] impl_1_post_route_phys_opt_report_timing_summary_0]
if { $obj != "" } {
  set_property -name "options.warn_on_violation" -value "1" -objects $obj
}

set obj [get_runs impl_1]
set_property -name "part" -value "xc7a35tcpg236-1" -objects $obj
set_property -name "strategy" -value "Vivado Implementation Defaults" -objects $obj
set_property -name "steps.write_bitstream.args.readback_file" -value "0" -objects $obj
set_property -name "steps.write_bitstream.args.verbose" -value "0" -objects $obj

# set the current impl run
current_run -implementation [get_runs impl_1]
catch {
  if { $idrFlowPropertiesConstraints != {} } {
    set_param runs.disableIDRFlowPropertyConstraints $idrFlowPropertiesConstraints
  }
}

# Generate IP output products
generate_target all [get_ips]

puts "INFO: Project created: ${_xil_proj_name_}"
puts "INFO: To synthesize, run: launch_runs synth_1 -jobs 4"
puts "INFO: To implement,  run: launch_runs impl_1 -to_step write_bitstream -jobs 4"