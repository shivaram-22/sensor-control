# FPGA Sensor Monitor

An FPGA-based sensor monitoring and fault-detection design written in
Verilog-2001. The project is set up in AMD/Xilinx Vivado and includes RTL,
simulation testbenches, sample input data, and a timing constraint.

## Features

- Classifies sensor readings as normal, warning, or fault.
- A configurable moving-average filter reduces the effect of noisy samples.
- A hysteretic alarm state machine confirms faults and supports acknowledgement.
- Counts confirmed fault events and indicates when the counter saturates.
- Sends status data over a UART transmitter.

Default settings use an 8-bit sensor value, warning thresholds of 60/55,
fault thresholds of 80/75, a four-sample moving average, a 100 MHz clock, and
115200-baud UART. These are configurable through the top-level module
parameters.

## Requirements

- AMD/Xilinx Vivado (the project was generated with Vivado 2026.1).
- The project targets `xc7a35tcpg236-1`.

The project is intended for RTL simulation and design analysis. It has no
board pin assignments, so do not generate a bitstream without adding the
appropriate constraints for your hardware.

## Open and simulate

1. Clone or download this repository.
2. In Vivado, choose **File > Project > Open** and open `sensor_monitor.xpr`.
3. In **Flow Navigator**, choose **Run Simulation > Run Behavioral Simulation**.
4. Run the simulation to completion. The top-level testbench reports
   `RESULT : ALL TESTS PASSED` when its checks succeed.

The project can also be opened from the Vivado Tcl Console by running
`source rebuild_project.tcl` from this directory. This fallback creates a
reconstructed project under `rebuilt/`.

For additional testbenches and analysis steps, see [HOW_TO_OPEN.txt](HOW_TO_OPEN.txt).

## Repository layout

```text
sensor_monitor.xpr                         Vivado project
rebuild_project.tcl                         Optional project reconstruction script
sensor_monitor.srcs/
  sources_1/new/                            Synthesizable RTL
  sim_1/new/                                Testbenches and simulation vectors
  constrs_1/new/timing.xdc                  Timing constraint
```

Generated Vivado caches, simulation runs, and build outputs are excluded from
version control; the source files and test data required to recreate the
project are included.
