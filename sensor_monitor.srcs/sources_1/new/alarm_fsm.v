// ============================================================================
// Module      : alarm_fsm
// Type        : Sequential Moore FSM, synchronous active-high reset
// Language    : Verilog-2001 (synthesizable)
//
// Description :
//   Turns the (filtered) sensor value into a CONFIRMED alarm state, the way
//   an industrial alarm panel behaves. Three features on top of the plain
//   threshold detector:
//
//   1. Hysteresis  - a state is entered at one threshold and left at a lower
//                    one, so a reading hovering around a threshold does not
//                    make the outputs flicker.
//                      WARNING : enter at >= WARN_ON  (60), leave at < WARN_OFF  (55)
//                      FAULT   : enter at >= FAULT_ON (80), clear at < FAULT_OFF (75)
//   2. Confirmation- a fault is declared only after CONFIRM_COUNT consecutive
//                    samples at or above FAULT_ON. Shorter bursts are
//                    rejected as spikes (state FAULT_PENDING -> back).
//   3. Latch + ack - a confirmed fault stays latched even if the reading
//                    drops. It is cleared only when the operator asserts
//                    ack AND the reading is below FAULT_OFF.
//
//   States (2-bit):
//     S_NORMAL        (0)  normal_led
//     S_WARNING       (1)  warning_led
//     S_FAULT_PENDING (2)  warning_led + fault_pending  (suspected fault)
//     S_FAULT         (3)  fault_led                    (confirmed, latched)
//
//   Transitions on a sample (value_valid = 1):
//     NORMAL   : v >= FAULT_ON -> PENDING (or FAULT if CONFIRM_COUNT = 1)
//                v >= WARN_ON  -> WARNING
//     WARNING  : v >= FAULT_ON -> PENDING (or FAULT if CONFIRM_COUNT = 1)
//                v <  WARN_OFF -> NORMAL
//     PENDING  : v >= FAULT_ON -> count; FAULT when CONFIRM_COUNT reached
//                v <  FAULT_ON -> spike rejected: WARNING (v >= WARN_OFF)
//                                                 or NORMAL (v < WARN_OFF)
//   Transition on any clock (operator action):
//     FAULT    : ack && v < FAULT_OFF -> WARNING (v >= WARN_OFF) or NORMAL
//
//   ack is level-sensitive: holding it high acts as "auto-clear" once the
//   reading is safe; a fault is still declared and counted first.
//
// Parameter constraints (designer must keep):
//   WARN_OFF <= WARN_ON < FAULT_OFF <= FAULT_ON,   1 <= CONFIRM_COUNT <= 255
// ============================================================================
`timescale 1ns / 1ps

module alarm_fsm #(
    parameter DATA_WIDTH    = 8,
    parameter WARN_ON       = 60,
    parameter WARN_OFF      = 55,
    parameter FAULT_ON      = 80,
    parameter FAULT_OFF     = 75,
    parameter CONFIRM_COUNT = 4
) (
    input  wire                  clk,
    input  wire                  rst,           // synchronous, active-high
    input  wire                  value_valid,   // new filtered sample strobe
    input  wire [DATA_WIDTH-1:0] value,         // filtered sensor value
    input  wire                  ack,           // operator acknowledge
    output wire [1:0]            alarm_state,
    output wire                  normal_led,
    output wire                  warning_led,
    output wire                  fault_led,     // CONFIRMED fault (latched)
    output wire                  fault_pending  // suspected, not yet confirmed
);

    localparam [1:0] S_NORMAL        = 2'd0;
    localparam [1:0] S_WARNING       = 2'd1;
    localparam [1:0] S_FAULT_PENDING = 2'd2;
    localparam [1:0] S_FAULT         = 2'd3;

    reg [1:0] state, next_state;
    reg [7:0] confirm_cnt, next_cnt;   // consecutive samples >= FAULT_ON

    // ---- Threshold comparators (unsigned) ---------------------------------
    wire at_fault_on    = (value >= FAULT_ON);
    wire below_fault_off= (value <  FAULT_OFF);
    wire at_warn_on     = (value >= WARN_ON);
    wire below_warn_off = (value <  WARN_OFF);

    // ---- State register (sequential, nonblocking) -------------------------
    always @(posedge clk) begin
        if (rst) begin
            state       <= S_NORMAL;
            confirm_cnt <= 8'd0;
        end else begin
            state       <= next_state;
            confirm_cnt <= next_cnt;
        end
    end

    // ---- Next-state logic (combinational, blocking) -----------------------
    always @(*) begin
        next_state = state;            // defaults: hold -> no latches
        next_cnt   = confirm_cnt;

        case (state)
            S_NORMAL, S_WARNING: begin
                if (value_valid) begin
                    if (at_fault_on) begin
                        if (CONFIRM_COUNT <= 1) begin
                            next_state = S_FAULT;
                            next_cnt   = 8'd0;
                        end else begin
                            next_state = S_FAULT_PENDING;
                            next_cnt   = 8'd1;          // first fault sample
                        end
                    end else if (state == S_NORMAL && at_warn_on) begin
                        next_state = S_WARNING;
                    end else if (state == S_WARNING && below_warn_off) begin
                        next_state = S_NORMAL;
                    end
                end
            end

            S_FAULT_PENDING: begin
                if (value_valid) begin
                    if (at_fault_on) begin
                        if (confirm_cnt >= CONFIRM_COUNT - 1) begin
                            next_state = S_FAULT;       // confirmed
                            next_cnt   = 8'd0;
                        end else begin
                            next_cnt   = confirm_cnt + 8'd1;
                        end
                    end else begin                      // spike rejected
                        next_cnt   = 8'd0;
                        next_state = below_warn_off ? S_NORMAL : S_WARNING;
                    end
                end
            end

            S_FAULT: begin                              // latched
                if (ack && below_fault_off)
                    next_state = below_warn_off ? S_NORMAL : S_WARNING;
            end

            default: begin                              // unreachable safety
                next_state = S_NORMAL;
                next_cnt   = 8'd0;
            end
        endcase
    end

    // ---- Moore outputs: decoded from the state register only --------------
    assign alarm_state   = state;
    assign normal_led    = (state == S_NORMAL);
    assign warning_led   = (state == S_WARNING) || (state == S_FAULT_PENDING);
    assign fault_led     = (state == S_FAULT);
    assign fault_pending = (state == S_FAULT_PENDING);

endmodule
