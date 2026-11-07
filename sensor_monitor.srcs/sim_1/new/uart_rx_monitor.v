// ============================================================================
// Module      : uart_rx_monitor   (SIMULATION ONLY - behavioural model)
// Language    : Verilog-2001
//
// Description :
//   Testbench helper that decodes an 8N1 serial line, like the gateway
//   microcontroller would. Received bytes are stored in rx_mem[] and
//   counted in rx_count. A start bit that is not low at mid-bit, or a stop
//   bit that is not high, increments frame_errors.
//   Testbenches read rx_mem / rx_count / frame_errors hierarchically.
// ============================================================================
`timescale 1ns / 1ps

module uart_rx_monitor #(
    parameter CLKS_PER_BIT = 868
) (
    input wire clk,
    input wire enable,     // ignore the line until reset is done
    input wire rx
);

    reg [7:0] rx_mem [0:255];
    integer   rx_count;
    integer   frame_errors;
    reg [7:0] shift;
    integer   b;

    initial begin
        rx_count     = 0;
        frame_errors = 0;
    end

    always begin
        @(negedge rx);
        if (enable) begin
            repeat (CLKS_PER_BIT / 2) @(posedge clk);    // middle of start bit
            if (rx !== 1'b0)
                frame_errors = frame_errors + 1;
            for (b = 0; b < 8; b = b + 1) begin
                repeat (CLKS_PER_BIT) @(posedge clk);     // middle of data bit
                shift[b] = rx;                            // LSB first
            end
            repeat (CLKS_PER_BIT) @(posedge clk);         // middle of stop bit
            if (rx !== 1'b1)
                frame_errors = frame_errors + 1;
            rx_mem[rx_count[7:0]] = shift;
            rx_count = rx_count + 1;
        end
    end

endmodule
