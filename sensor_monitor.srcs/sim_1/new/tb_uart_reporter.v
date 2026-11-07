// ============================================================================
// Testbench   : tb_uart_reporter
// DUTs        : uart_tx (driven directly) and status_reporter + uart_tx
// Language    : Verilog-2001, simulation only
// Needs       : tb/uart_rx_monitor.v
//
//   U1 bytes 0x00, 0xFF, 0x55, 0xA3, 0x81 are received correctly
//   U2 every bit lasts exactly CLKS_PER_BIT clocks (edge timing of 0x55)
//   U3 a start request while busy is ignored
//   U4 no state change -> no packet; line idles high
//   U5 state change -> packet {0xA0|state, value, count}
//   U6 counter updated one clock after the state is included in the packet
//   U7 two changes during a packet are merged into one packet (latest state)
//   All frames: no framing errors
// ============================================================================
`timescale 1ns / 1ps

module tb_uart_reporter;

    localparam CLK_PERIOD = 10;
    localparam CPB        = 8;           // clocks per bit (fast simulation)

    reg        clk, rst;
    // direct UART
    reg        d_start;
    reg  [7:0] d_data;
    wire       d_tx, d_busy;
    // reporter chain
    reg  [1:0] alarm_state;
    reg  [7:0] value, fault_count;
    wire       r_start, r_tx, r_busy;
    wire [7:0] r_data;
    reg        rx_enable;

    integer test_count, fail_count, i, base;
    integer edge_count;
    real    edge_time [0:15];
    reg     measure;

    uart_tx #(.CLKS_PER_BIT(CPB)) uart_direct (
        .clk(clk), .rst(rst), .tx_start(d_start), .tx_data(d_data),
        .tx(d_tx), .tx_busy(d_busy));
    uart_rx_monitor #(.CLKS_PER_BIT(CPB)) mon_direct (
        .clk(clk), .enable(rx_enable), .rx(d_tx));

    status_reporter reporter (
        .clk(clk), .rst(rst), .alarm_state(alarm_state), .value(value),
        .fault_count(fault_count), .tx_busy(r_busy),
        .tx_start(r_start), .tx_data(r_data));
    uart_tx #(.CLKS_PER_BIT(CPB)) uart_rep (
        .clk(clk), .rst(rst), .tx_start(r_start), .tx_data(r_data),
        .tx(r_tx), .tx_busy(r_busy));
    uart_rx_monitor #(.CLKS_PER_BIT(CPB)) mon_rep (
        .clk(clk), .enable(rx_enable), .rx(r_tx));

    initial clk = 1'b0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // record edge times on the direct line (for U2)
    always @(d_tx) if (measure && edge_count < 16) begin
        edge_time[edge_count] = $realtime;
        edge_count = edge_count + 1;
    end

    // ------------------------------------------------------------------
    task check;
        input [8*52:1] label;
        input integer  actual;
        input integer  expected;
        reg   [7:0]    a8, e8;
        begin
            a8 = actual; e8 = expected;
            test_count = test_count + 1;
            if (actual !== expected) begin
                fail_count = fail_count + 1;
                $display("FAIL  %0s : got %0d (0x%h), expected %0d (0x%h)",
                         label, actual, a8, expected, e8);
            end else
                $display("PASS  %0s = %0d (0x%h)", label, actual, a8);
        end
    endtask

    task send_direct;
        input [7:0] b;
        begin
            @(negedge clk); d_data = b; d_start = 1'b1;
            @(negedge clk); d_start = 1'b0;
            wait (d_busy == 1'b0);
            @(negedge clk);
        end
    endtask

    // wait until the reporter path has been idle for a while
    task wait_reporter_idle;
        begin
            repeat (2) @(negedge clk);
            wait (reporter.r_state == 3'd0 && !r_busy);
            repeat (CPB * 2) @(negedge clk);
        end
    endtask

    // ------------------------------------------------------------------
    initial begin
        $timeformat(-9, 0, " ns", 0);
        test_count = 0; fail_count = 0; edge_count = 0; measure = 1'b0;
        rst = 1'b1; rx_enable = 1'b0;
        d_start = 1'b0; d_data = 8'h00;
        alarm_state = 2'd0; value = 8'd40; fault_count = 8'd0;

        $display("============================================================");
        $display(" tb_uart_reporter : 8N1, CLKS_PER_BIT = %0d", CPB);
        $display("============================================================");
        repeat (3) @(negedge clk);
        rst = 1'b0; rx_enable = 1'b1;
        repeat (3) @(negedge clk);

        $display("--- U1: direct bytes ---");
        send_direct(8'h00);
        send_direct(8'hFF);
        measure = 1'b1; send_direct(8'h55); measure = 1'b0;
        send_direct(8'hA3);
        send_direct(8'h81);
        repeat (CPB) @(negedge clk);
        check("U1 bytes received", mon_direct.rx_count, 5);
        check("U1 byte 0", mon_direct.rx_mem[0], 8'h00);
        check("U1 byte 1", mon_direct.rx_mem[1], 8'hFF);
        check("U1 byte 2", mon_direct.rx_mem[2], 8'h55);
        check("U1 byte 3", mon_direct.rx_mem[3], 8'hA3);
        check("U1 byte 4", mon_direct.rx_mem[4], 8'h81);

        $display("--- U2: bit timing of 0x55 (alternating bits) ---");
        // start(0) 1 0 1 0 1 0 1 0 stop(1): 10 edges, 9 intervals of 1 bit
        check("U2 edges seen in 0x55 frame", edge_count, 10);
        base = 0;
        for (i = 1; i < 10; i = i + 1)
            if (edge_time[i] - edge_time[i-1] != CPB * CLK_PERIOD) base = base + 1;
        check("U2 bit intervals != CPB clocks", base, 0);

        $display("--- U3: request while busy is ignored ---");
        @(negedge clk); d_data = 8'h12; d_start = 1'b1;
        @(negedge clk); d_start = 1'b0;
        repeat (CPB * 3) @(negedge clk);
        d_data = 8'h34; d_start = 1'b1;          // mid-frame request
        @(negedge clk); d_start = 1'b0;
        wait (d_busy == 1'b0);
        repeat (CPB * 12) @(negedge clk);
        check("U3 bytes received (only one)", mon_direct.rx_count, 6);
        check("U3 received byte", mon_direct.rx_mem[5], 8'h12);

        $display("--- U4: no state change -> no packet ---");
        repeat (CPB * 40) @(negedge clk);
        check("U4 packets bytes", mon_rep.rx_count, 0);
        check("U4 line idles high", r_tx, 1);

        $display("--- U5: NORMAL -> WARNING packet ---");
        @(negedge clk); alarm_state = 2'd1; value = 8'd65;
        wait_reporter_idle;
        check("U5 bytes", mon_rep.rx_count, 3);
        check("U5 status byte (WARNING)", mon_rep.rx_mem[0], 8'hA1);
        check("U5 value byte", mon_rep.rx_mem[1], 8'd65);
        check("U5 count byte", mon_rep.rx_mem[2], 8'd0);

        $display("--- U6: FAULT, counter updates 1 clock later ---");
        @(negedge clk); alarm_state = 2'd3; value = 8'd92;
        @(negedge clk); fault_count = 8'd1;       // like fault_counter does
        wait_reporter_idle;
        check("U6 bytes", mon_rep.rx_count, 6);
        check("U6 status byte (FAULT)", mon_rep.rx_mem[3], 8'hA3);
        check("U6 value byte", mon_rep.rx_mem[4], 8'd92);
        check("U6 count byte includes new event", mon_rep.rx_mem[5], 8'd1);

        $display("--- U7: two changes during one packet are merged ---");
        @(negedge clk); alarm_state = 2'd2; value = 8'd83;  // PENDING
        repeat (CPB * 5) @(negedge clk);                    // packet in progress
        alarm_state = 2'd1;                                 // WARNING
        repeat (CPB * 5) @(negedge clk);
        alarm_state = 2'd0; value = 8'd30;                  // NORMAL
        wait_reporter_idle;
        repeat (CPB * 40) @(negedge clk);
        wait_reporter_idle;
        check("U7 bytes (two packets)", mon_rep.rx_count, 12);
        check("U7 first packet status (PENDING)", mon_rep.rx_mem[6], 8'hA2);
        check("U7 second packet status (latest = NORMAL)", mon_rep.rx_mem[9], 8'hA0);
        check("U7 second packet value", mon_rep.rx_mem[10], 8'd30);

        check("framing errors (direct)",   mon_direct.frame_errors, 0);
        check("framing errors (reporter)", mon_rep.frame_errors, 0);

        $display("============================================================");
        $display(" SUMMARY: %0d checks, %0d passed, %0d failed",
                 test_count, test_count - fail_count, fail_count);
        if (fail_count == 0) $display(" RESULT : ALL TESTS PASSED");
        else                 $display(" RESULT : TESTS FAILED");
        $display("============================================================");
        $finish;
    end

endmodule
