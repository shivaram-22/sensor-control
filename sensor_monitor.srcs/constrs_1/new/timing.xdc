## ============================================================================
## timing.xdc - constraints for SYNTHESIS / TIMING ANALYSIS only
## Project: FPGA-Based Intelligent Sensor Monitoring and Fault Detection System
##
## No board is used, so no pin locations (PACKAGE_PIN / IOSTANDARD) are set.
## The clock constraint lets Vivado report real timing (setup slack, WNS)
## after synthesis: Reports -> Timing -> Report Timing Summary.
## Do NOT generate a bitstream with this file (pins are unassigned).
## ============================================================================

## 100 MHz system clock (10 ns period) - matches CLKS_PER_BIT = 868 @ 115200 baud
create_clock -period 10.000 -name sys_clk [get_ports clk]
