// ============================================================================
// Testbench   : tb_moving_avg_filter
// DUTs        : moving_avg_filter with LOG2_TAPS = 0, 2, 3 (1, 4, 8 taps)
// Language    : Verilog-2001, simulation only
//
// Checks (all automatic):
//   F1 reset clears the output and the strobe
//   F2 known sequence on the 4-tap filter (hand-calculated values)
//   F3 avg_valid is a 1-cycle strobe and avg_out holds between samples
//   F4 300 pseudo-random samples on all three filters vs a reference model
//   F5 reset in the middle of operation clears the history (warm-up again)
// Stimulus is applied on the falling clock edge, outputs are checked on the
// following falling edge -> no race with the rising-edge logic.
// ============================================================================
`timescale 1ns / 1ps

module tb_moving_avg_filter;

    localparam DATA_WIDTH = 8;
    localparam CLK_PERIOD = 10;

    reg                   clk;
    reg                   rst;
    reg                   sample_valid;
    reg  [DATA_WIDTH-1:0] sample_in;

    wire                  v1, v4, v8;
    wire [DATA_WIDTH-1:0] avg1, avg4, avg8;

    integer test_count, fail_count;
    integer i, k, seed;

    // reference history (index 0 = newest)
    integer ref1 [0:0];
    integer ref4 [0:3];
    integer ref8 [0:7];

    // ------------------------------------------------------------------
    moving_avg_filter #(.DATA_WIDTH(DATA_WIDTH), .LOG2_TAPS(0)) dut1 (
        .clk(clk), .rst(rst), .sample_valid(sample_valid), .sample_in(sample_in),
        .avg_valid(v1), .avg_out(avg1));

    moving_avg_filter #(.DATA_WIDTH(DATA_WIDTH), .LOG2_TAPS(2)) dut4 (
        .clk(clk), .rst(rst), .sample_valid(sample_valid), .sample_in(sample_in),
        .avg_valid(v4), .avg_out(avg4));

    moving_avg_filter #(.DATA_WIDTH(DATA_WIDTH), .LOG2_TAPS(3)) dut8 (
        .clk(clk), .rst(rst), .sample_valid(sample_valid), .sample_in(sample_in),
        .avg_valid(v8), .avg_out(avg8));

    // 100 MHz clock (10 ns period)
    initial clk = 1'b0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // ------------------------------------------------------------------
    task check;
        input [8*40:1] label;
        input integer  actual;
        input integer  expected;
        input          verbose;
        begin
            test_count = test_count + 1;
            if (actual !== expected) begin
                fail_count = fail_count + 1;
                $display("FAIL  %0s : got %0d, expected %0d  (t=%0t)",
                         label, actual, expected, $time);
            end else if (verbose)
                $display("PASS  %0s = %0d", label, actual);
        end
    endtask

    task clear_reference;
        begin
            for (k = 0; k < 8; k = k + 1) ref8[k] = 0;
            for (k = 0; k < 4; k = k + 1) ref4[k] = 0;
            ref1[0] = 0;
        end
    endtask

    // Expected averages (integer division = floor = right shift)
    function integer sum4; input dummy; integer s, j;
        begin s = 0; for (j = 0; j < 4; j = j + 1) s = s + ref4[j]; sum4 = s; end
    endfunction
    function integer sum8; input dummy; integer s, j;
        begin s = 0; for (j = 0; j < 8; j = j + 1) s = s + ref8[j]; sum8 = s; end
    endfunction

    // Send one sample, update the reference model, check all three DUTs.
    task send_sample;
        input [DATA_WIDTH-1:0] value;
        input                  verbose;
        begin
            @(negedge clk);
            sample_in    = value;
            sample_valid = 1'b1;
            // reference model shift
            for (k = 7; k > 0; k = k - 1) ref8[k] = ref8[k-1];
            for (k = 3; k > 0; k = k - 1) ref4[k] = ref4[k-1];
            ref8[0] = value; ref4[0] = value; ref1[0] = value;
            @(negedge clk);                 // one rising edge has passed
            sample_valid = 1'b0;
            check("strobe 1-tap",  v1, 1, 1'b0);
            check("strobe 4-tap",  v4, 1, 1'b0);
            check("strobe 8-tap",  v8, 1, 1'b0);
            check("avg 1-tap", avg1, ref1[0],      verbose);
            check("avg 4-tap", avg4, sum4(0) / 4,  verbose);
            check("avg 8-tap", avg8, sum8(0) / 8,  verbose);
        end
    endtask

    task do_reset;
        begin
            @(negedge clk); rst = 1'b1;
            @(negedge clk); @(negedge clk); rst = 1'b0;
            clear_reference;
        end
    endtask

    // ------------------------------------------------------------------
    initial begin
        $timeformat(-9, 0, " ns", 0);
        test_count = 0; fail_count = 0; seed = 2026;
        rst = 1'b1; sample_valid = 1'b0; sample_in = 0;
        clear_reference;

        $display("============================================================");
        $display(" tb_moving_avg_filter : 1-, 4- and 8-tap filters");
        $display("============================================================");

        // ---- F1: reset ---------------------------------------------------
        $display("--- F1: reset ---");
        repeat (3) @(negedge clk);
        check("avg 4-tap in reset",   avg4, 0, 1'b1);
        check("valid 4-tap in reset", v4,   0, 1'b1);
        rst = 1'b0;

        // ---- F2: hand-calculated sequence on the 4-tap filter -------------
        //  inputs : 100  100  100  100   20   20
        //  sums   : 100  200  300  400  320  240
        //  /4     :  25   50   75  100   80   60
        $display("--- F2: known sequence (4-tap: 25,50,75,100,80,60) ---");
        send_sample(8'd100, 1'b0); check("F2 step1", avg4,  25, 1'b1);
        send_sample(8'd100, 1'b0); check("F2 step2", avg4,  50, 1'b1);
        send_sample(8'd100, 1'b0); check("F2 step3", avg4,  75, 1'b1);
        send_sample(8'd100, 1'b0); check("F2 step4", avg4, 100, 1'b1);
        send_sample(8'd20,  1'b0); check("F2 step5", avg4,  80, 1'b1);
        send_sample(8'd20,  1'b0); check("F2 step6", avg4,  60, 1'b1);

        // ---- F3: strobe is one cycle, output holds ------------------------
        $display("--- F3: strobe width and output hold ---");
        repeat (5) @(negedge clk);
        check("valid low when idle", v4,   0,  1'b1);
        check("avg held when idle",  avg4, 60, 1'b1);

        // ---- F4: random samples vs reference model ------------------------
        $display("--- F4: 300 random samples, 3 filters (only FAILs printed) ---");
        k = fail_count;
        for (i = 0; i < 300; i = i + 1) begin
            send_sample($random(seed), 1'b0);
            // random idle gap 0..3 cycles between samples
            repeat ($unsigned($random(seed)) % 4) @(negedge clk);
        end
        if (fail_count == k)
            $display("PASS  random: 300 samples x 3 filters match the reference model");

        // ---- F5: max value, then reset mid-operation ----------------------
        $display("--- F5: full-scale input and reset mid-operation ---");
        for (i = 0; i < 8; i = i + 1) send_sample(8'd255, 1'b0);
        check("8-tap full scale (no overflow)", avg8, 255, 1'b1);
        do_reset;
        check("avg after reset", avg4, 0, 1'b1);
        send_sample(8'd200, 1'b0);
        check("warm-up after reset (200/4)", avg4, 50, 1'b1);

        // ---- Summary -------------------------------------------------------
        $display("============================================================");
        $display(" SUMMARY: %0d checks, %0d passed, %0d failed",
                 test_count, test_count - fail_count, fail_count);
        if (fail_count == 0) $display(" RESULT : ALL TESTS PASSED");
        else                 $display(" RESULT : TESTS FAILED");
        $display("============================================================");
        $finish;
    end

endmodule
