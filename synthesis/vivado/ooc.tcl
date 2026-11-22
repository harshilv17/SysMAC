# Vivado out-of-context synthesis + implementation for SysMAC.
#
# UNTESTED in this repository so far: written from AMD's documented flow
# (UG905, UG903, UG835). The first person to run it should commit the
# reports and fix anything Vivado complains about.
#
# Run from the repository root, with Vivado 2025.2 (the last release that
# needs no licence file):
#   vivado -mode batch -source synthesis/vivado/ooc.tcl -tclargs systolic_accelerator_top 8.0
#   vivado -mode batch -source synthesis/vivado/ooc.tcl -tclargs seq_matmul 8.0
#
# Arguments: top module, clock period in ns (default 8.0), part (default
# xc7a35tcpg236-1, the Basys 3 chip).
#
# Why out-of-context: the top has 436 port bits; an xc7a35t has 106 user I/O
# in cpg236 and 210 in csg324, so a normal pinned implementation cannot be
# placed. Out-of-context mode inserts no I/O buffers and measures the core
# alone. Port-to-register paths are not timed (see the unconstrained section
# of timing.rpt); register-to-register paths, which include the PE
# multiply-add, are.

set top    [expr {[llength $argv] > 0 ? [lindex $argv 0] : "systolic_accelerator_top"}]
set period [expr {[llength $argv] > 1 ? [lindex $argv 1] : 8.0}]
set part   [expr {[llength $argv] > 2 ? [lindex $argv 2] : "xc7a35tcpg236-1"}]

set sys_files {
    rtl/systolic_controller.v rtl/input_buffer.v rtl/input_scheduler.v
    rtl/processing_element.v rtl/systolic_array.v rtl/output_registers.v
    rtl/systolic_accelerator_top.v
}
set files [expr {$top eq "seq_matmul" ? {rtl/seq_matmul.v} : $sys_files}]

set out synthesis/vivado/$top
file mkdir $out

# Clock constraint, written fresh for this period.
set xdc $out/ooc.xdc
set fh [open $xdc w]
puts $fh "create_clock -name clk -period $period \[get_ports clk\]"
close $fh

read_verilog $files
read_xdc -mode out_of_context $xdc

synth_design -top $top -part $part -mode out_of_context
report_utilization -file $out/utilization_synth.rpt

opt_design
place_design
phys_opt_design
route_design

report_utilization             -file $out/utilization.rpt
report_utilization -hierarchical -file $out/utilization_hier.rpt
report_timing_summary -report_unconstrained -max_paths 10 -file $out/timing.rpt
report_power                   -file $out/power.rpt
report_drc                     -file $out/drc.rpt

# Fmax from the worst register-to-register setup slack: Fmax = 1 / (T - WNS).
set path [get_timing_paths -setup -max_paths 1 -nworst 1]
set wns  [get_property SLACK $path]
set fmax [expr {1000.0 / ($period - $wns)}]
set fh [open $out/fmax.txt w]
puts $fh "vivado  [version -short]"
puts $fh "part    $part"
puts $fh "top     $top"
puts $fh "period  $period ns"
puts $fh "WNS     $wns ns"
puts $fh [format "Fmax    %.1f MHz  (1000 / (period - WNS))" $fmax]
puts $fh "worst path: [get_property STARTPOINT_PIN $path] -> [get_property ENDPOINT_PIN $path]"
close $fh
puts "wrote reports to $out"
