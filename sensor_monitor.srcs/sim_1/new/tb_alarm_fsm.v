// ============================================================================
// Testbench   : tb_alarm_fsm
// DUTs        : alarm_fsm  (CONFIRM_COUNT = 4)   and
//               alarm_fsm  (CONFIRM_COUNT = 1)   -> no confirmation delay
// Language    : Verilog-2001, simulation only
//
//   H1 reset state
//   H2 warning hysteresis: enter at 60, stay at 55..59, leave below 55
//   H3 reading hovering 59/61 changes state only once (no flicker)
//   C1 short fault burst (3 samples < 4) is rejected, fault_led never high
//   C2 sustained fault confirmed on exactly the 4th sample
//   C3 latch: ack ignored at 85 and at 77 (>= FAULT_OFF), fault held at 40
//      without ack, cleared by ack at 40 -> NORMAL
//   C4 ack while reading is in the warning band -> WARNING
//   C5 one low sample inside a burst restarts the confirmation count
//   C6 value changes without value_valid do not change state
//   C7 reset from FAULT
//   C8 CONFIRM_COUNT = 1 instance goes straight to FAULT
//   Every cycle: LEDs one-hot, fault_pending only with warning_led, no X.
// ============================================================================
`timescale 1ns / 1ps

module tb_alarm_fsm;

    localparam CLK_PERIOD = 10;
    localparam [1:0] S_NORMAL = 2'd0, S_WARNING = 2'd1,
                     S_PENDING = 2'd2, S_FAULT = 2'd3;

    reg        clk, rst, value_valid, ack;
    reg  [7:0] value;

    wire [1:0] state;
    wire       normal_led, warning_led, fault_led, fault_pending;
    wire [1:0] state1;
    wire       n1, w1, f1, p1;

    integer test_count, fail_count, i, changes;
    reg [1:0] last_state;
    reg       fault_seen;

    alarm_fsm #(.CONFIRM_COUNT(4)) dut (
        .clk(clk), .rst(rst), .value_valid(value_valid), .value(value), .ack(ack),
        .alarm_state(state), .normal_led(normal_led), .warning_led(warning_led),
        .fault_led(fault_led), .fault_pending(fault_pending));

    alarm_fsm #(.CONFIRM_COUNT(1)) dut_c1 (
        .clk(clk), .rst(rst), .value_valid(value_valid), .value(value), .ack(ack),
        .alarm_state(state1), .normal_led(n1), .warning_led(w1),
        .fault_led(f1), .fault_pending(p1));

    initial clk = 1'b0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // ---- Per-cycle invariant checks (both DUTs) ---------------------------
    always @(negedge clk) if (!rst) begin
        if ((normal_led + warning_led + fault_led) != 1 ||
            ^{normal_led, warning_led, fault_led, fault_pending} === 1'bx ||
            (fault_pending && !warning_led) ||
            (n1 + w1 + f1) != 1) begin
            fail_count = fail_count + 1;
            $display("FAIL  invariant: LEDs N/W/F/P=%b%b%b%b c1=%b%b%b (t=%0t)",
                     normal_led, warning_led, fault_led, fault_pending, n1, w1, f1, $time);
        end
        if (state != last_state) changes = changes + 1;
        last_state = state;
        if (fault_led) fault_seen = 1'b1;
    end

    // ------------------------------------------------------------------
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

    task expect_state;
        input [8*44:1] label;
        input [1:0]    expected;
        begin
            test_count = test_count + 1;
            if (state !== expected) begin
                fail_count = fail_count + 1;
                $display("FAIL  %0s : state %0s, expected %0s (t=%0t)",
                         label, name(state), name(expected), $time);
            end else
                $display("PASS  %0s : %0s", label, name(state));
        end
    endtask

    // Present one sample for one clock (driven on falling edge).
    task sample;
        input [7:0] v;
        begin
            value = v; value_valid = 1'b1;
            @(negedge clk);
            value_valid = 1'b0;
            @(negedge clk);
        end
    endtask

    // One-cycle operator acknowledge.
    task press_ack;
        begin
            ack = 1'b1; @(negedge clk);
            ack = 1'b0; @(negedge clk);
        end
    endtask

    task do_reset;
        begin
            rst = 1'b1; @(negedge clk); @(negedge clk);
            rst = 1'b0; @(negedge clk);
        end
    endtask

    // ------------------------------------------------------------------
    initial begin
        $timeformat(-9, 0, " ns", 0);
        test_count = 0; fail_count = 0; changes = 0;
        last_state = S_NORMAL; fault_seen = 1'b0;
        rst = 1'b1; value_valid = 1'b0; ack = 1'b0; value = 8'd0;

        $display("============================================================");
        $display(" tb_alarm_fsm : WARN 60/55, FAULT 80/75, confirm = 4 samples");
        $display("============================================================");
        @(negedge clk);
        do_reset;

        $display("--- H1: reset ---");
        expect_state("H1 after reset", S_NORMAL);

        $display("--- H2: warning hysteresis ---");
        sample(8'd59); expect_state("H2 59 (below WARN_ON)",        S_NORMAL);
        sample(8'd60); expect_state("H2 60 enters WARNING",         S_WARNING);
        sample(8'd57); expect_state("H2 57 stays (hysteresis band)",S_WARNING);
        sample(8'd55); expect_state("H2 55 stays (= WARN_OFF)",     S_WARNING);
        sample(8'd54); expect_state("H2 54 leaves to NORMAL",       S_NORMAL);
        sample(8'd58); expect_state("H2 58 does not re-enter",      S_NORMAL);

        $display("--- H3: hovering 59/61 x10 ---");
        changes = 0;
        for (i = 0; i < 10; i = i + 1) begin
            sample(8'd59);
            sample(8'd61);
        end
        test_count = test_count + 1;
        if (changes == 1)
            $display("PASS  H3 state changes while hovering = 1 (no flicker)");
        else begin
            fail_count = fail_count + 1;
            $display("FAIL  H3 state changes while hovering = %0d, expected 1", changes);
        end

        $display("--- C1: 3-sample burst is rejected ---");
        fault_seen = 1'b0;
        sample(8'd85); expect_state("C1 burst sample 1", S_PENDING);
        test_count = test_count + 1;
        if (state1 === S_FAULT) $display("PASS  C8 CONFIRM_COUNT=1 instance: FAULT on 1st sample");
        else begin fail_count = fail_count + 1;
             $display("FAIL  C8 CONFIRM_COUNT=1 instance: state %0s", name(state1)); end
        sample(8'd85); expect_state("C1 burst sample 2", S_PENDING);
        sample(8'd85); expect_state("C1 burst sample 3", S_PENDING);
        sample(8'd70); expect_state("C1 drop to 70 -> rejected", S_WARNING);
        test_count = test_count + 1;
        if (!fault_seen) $display("PASS  C1 fault_led never asserted during burst");
        else begin fail_count = fail_count + 1; $display("FAIL  C1 fault_led asserted"); end

        $display("--- C2: sustained fault confirmed on 4th sample ---");
        sample(8'd90); expect_state("C2 sample 1", S_PENDING);
        sample(8'd90); expect_state("C2 sample 2", S_PENDING);
        sample(8'd90); expect_state("C2 sample 3", S_PENDING);
        sample(8'd90); expect_state("C2 sample 4 -> CONFIRMED", S_FAULT);

        $display("--- C3: latch and acknowledge ---");
        sample(8'd85); press_ack; expect_state("C3 ack at 85 ignored", S_FAULT);
        sample(8'd77); press_ack; expect_state("C3 ack at 77 ignored (>= 75)", S_FAULT);
        sample(8'd40);            expect_state("C3 drops to 40, still latched", S_FAULT);
        repeat (10) @(negedge clk);
        expect_state("C3 still latched 10 cycles later", S_FAULT);
        press_ack;                expect_state("C3 ack at 40 -> NORMAL", S_NORMAL);

        $display("--- C4: ack in warning band ---");
        for (i = 0; i < 4; i = i + 1) sample(8'd100);
        expect_state("C4 confirmed again", S_FAULT);
        sample(8'd57); press_ack; expect_state("C4 ack at 57 -> WARNING", S_WARNING);

        $display("--- C5: interrupted burst restarts the count ---");
        sample(8'd85); sample(8'd85); sample(8'd85);
        sample(8'd79); expect_state("C5 one low sample breaks it", S_WARNING);
        sample(8'd85); sample(8'd85); sample(8'd85);
        expect_state("C5 3 more samples: still pending", S_PENDING);
        sample(8'd85); expect_state("C5 4th consecutive -> FAULT", S_FAULT);

        $display("--- C6: no sample strobe, no change ---");
        press_ack;                      // value is 85 -> ignored
        value = 8'd10;                  // change value WITHOUT value_valid
        repeat (5) @(negedge clk);
        expect_state("C6 value=10 but no valid strobe", S_FAULT);
        // (ack is level-based on the held value, so ack now clears it)
        press_ack; expect_state("C6 ack with held value 10 -> NORMAL", S_NORMAL);
        value = 8'd200;
        repeat (5) @(negedge clk);
        expect_state("C6 value=200 but no valid strobe", S_NORMAL);

        $display("--- C7: reset from FAULT ---");
        for (i = 0; i < 4; i = i + 1) sample(8'd200);
        expect_state("C7 confirmed", S_FAULT);
        do_reset;
        expect_state("C7 after reset", S_NORMAL);

        $display("============================================================");
        $display(" SUMMARY: %0d checks, %0d passed, %0d failed (+ per-cycle invariants)",
                 test_count, test_count - fail_count, fail_count);
        if (fail_count == 0) $display(" RESULT : ALL TESTS PASSED");
        else                 $display(" RESULT : TESTS FAILED");
        $display("============================================================");
        $finish;
    end

endmodule
