// ============================================================================
// Testbench   : tb_sensor_monitor_top   (complete-system verification)
// DUT         : sensor_monitor_top
// Language    : Verilog-2001, simulation only
// Needs       : tb/uart_rx_monitor.v and the four .mem files from
//               scripts/gen_sensor_trace.py:
//                 trace_info.mem, sensor_trace.mem,
//                 expected_samples.mem, expected_packets.mem
//
// Method:
//   A realistic sensor trace (noise, a spike, a short burst, a value hovering
//   near the warning threshold, two real over-temperature faults, operator
//   acknowledges) is replayed sample by sample. After every sample the
//   filtered value, alarm state and fault count are compared with the golden
//   results from an independent Python model. At the end, every decoded UART
//   packet is compared with the expected packet list.
//
//   S0 reset values
//   S1 trace replay: per-sample golden compare + raw classifier check
//   S2 UART packets vs golden list, no framing errors
//   S3 reset during an active fault clears count/state/filter, and the
//      still-present fault is detected again afterwards
//   Every clock: LEDs one-hot, raw outputs one-hot, fault_pending implies
//   warning_led, count changes only by +1 while fault_led is high, no X.
//
// Clock 10 ns. One sample every SAMPLE_PERIOD clocks; acknowledges are
// pressed ACK_OFFSET clocks after their sample. UART runs at CPB clocks/bit
// so that each packet finishes before the next state change.
// Total simulated time is about 1.2 ms -> in Vivado use "Run All".
// ============================================================================
`timescale 1ns / 1ps

module tb_sensor_monitor_top;

    // ---- configuration -------------------------------------------------------
    parameter INFO_FILE     = "trace_info.mem";
    parameter TRACE_FILE    = "sensor_trace.mem";
    parameter EXPECTED_FILE = "expected_samples.mem";
    parameter PACKET_FILE   = "expected_packets.mem";

    localparam CLK_PERIOD    = 10;
    localparam CPB           = 4;      // UART clocks per bit (fast sim)
    localparam SAMPLE_PERIOD = 512;    // clocks between samples
    localparam ACK_OFFSET    = 256;    // ack pressed mid-period
    localparam MAX_SAMPLES   = 1024;
    localparam MAX_PACKETS   = 64;

    localparam [1:0] S_NORMAL = 2'd0, S_WARNING = 2'd1,
                     S_PENDING = 2'd2, S_FAULT = 2'd3;

    // ---- DUT signals ---------------------------------------------------------
    reg        clk, rst, sample_valid, ack;
    reg  [7:0] sensor_in;
    wire       raw_normal, raw_warning, raw_fault;
    wire [7:0] filtered_value;
    wire [1:0] alarm_state;
    wire       normal_led, warning_led, fault_led, fault_pending;
    wire [7:0] fault_count;
    wire       count_saturated, uart_txd;

    // ---- golden data -----------------------------------------------------
    reg [31:0] info_mem  [0:1];
    reg [8:0]  trace_mem [0:MAX_SAMPLES-1];
    reg [31:0] exp_mem   [0:MAX_SAMPLES-1];
    reg [23:0] pkt_mem   [0:MAX_PACKETS-1];
    integer    num_samples, num_packets;

    integer test_count, fail_count, n, p, b;
    integer sample_idx;
    reg     checking;
    reg     rx_enable;
    reg [1:0] logged_state;
    reg [7:0] prev_count;
    reg [7:0] exp_filtered, exp_count;
    reg [1:0] exp_after_sample, exp_end;
    reg [7:0] rx_b0, rx_b1, rx_b2;

    // ---- DUT -------------------------------------------------------------
    sensor_monitor_top #(
        .CLKS_PER_BIT (CPB)            // all other parameters at defaults
    ) dut (
        .clk(clk), .rst(rst), .sample_valid(sample_valid),
        .sensor_in(sensor_in), .ack(ack),
        .raw_normal(raw_normal), .raw_warning(raw_warning), .raw_fault(raw_fault),
        .filtered_value(filtered_value), .alarm_state(alarm_state),
        .normal_led(normal_led), .warning_led(warning_led),
        .fault_led(fault_led), .fault_pending(fault_pending),
        .fault_count(fault_count), .count_saturated(count_saturated),
        .uart_txd(uart_txd));

    uart_rx_monitor #(.CLKS_PER_BIT(CPB)) gateway (
        .clk(clk), .enable(rx_enable), .rx(uart_txd));

    initial clk = 1'b0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // ---- helpers ---------------------------------------------------------
    function [8*8:1] name;
        input [1:0] s;
        begin
            case (s)
                S_NORMAL : name = "NORMAL";
                S_WARNING: name = "WARNING";
                S_PENDING: name = "PENDING";
                default  : name = "FAULT";
            endcase
        end
    endfunction

    task fail;
        input [8*60:1] msg;
        begin
            fail_count = fail_count + 1;
            $display("FAIL  [sample %0d] %0s (t=%0t)", sample_idx, msg, $time);
        end
    endtask

    task check;
        input [8*52:1] label;
        input integer  actual;
        input integer  expected;
        begin
            test_count = test_count + 1;
            if (actual !== expected) begin
                fail_count = fail_count + 1;
                $display("FAIL  %0s : got %0d, expected %0d (t=%0t)",
                         label, actual, expected, $time);
            end else
                $display("PASS  %0s = %0d", label, actual);
        end
    endtask

    // ---- per-cycle invariants -----------------------------------------------
    always @(negedge clk) begin
        if (checking && !rst) begin
            if (^{normal_led, warning_led, fault_led, fault_pending,
                  raw_normal, raw_warning, raw_fault, fault_count, uart_txd} === 1'bx)
                fail("X/Z on an output");
            if ((normal_led + warning_led + fault_led) != 1)
                fail("alarm LEDs not one-hot");
            if ((raw_normal + raw_warning + raw_fault) != 1)
                fail("raw LEDs not one-hot");
            if (fault_pending && !warning_led)
                fail("fault_pending without warning_led");
            if (fault_count != prev_count &&
                !(fault_count == prev_count + 8'd1 && fault_led))
                fail("unexpected fault_count change");
        end
        prev_count = fault_count;
    end

    // ---- readable event log (for the report) -------------------------------
    always @(alarm_state) if (checking && !rst) begin
        $display("      [sample %3d] alarm %-7s -> %-7s  filtered=%3d",
                 sample_idx, name(logged_state), name(alarm_state), filtered_value);
        logged_state = alarm_state;
    end
    always @(posedge raw_fault) if (checking && !rst && !fault_led)
        $display("      [sample %3d] raw_fault=1 (input %0d) while alarm is %0s",
                 sample_idx, sensor_in, name(alarm_state));
    always @(fault_count) if (checking && !rst)
        $display("      [sample %3d] fault_count = %0d", sample_idx, fault_count);

    // apply one sample (driven on the falling edge, 1-clock strobe)
    task apply_sample;
        input [7:0] v;
        begin
            @(negedge clk);
            sensor_in = v; sample_valid = 1'b1;
            @(negedge clk);
            sample_valid = 1'b0;
        end
    endtask

    // ---- main stimulus ---------------------------------------------------
    initial begin
        $timeformat(-9, 0, " ns", 0);
        test_count = 0; fail_count = 0; sample_idx = 0;
        checking = 1'b0; rx_enable = 1'b0;
        rst = 1'b1; sample_valid = 1'b0; ack = 1'b0; sensor_in = 8'd0;
        logged_state = S_NORMAL; prev_count = 8'd0;

        $readmemh(INFO_FILE, info_mem);
        num_samples = info_mem[0];
        num_packets = info_mem[1];
        if (num_samples < 1 || num_samples > MAX_SAMPLES || ^info_mem[0] === 1'bx) begin
            $display("ERROR: could not read %0s - add the .mem files to the", INFO_FILE);
            $display("       simulation sources (see README). Simulation stopped.");
            $finish;
        end
        $readmemh(TRACE_FILE,    trace_mem, 0, num_samples - 1);
        $readmemh(EXPECTED_FILE, exp_mem,   0, num_samples - 1);
        $readmemh(PACKET_FILE,   pkt_mem,   0, num_packets - 1);

        $display("============================================================");
        $display(" tb_sensor_monitor_top : %0d samples, %0d expected UART packets",
                 num_samples, num_packets);
        $display("============================================================");

        // ---- S0: reset -----------------------------------------------------
        $display("--- S0: reset ---");
        repeat (3) @(negedge clk);
        rst = 1'b0; rx_enable = 1'b1;
        @(negedge clk);
        check("S0 alarm_state after reset (0=NORMAL)", alarm_state, S_NORMAL);
        check("S0 fault_count after reset", fault_count, 0);
        check("S0 filtered_value after reset", filtered_value, 0);
        check("S0 UART line idle high", uart_txd, 1);
        checking = 1'b1;

        // ---- S1: replay the trace ------------------------------------------
        $display("--- S1: trace replay, golden compare every sample (events below) ---");
        p = fail_count;
        for (n = 0; n < num_samples; n = n + 1) begin
            sample_idx       = n;
            exp_end          = exp_mem[n][25:24];
            exp_after_sample = exp_mem[n][17:16];
            exp_count        = exp_mem[n][15:8];
            exp_filtered     = exp_mem[n][7:0];

            apply_sample(trace_mem[n][7:0]);

            // raw (unfiltered, combinational) classifier
            test_count = test_count + 1;
            if ({raw_normal, raw_warning, raw_fault} !==
                ((sensor_in >= 80) ? 3'b001 : (sensor_in >= 60) ? 3'b010 : 3'b100))
                fail("raw classifier mismatch");

            // filter (+1 clk), FSM (+2), counter (+3): settle, then check
            repeat (4) @(negedge clk);
            test_count = test_count + 2;
            if (filtered_value !== exp_filtered) fail("filtered value != golden");
            if (alarm_state !== exp_after_sample) fail("state after sample != golden");

            // operator acknowledge, if scheduled for this sample
            repeat (ACK_OFFSET - 6) @(negedge clk);
            if (trace_mem[n][8]) begin
                $display("      [sample %3d] operator presses ACK (filtered=%0d)",
                         n, filtered_value);
                ack = 1'b1; @(negedge clk); ack = 1'b0;
            end else
                @(negedge clk);

            // end of sample period
            repeat (SAMPLE_PERIOD - ACK_OFFSET - 3) @(negedge clk);
            test_count = test_count + 2;
            if (alarm_state !== exp_end)   fail("state at end of period != golden");
            if (fault_count !== exp_count) fail("fault_count != golden");
        end
        if (fail_count == p)
            $display("PASS  S1 all %0d samples match the golden model (filtered value, state, count)",
                     num_samples);

        // ---- S2: UART packets ---------------------------------------------
        $display("--- S2: UART status packets ---");
        repeat (SAMPLE_PERIOD) @(negedge clk);
        check("S2 bytes received (3 per packet)", gateway.rx_count, 3 * num_packets);
        check("S2 UART framing errors", gateway.frame_errors, 0);
        p = fail_count;
        for (b = 0; b < num_packets; b = b + 1) begin
            rx_b0 = gateway.rx_mem[3*b];
            rx_b1 = gateway.rx_mem[3*b + 1];
            rx_b2 = gateway.rx_mem[3*b + 2];
            test_count = test_count + 1;
            if ({rx_b0, rx_b1, rx_b2} !== pkt_mem[b]) begin
                fail_count = fail_count + 1;
                $display("FAIL  packet %0d: got %h %h %h, expected %h", b,
                         rx_b0, rx_b1, rx_b2, pkt_mem[b]);
            end else
                $display("      packet %2d: %h %h %h  -> %-7s value=%3d count=%0d",
                         b, rx_b0, rx_b1, rx_b2, name(rx_b0[1:0]), rx_b1, rx_b2);
        end
        if (fail_count == p)
            $display("PASS  S2 all %0d packets match the golden list", num_packets);

        // ---- S3: reset during an active fault ------------------------------
        $display("--- S3: reset while a fault is active ---");
        sample_idx = num_samples;
        for (n = 0; n < 6; n = n + 1) begin
            sample_idx = sample_idx + 1;
            apply_sample(8'd200);
            repeat (8) @(negedge clk);
        end
        check("S3 fault confirmed (3=FAULT)", alarm_state, S_FAULT);
        check("S3 fault_count before reset", fault_count, 3);
        wait (dut.u_reporter.r_state == 3'd0 && !dut.u_uart.tx_busy);
        @(negedge clk);
        checking = 1'b0; rst = 1'b1;
        @(negedge clk); @(negedge clk);
        rst = 1'b0; @(negedge clk);
        check("S3 state after reset (0=NORMAL)", alarm_state, S_NORMAL);
        check("S3 fault_count after reset", fault_count, 0);
        check("S3 filter cleared by reset", filtered_value, 0);
        logged_state = S_NORMAL; checking = 1'b1;
        for (n = 0; n < 6; n = n + 1) begin
            sample_idx = sample_idx + 1;
            apply_sample(8'd200);
            repeat (8) @(negedge clk);
        end
        check("S3 still-present fault detected again (3=FAULT)", alarm_state, S_FAULT);
        check("S3 counted once after reset", fault_count, 1);

        // ---- summary ----------------------------------------------------------
        $display("============================================================");
        $display(" SUMMARY: %0d checks, %0d passed, %0d failed (+ per-clock invariants)",
                 test_count, test_count - fail_count, fail_count);
        if (fail_count == 0) $display(" RESULT : ALL TESTS PASSED");
        else                 $display(" RESULT : TESTS FAILED");
        $display(" Simulated time: %0t", $time);
        $display("============================================================");
        $finish;
    end

endmodule
