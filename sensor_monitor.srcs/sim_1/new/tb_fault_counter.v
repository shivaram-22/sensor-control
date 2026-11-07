// ============================================================================
// Testbench   : tb_fault_counter
// DUT         : fault_counter (edge-detecting, saturating)
// Language    : Verilog-2001, simulation only
//
// Test Group B (required):
//   B1 reset clears the counter
//   B2 a new fault event increments the counter once
//   B3 a fault held for many cycles still counts only once
//   B4 fault clears, new fault -> counter increments again
//   B5 reset clears the count AND the previous-fault register
//   B6 overflow: counter saturates at 255 and raises count_saturated
// Extra:
//   B7 single-cycle fault pulses separated by one idle cycle are all counted
//   Every clock cycle is also compared against a reference model, so an
//   unintended increment anywhere in the test is caught (scoreboard).
// ============================================================================
`timescale 1ns / 1ps

module tb_fault_counter;

    localparam WIDTH      = 8;
    localparam CLK_PERIOD = 10;

    reg              clk, rst, fault_status;
    wire [WIDTH-1:0] fault_count;
    wire             count_saturated;

    integer test_count, fail_count, i;
    integer ref_count;     // reference model
    reg     ref_prev;

    fault_counter #(.WIDTH(WIDTH)) dut (
        .clk(clk), .rst(rst), .fault_status(fault_status),
        .fault_count(fault_count), .count_saturated(count_saturated));

    initial clk = 1'b0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // ------------------------------------------------------------------
    task check;
        input [8*48:1] label;
        input integer  actual;
        input integer  expected;
        begin
            test_count = test_count + 1;
            if (actual !== expected) begin
                fail_count = fail_count + 1;
                $display("FAIL  %0s : got %0d, expected %0d  (t=%0t)",
                         label, actual, expected, $time);
            end else
                $display("PASS  %0s = %0d", label, actual);
        end
    endtask

    // One clock cycle: drive inputs at the falling edge, let one rising edge
    // pass, update the reference model, compare (silent unless mismatch).
    task cycle;
        input f;
        input r;
        begin
            fault_status = f;
            rst          = r;
            @(negedge clk);
            if (r) begin
                ref_count = 0;
                ref_prev  = 1'b0;
            end else begin
                if (f && !ref_prev && ref_count < 255)
                    ref_count = ref_count + 1;
                ref_prev = f;
            end
            test_count = test_count + 1;
            if (fault_count !== ref_count ||
                count_saturated !== (ref_count == 255)) begin
                fail_count = fail_count + 1;
                $display("FAIL  scoreboard: count=%0d sat=%b, model=%0d (t=%0t)",
                         fault_count, count_saturated, ref_count, $time);
            end
        end
    endtask

    // ------------------------------------------------------------------
    initial begin
        $timeformat(-9, 0, " ns", 0);
        test_count = 0; fail_count = 0;
        ref_count = 0; ref_prev = 1'b0;
        fault_status = 1'b0; rst = 1'b1;

        $display("============================================================");
        $display(" tb_fault_counter : edge-detecting, saturating at 255");
        $display("============================================================");
        @(negedge clk);

        $display("--- B1: reset clears the counter ---");
        cycle(1'b0, 1'b1); cycle(1'b0, 1'b1);
        check("B1 count after reset", fault_count, 0);
        cycle(1'b0, 1'b0); cycle(1'b0, 1'b0);
        check("B1 no fault -> still 0", fault_count, 0);

        $display("--- B2: first new fault event ---");
        cycle(1'b1, 1'b0);
        check("B2 count after 0->1 edge", fault_count, 1);

        $display("--- B3: sustained fault (20 cycles) ---");
        for (i = 0; i < 20; i = i + 1) cycle(1'b1, 1'b0);
        check("B3 count after 20 more fault cycles", fault_count, 1);

        $display("--- B4: fault clears, new fault ---");
        cycle(1'b0, 1'b0); cycle(1'b0, 1'b0);
        check("B4 count while fault cleared", fault_count, 1);
        cycle(1'b1, 1'b0);
        check("B4 count after second event", fault_count, 2);

        $display("--- B5: reset clears count and previous-fault state ---");
        cycle(1'b1, 1'b1);                   // reset while fault is high
        check("B5 count during reset", fault_count, 0);
        cycle(1'b1, 1'b0);                   // fault still high after reset
        check("B5 active fault re-detected after reset", fault_count, 1);
        cycle(1'b1, 1'b0);
        check("B5 not counted twice", fault_count, 1);

        $display("--- B7: 1-cycle pulses separated by 1 idle cycle ---");
        for (i = 0; i < 5; i = i + 1) begin
            cycle(1'b0, 1'b0);
            cycle(1'b1, 1'b0);
        end
        check("B7 count after 5 short pulses", fault_count, 6);

        $display("--- B6: overflow / saturation ---");
        for (i = 0; i < 300; i = i + 1) begin // 300 more events
            cycle(1'b0, 1'b0);
            cycle(1'b1, 1'b0);
        end
        check("B6 count saturates at", fault_count, 255);
        check("B6 count_saturated flag", count_saturated, 1);
        cycle(1'b0, 1'b0); cycle(1'b1, 1'b0);
        check("B6 stays at 255 on further events", fault_count, 255);
        cycle(1'b0, 1'b1);
        check("B6 reset leaves saturation", fault_count, 0);
        check("B6 flag cleared by reset", count_saturated, 0);

        $display("============================================================");
        $display(" SUMMARY: %0d checks (incl. per-cycle scoreboard), %0d passed, %0d failed",
                 test_count, test_count - fail_count, fail_count);
        if (fail_count == 0) $display(" RESULT : ALL TESTS PASSED");
        else                 $display(" RESULT : TESTS FAILED");
        $display("============================================================");
        $finish;
    end

endmodule
