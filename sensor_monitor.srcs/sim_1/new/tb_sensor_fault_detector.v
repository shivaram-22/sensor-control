// ============================================================================
// Testbench   : tb_sensor_fault_detector
// DUT         : sensor_fault_detector (combinational threshold classifier)
// Language    : Verilog-2001, simulation only (NOT synthesizable)
//
// What this testbench verifies automatically:
//   Group A - the nine required threshold values (0,30,59,60,65,79,80,100,255)
//   Group C - boundary pairs (59/60, 79/80), repeated state transitions,
//             one-hot (mutual exclusion) on every check, no X/Z on outputs,
//             an exhaustive sweep of all 256 input values,
//             a second DUT with overridden parameters (100/200),
//             and an informational check of an unknown (X) input.
//
// Timing: total simulated time is about 0.75 us, so the run finishes even
// with Vivado's default 1000 ns simulation run time.
// ============================================================================
`timescale 1ns / 1ps

module tb_sensor_fault_detector;

    // ------------------------------------------------------------------
    // Test configuration
    // ------------------------------------------------------------------
    localparam DATA_WIDTH   = 8;
    localparam WARN_TH      = 60;    // must match the DUT parameters below
    localparam FAULT_TH     = 80;
    localparam ALT_WARN_TH  = 100;   // second DUT: proves parameterization
    localparam ALT_FAULT_TH = 200;

    localparam DIRECTED_DELAY = 10;  // ns between directed stimuli
    localparam SWEEP_DELAY    = 2;   // ns between sweep stimuli

    // State encoding used only inside the testbench
    localparam [1:0] ST_NORMAL  = 2'd0;
    localparam [1:0] ST_WARNING = 2'd1;
    localparam [1:0] ST_FAULT   = 2'd2;

    // ------------------------------------------------------------------
    // Signals
    // ------------------------------------------------------------------
    reg  [DATA_WIDTH-1:0] sensor_in;

    wire normal_led,  warning_led,  fault_led;     // default DUT
    wire alt_normal,  alt_warning,  alt_fault;     // parameter-override DUT

    integer test_count;
    integer fail_count;
    integer sweep_fail_start;
    integer value;

    // ------------------------------------------------------------------
    // Devices under test
    // ------------------------------------------------------------------
    sensor_fault_detector #(
        .DATA_WIDTH      (DATA_WIDTH),
        .WARN_THRESHOLD  (WARN_TH),
        .FAULT_THRESHOLD (FAULT_TH)
    ) dut (
        .sensor_in   (sensor_in),
        .normal_led  (normal_led),
        .warning_led (warning_led),
        .fault_led   (fault_led)
    );

    sensor_fault_detector #(
        .DATA_WIDTH      (DATA_WIDTH),
        .WARN_THRESHOLD  (ALT_WARN_TH),
        .FAULT_THRESHOLD (ALT_FAULT_TH)
    ) dut_alt (
        .sensor_in   (sensor_in),
        .normal_led  (alt_normal),
        .warning_led (alt_warning),
        .fault_led   (alt_fault)
    );

    // ------------------------------------------------------------------
    // Reference model: the expected state for a value and two thresholds.
    // Written independently of the RTL (ascending order, '<' comparisons)
    // so that a copy-paste bug in the RTL is not repeated here.
    // ------------------------------------------------------------------
    function [1:0] expected_state;
        input [DATA_WIDTH-1:0] v;
        input [31:0]           warn_th;
        input [31:0]           fault_th;
        begin
            if (v < warn_th)
                expected_state = ST_NORMAL;
            else if (v < fault_th)
                expected_state = ST_WARNING;
            else
                expected_state = ST_FAULT;
        end
    endfunction

    // ------------------------------------------------------------------
    // check_status: compares one set of outputs with the expected state.
    //   * outputs must be 0/1 (no X or Z)
    //   * exactly one output must be high (one-hot / mutual exclusion)
    //   * the high output must match the expected state
    //   verbose = 1 prints PASS lines too; verbose = 0 prints only FAILs.
    // ------------------------------------------------------------------
    task check_status;
        input [DATA_WIDTH-1:0] v;
        input [1:0]            exp_state;
        input                  n_led;
        input                  w_led;
        input                  f_led;
        input                  verbose;
        reg   [2:0]            exp_leds;
        reg   [2:0]            act_leds;
        begin
            test_count = test_count + 1;
            act_leds   = {n_led, w_led, f_led};
            case (exp_state)
                ST_NORMAL : exp_leds = 3'b100;
                ST_WARNING: exp_leds = 3'b010;
                default   : exp_leds = 3'b001;
            endcase

            if (^act_leds === 1'bx) begin
                fail_count = fail_count + 1;
                $display("FAIL  in=%3d  N/W/F=%b  -> output contains X/Z", v, act_leds);
            end else if ((n_led + w_led + f_led) != 1) begin
                fail_count = fail_count + 1;
                $display("FAIL  in=%3d  N/W/F=%b  -> not one-hot", v, act_leds);
            end else if (act_leds !== exp_leds) begin
                fail_count = fail_count + 1;
                $display("FAIL  in=%3d  N/W/F=%b  expected %b", v, act_leds, exp_leds);
            end else if (verbose) begin
                $display("PASS  in=%3d  N/W/F=%b  (%s)", v, act_leds,
                         (exp_state == ST_NORMAL)  ? "NORMAL " :
                         (exp_state == ST_WARNING) ? "WARNING" : "FAULT  ");
            end
        end
    endtask

    // Apply a value, wait for the combinational logic, check the default DUT.
    task apply_and_check;
        input [DATA_WIDTH-1:0] v;
        begin
            sensor_in = v;
            #DIRECTED_DELAY;
            check_status(v, expected_state(v, WARN_TH, FAULT_TH),
                         normal_led, warning_led, fault_led, 1'b1);
        end
    endtask

    // Same, but checks the parameter-override DUT.
    task apply_and_check_alt;
        input [DATA_WIDTH-1:0] v;
        begin
            sensor_in = v;
            #DIRECTED_DELAY;
            check_status(v, expected_state(v, ALT_WARN_TH, ALT_FAULT_TH),
                         alt_normal, alt_warning, alt_fault, 1'b1);
        end
    endtask

    // ------------------------------------------------------------------
    // Stimulus
    // ------------------------------------------------------------------
    initial begin
        $timeformat(-9, 0, " ns", 0);   // print %t values in nanoseconds
        test_count = 0;
        fail_count = 0;
        sensor_in  = {DATA_WIDTH{1'b0}};

        $display("============================================================");
        $display(" tb_sensor_fault_detector : thresholds WARN=%0d FAULT=%0d", WARN_TH, FAULT_TH);
        $display("============================================================");

        // ---- Group A: required threshold values ----------------------
        $display("--- Group A: required threshold values ---");
        apply_and_check(8'd0);
        apply_and_check(8'd30);
        apply_and_check(8'd59);
        apply_and_check(8'd60);
        apply_and_check(8'd65);
        apply_and_check(8'd79);
        apply_and_check(8'd80);
        apply_and_check(8'd100);
        apply_and_check(8'd255);

        // ---- Group C1: repeated transitions across both boundaries -------
        $display("--- Group C1: repeated transitions N<->W<->F ---");
        apply_and_check(8'd59);   // N
        apply_and_check(8'd60);   // W   (N -> W)
        apply_and_check(8'd59);   // N   (W -> N)
        apply_and_check(8'd79);   // W   (N -> W)
        apply_and_check(8'd80);   // F   (W -> F)
        apply_and_check(8'd79);   // W   (F -> W)
        apply_and_check(8'd255);  // F   (W -> F)
        apply_and_check(8'd0);    // N   (F -> N directly)
        apply_and_check(8'd80);   // F   (N -> F directly)

        // ---- Group C2: parameter override (WARN=100, FAULT=200) --------
        $display("--- Group C2: parameter override DUT (WARN=%0d FAULT=%0d) ---",
                 ALT_WARN_TH, ALT_FAULT_TH);
        apply_and_check_alt(8'd99);
        apply_and_check_alt(8'd100);
        apply_and_check_alt(8'd199);
        apply_and_check_alt(8'd200);

        // ---- Group C3: exhaustive sweep, both DUTs, all 256 inputs -----
        $display("--- Group C3: exhaustive sweep 0..255 on both DUTs (only FAILs printed) ---");
        sweep_fail_start = fail_count;
        for (value = 0; value < (1 << DATA_WIDTH); value = value + 1) begin
            sensor_in = value;
            #SWEEP_DELAY;
            check_status(value, expected_state(value, WARN_TH, FAULT_TH),
                         normal_led, warning_led, fault_led, 1'b0);
            check_status(value, expected_state(value, ALT_WARN_TH, ALT_FAULT_TH),
                         alt_normal, alt_warning, alt_fault, 1'b0);
        end
        if (fail_count == sweep_fail_start)
            $display("PASS  sweep: 512 checks (256 values x 2 DUTs), 0 mismatches");
        else
            $display("FAIL  sweep: %0d mismatches", fail_count - sweep_fail_start);

        // ---- Group C4: unknown input (informational, not scored) -------
        // In RTL simulation an if() whose condition is X takes the ELSE
        // branch, so an all-X input falls through to the NORMAL branch
        // ("X-optimism"). Real hardware never sees X, but this shows why
        // uninitialised inputs must be avoided in a testbench.
        $display("--- Group C4: unknown (X) input - informational ---");
        sensor_in = {DATA_WIDTH{1'bx}};
        #DIRECTED_DELAY;
        $display("INFO  in=X    N/W/F=%b%b%b  (if-else treats an X condition as false)",
                 normal_led, warning_led, fault_led);

        // ---- Summary ------------------------------------------------------
        $display("============================================================");
        $display(" SUMMARY: %0d checks, %0d passed, %0d failed",
                 test_count, test_count - fail_count, fail_count);
        if (fail_count == 0)
            $display(" RESULT : ALL TESTS PASSED");
        else
            $display(" RESULT : TESTS FAILED");
        $display(" Sim time at finish: %0t", $time);
        $display("============================================================");
        $finish;
    end

endmodule
