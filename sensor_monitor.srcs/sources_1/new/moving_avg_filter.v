// ============================================================================
// Module      : moving_avg_filter
// Type        : Sequential (clocked), synchronous active-high reset
// Language    : Verilog-2001 (synthesizable)
//
// Description :
//   Moving-average (boxcar) filter over the last TAPS = 2**LOG2_TAPS samples.
//   Real sensor signals carry noise; averaging before classification stops
//   single noisy samples from changing the alarm state.
//
//   Implementation (no multipliers, no dividers):
//     * A shift register holds the last TAPS samples.
//     * A running sum is updated with   sum_new = sum + newest - oldest
//       so only one adder/subtractor is needed regardless of TAPS.
//     * Division by TAPS is a right shift by LOG2_TAPS (TAPS is a power of 2).
//
//   Handshake:
//     sample_valid : 1-cycle strobe, "a new ADC sample is on sample_in".
//     avg_valid    : 1-cycle strobe one clock later, "avg_out has updated".
//   avg_out holds its value between samples.
//
//   After reset the history is all zeros, so the first TAPS-1 outputs are
//   biased low (warm-up). This is documented as a design limitation.
//
//   LOG2_TAPS = 0 gives TAPS = 1, i.e. the filter becomes a simple register
//   (useful to compare "filtered" vs "unfiltered" behaviour).
// ============================================================================
`timescale 1ns / 1ps

module moving_avg_filter #(
    parameter DATA_WIDTH = 8,
    parameter LOG2_TAPS  = 2            // 2 -> average of 4 samples
) (
    input  wire                  clk,
    input  wire                  rst,          // synchronous, active-high
    input  wire                  sample_valid, // new sample strobe
    input  wire [DATA_WIDTH-1:0] sample_in,
    output reg                   avg_valid,    // avg_out updated this cycle
    output reg  [DATA_WIDTH-1:0] avg_out
);

    localparam TAPS  = 1 << LOG2_TAPS;
    localparam ACC_W = DATA_WIDTH + LOG2_TAPS;   // sum of TAPS samples fits

    reg  [DATA_WIDTH-1:0] history [0:TAPS-1];    // history[0] = newest
    reg  [ACC_W-1:0]      acc;                   // sum of all history entries
    wire [ACC_W-1:0]      acc_next;
    integer i;

    // Running sum: add the incoming sample, drop the oldest one.
    // acc always >= history[TAPS-1], so the subtraction never underflows.
    assign acc_next = acc + sample_in - history[TAPS-1];

    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < TAPS; i = i + 1)
                history[i] <= {DATA_WIDTH{1'b0}};
            acc       <= {ACC_W{1'b0}};
            avg_out   <= {DATA_WIDTH{1'b0}};
            avg_valid <= 1'b0;
        end else begin
            avg_valid <= 1'b0;                      // default: strobe low
            if (sample_valid) begin
                for (i = TAPS - 1; i > 0; i = i - 1)
                    history[i] <= history[i-1];     // shift older
                history[0] <= sample_in;            // insert newest
                acc        <= acc_next;
                avg_out    <= acc_next[ACC_W-1:LOG2_TAPS];   // divide by TAPS
                avg_valid  <= 1'b1;
            end
        end
    end

endmodule
