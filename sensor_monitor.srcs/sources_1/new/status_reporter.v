// ============================================================================
// Module      : status_reporter
// Type        : Sequential FSM, synchronous active-high reset
// Language    : Verilog-2001 (synthesizable)
//
// Description :
//   The "IoT uplink" of the monitor. Whenever the alarm state changes, it
//   sends a 3-byte status packet through uart_tx, e.g. to a gateway
//   microcontroller that forwards it to the cloud:
//
//       byte 0 : 0xA0 | alarm_state   (0xA0 NORMAL, 0xA1 WARNING,
//                                      0xA2 FAULT_PENDING, 0xA3 FAULT)
//       byte 1 : filtered sensor value at the time of the change
//       byte 2 : fault event count at the time of the change
//
//   Snapshot timing: the change is detected one clock after the state
//   register updates, and the snapshot is taken one clock later, so the
//   fault counter (which updates one clock after the state) is included.
//
//   If the state changes again while a packet is being sent, the reporter
//   sends the LATEST state after the current packet (intermediate states
//   may be merged). Nothing is queued, so no FIFO is needed.
// ============================================================================
`timescale 1ns / 1ps

module status_reporter (
    input  wire       clk,
    input  wire       rst,            // synchronous, active-high
    input  wire [1:0] alarm_state,
    input  wire [7:0] value,
    input  wire [7:0] fault_count,
    input  wire       tx_busy,
    output reg        tx_start,
    output reg  [7:0] tx_data
);

    localparam [2:0] R_IDLE    = 3'd0;
    localparam [2:0] R_SNAP    = 3'd1;
    localparam [2:0] R_LOAD    = 3'd2;
    localparam [2:0] R_WAIT_HI = 3'd3;   // wait for uart_tx to accept
    localparam [2:0] R_WAIT_LO = 3'd4;   // wait for byte to finish

    localparam [3:0] STATUS_TAG = 4'hA;

    reg [2:0] r_state;
    reg [1:0] last_state;                // last state that was reported
    reg [1:0] byte_idx;
    reg [1:0] snap_state;
    reg [7:0] snap_value, snap_count;

    always @(posedge clk) begin
        if (rst) begin
            r_state    <= R_IDLE;
            last_state <= 2'd0;          // FSM also resets to NORMAL (0)
            byte_idx   <= 2'd0;
            snap_state <= 2'd0;
            snap_value <= 8'd0;
            snap_count <= 8'd0;
            tx_start   <= 1'b0;
            tx_data    <= 8'd0;
        end else begin
            case (r_state)
                R_IDLE: begin
                    tx_start <= 1'b0;
                    if (alarm_state != last_state)
                        r_state <= R_SNAP;
                end

                R_SNAP: begin
                    snap_state <= alarm_state;
                    snap_value <= value;
                    snap_count <= fault_count;
                    last_state <= alarm_state;
                    byte_idx   <= 2'd0;
                    r_state    <= R_LOAD;
                end

                R_LOAD: begin
                    case (byte_idx)
                        2'd0:    tx_data <= {STATUS_TAG, 2'b00, snap_state};
                        2'd1:    tx_data <= snap_value;
                        default: tx_data <= snap_count;
                    endcase
                    tx_start <= 1'b1;
                    r_state  <= R_WAIT_HI;
                end

                R_WAIT_HI: begin
                    tx_start <= 1'b0;            // 1-cycle start pulse
                    if (tx_busy)
                        r_state <= R_WAIT_LO;
                end

                R_WAIT_LO: begin
                    if (!tx_busy) begin
                        if (byte_idx == 2'd2)
                            r_state <= R_IDLE;   // packet complete
                        else begin
                            byte_idx <= byte_idx + 2'd1;
                            r_state  <= R_LOAD;
                        end
                    end
                end

                default: r_state <= R_IDLE;
            endcase
        end
    end

endmodule
