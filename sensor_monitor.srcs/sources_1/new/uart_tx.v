// ============================================================================
// Module      : uart_tx
// Type        : Sequential FSM, synchronous active-high reset
// Language    : Verilog-2001 (synthesizable)
//
// Description :
//   UART transmitter, 8N1 format (1 start bit, 8 data bits LSB first,
//   no parity, 1 stop bit). The line idles high.
//
//   CLKS_PER_BIT = clock frequency / baud rate
//     100 MHz / 115200 baud = 868   (default)
//   Testbenches override it with a small value so simulation is fast.
//
//   Handshake:
//     tx_start : 1-cycle request; tx_data is captured when tx_start is seen
//                while idle. Requests while busy are ignored.
//     tx_busy  : high from the cycle after tx_start until the stop bit ends.
//   The tx output is registered (no glitches on the serial line).
// ============================================================================
`timescale 1ns / 1ps

module uart_tx #(
    parameter CLKS_PER_BIT = 868
) (
    input  wire       clk,
    input  wire       rst,        // synchronous, active-high
    input  wire       tx_start,
    input  wire [7:0] tx_data,
    output reg        tx,         // serial output, idle high
    output reg        tx_busy
);

    localparam [1:0] T_IDLE  = 2'd0;
    localparam [1:0] T_START = 2'd1;
    localparam [1:0] T_DATA  = 2'd2;
    localparam [1:0] T_STOP  = 2'd3;

    // counter wide enough for CLKS_PER_BIT up to 65535
    reg [15:0] clk_cnt;
    reg [2:0]  bit_idx;
    reg [7:0]  shift_reg;
    reg [1:0]  state;

    wire bit_done = (clk_cnt == CLKS_PER_BIT - 1);

    always @(posedge clk) begin
        if (rst) begin
            state     <= T_IDLE;
            tx        <= 1'b1;
            tx_busy   <= 1'b0;
            clk_cnt   <= 16'd0;
            bit_idx   <= 3'd0;
            shift_reg <= 8'd0;
        end else begin
            case (state)
                T_IDLE: begin
                    tx      <= 1'b1;
                    clk_cnt <= 16'd0;
                    bit_idx <= 3'd0;
                    if (tx_start) begin
                        shift_reg <= tx_data;
                        tx_busy   <= 1'b1;
                        state     <= T_START;
                    end
                end

                T_START: begin                       // start bit = 0
                    tx <= 1'b0;
                    if (bit_done) begin
                        clk_cnt <= 16'd0;
                        state   <= T_DATA;
                    end else
                        clk_cnt <= clk_cnt + 16'd1;
                end

                T_DATA: begin                        // 8 data bits, LSB first
                    tx <= shift_reg[0];
                    if (bit_done) begin
                        clk_cnt   <= 16'd0;
                        shift_reg <= shift_reg >> 1;
                        if (bit_idx == 3'd7)
                            state <= T_STOP;
                        else
                            bit_idx <= bit_idx + 3'd1;
                    end else
                        clk_cnt <= clk_cnt + 16'd1;
                end

                T_STOP: begin                        // stop bit = 1
                    tx <= 1'b1;
                    if (bit_done) begin
                        clk_cnt <= 16'd0;
                        tx_busy <= 1'b0;
                        state   <= T_IDLE;
                    end else
                        clk_cnt <= clk_cnt + 16'd1;
                end

                default: state <= T_IDLE;
            endcase
        end
    end

endmodule
