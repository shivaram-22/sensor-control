// ============================================================================
// Module      : sensor_fault_detector
// Project     : FPGA-Based Intelligent Sensor Monitoring and Fault Detection
//               System Using Verilog HDL for Industrial IoT Applications
// Type        : Combinational (no clock, no state)
// Language    : Verilog-2001 (synthesizable)
//
// Description :
//   Classifies an unsigned sensor reading into exactly one of three states
//   using two parameterized thresholds:
//
//       sensor_in <  WARN_THRESHOLD                     -> NORMAL
//       WARN_THRESHOLD <= sensor_in < FAULT_THRESHOLD   -> WARNING
//       sensor_in >= FAULT_THRESHOLD                    -> FAULT
//
//   With the default parameters (8-bit, 60, 80):
//       0  .. 59   -> normal_led  = 1
//       60 .. 79   -> warning_led = 1
//       80 .. 255  -> fault_led   = 1
//
// Design rules followed:
//   * One-hot outputs: exactly one LED is high for every valid input.
//   * Default assignments at the top of the always block -> no latches.
//   * Priority if-else checks the highest severity (FAULT) first, so the
//     boundaries 60 and 80 fall into the correct, more severe state.
//
// Parameter constraint (not enforced in hardware - the designer must keep it):
//   0 < WARN_THRESHOLD < FAULT_THRESHOLD <= 2**DATA_WIDTH - 1
// ============================================================================
`timescale 1ns / 1ps

module sensor_fault_detector #(
    parameter DATA_WIDTH      = 8,   // width of the sensor reading
    parameter WARN_THRESHOLD  = 60,  // first value classified as WARNING
    parameter FAULT_THRESHOLD = 80   // first value classified as FAULT
) (
    input  wire [DATA_WIDTH-1:0] sensor_in,    // unsigned sensor reading
    output reg                   normal_led,   // 1 = reading is NORMAL
    output reg                   warning_led,  // 1 = reading is WARNING
    output reg                   fault_led     // 1 = reading is FAULT
);

    // always @(*) : re-evaluate whenever ANY signal read inside the block
    // changes. This models pure combinational logic and avoids incomplete
    // sensitivity lists (a common cause of simulation/synthesis mismatch).
    always @(*) begin
        // ---- Default assignments --------------------------------------
        // Every output gets a value on every path through the block, so the
        // synthesizer never needs to "remember" an old value -> no latches.
        normal_led  = 1'b0;
        warning_led = 1'b0;
        fault_led   = 1'b0;

        // ---- Priority classification (most severe first) -----------------
        // '>=' on unsigned operands is an unsigned magnitude comparator.
        if (sensor_in >= FAULT_THRESHOLD) begin
            fault_led   = 1'b1;          // 80 .. 255
        end else if (sensor_in >= WARN_THRESHOLD) begin
            warning_led = 1'b1;          // 60 .. 79
        end else begin
            normal_led  = 1'b1;          // 0 .. 59
        end
    end

endmodule
