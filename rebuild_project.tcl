# ============================================================================
# rebuild_project.tcl  -  FALLBACK ONLY
# Use this only if sensor_monitor.xpr does not open in your Vivado version.
# Vivado Tcl Console:
#     cd D:/path/to/sensor_monitor
#     source rebuild_project.tcl
# Creates ./rebuilt/sensor_monitor_rebuilt.xpr from the files in
# sensor_monitor.srcs (copied into the new project).
# ============================================================================
set PART xc7a35tcpg236-1
set HERE [file normalize [file dirname [info script]]]
set S    [file join $HERE sensor_monitor.srcs]

create_project sensor_monitor_rebuilt [file join $HERE rebuilt] -part $PART -force
import_files -fileset sources_1 [glob [file join $S sources_1 new *.v]]
set_property top sensor_monitor_top [get_filesets sources_1]
import_files -fileset constrs_1 [file join $S constrs_1 new timing.xdc]
import_files -fileset sim_1 [glob [file join $S sim_1 new *.v]]
import_files -fileset sim_1 [glob [file join $S sim_1 new *.mem]]
set_property top tb_sensor_monitor_top [get_filesets sim_1]
set_property top_lib xil_defaultlib [get_filesets sim_1]
set_property -name {xsim.simulate.runtime} -value {-all} -objects [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
puts "Rebuilt project ready: Run Simulation -> Run Behavioral Simulation"
