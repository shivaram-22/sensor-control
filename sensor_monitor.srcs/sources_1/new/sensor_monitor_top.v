// ============================================================================
// Module      : sensor_monitor_top
// Project     : FPGA-Based Intelligent Sensor Monitoring and Fault Detection
//               System Using Verilog HDL for Industrial IoT Applications
// Language    : Verilog-2001 (synthesizable)
//
// Data path:
//
//  sensor_in ─┬─► sensor_fault_detector ─► raw_normal / raw_warning / raw_fault
//             │   (instantaneous, unfiltered classification - for comparison)
//             │
//             └─► moving_avg_filter ─► filtered_value ─► alarm_fsm ─► normal_led
//                 (4-sample average)                   (hysteresis,  warning_led
//                                              ack ───► confirmation, fault_led
//                                                       latch/ack)   fault_pending
//                                                           │
//                                         fault_led ─► fault_counter ─► fault_count
//                                                           │
//               alarm_state, filtered_value, fault_count ─► status_reporter
//                                                           ─► uart_tx ─► uart_txd
//
//  All sequential blocks use the same clock and a synchronous active-high
//  reset. sample_valid is a 1-clock strobe per new ADC sample.
// ============================================================================
`timescale 1ns / 1ps

module sensor_monitor_top #(
    parameter DATA_WIDTH    = 8,
    parameter LOG2_TAPS     = 2,     // moving average of 4 samples
    parameter WARN_ON       = 60,
    parameter WARN_OFF      = 55,
    parameter FAULT_ON      = 80,
    parameter FAULT_OFF     = 75,
    parameter CONFIRM_COUNT = 4,     // consecutive samples to confirm a fault
    parameter CLKS_PER_BIT  = 868    // 100 MHz / 115200 baud
) (
    input  wire                  clk,
    input  wire                  rst,
    input  wire                  sample_valid,
    input  wire [DATA_WIDTH-1:0] sensor_in,
    input  wire                  ack,

    // instantaneous (raw) classification of the unfiltered input
    output wire                  raw_normal,
    output wire                  raw_warning,
    output wire                  raw_fault,

    // confirmed alarm outputs
    output wire [DATA_WIDTH-1:0] filtered_value,
    output wire [1:0]            alarm_state,
    output wire                  normal_led,
    output wire                  warning_led,
    output wire                  fault_led,
    output wire                  fault_pending,

    // fault event counter
    output wire [7:0]            fault_count,
    output wire                  count_saturated,

    // serial status uplink
    output wire                  uart_txd
);

    wire       filtered_valid;
    wire       tx_start, tx_busy;
    wire [7:0] tx_data;

    // ---- 1. Raw (unfiltered) threshold classification -----------------------
    sensor_fault_detector #(
        .DATA_WIDTH      (DATA_WIDTH),
        .WARN_THRESHOLD  (WARN_ON),
        .FAULT_THRESHOLD (FAULT_ON)
    ) u_raw_detector (
        .sensor_in   (sensor_in),
        .normal_led  (raw_normal),
        .warning_led (raw_warning),
        .fault_led   (raw_fault)
    );

    // ---- 2. Noise filter -----------------------------------------------------
    moving_avg_filter #(
        .DATA_WIDTH (DATA_WIDTH),
        .LOG2_TAPS  (LOG2_TAPS)
    ) u_filter (
        .clk          (clk),
        .rst          (rst),
        .sample_valid (sample_valid),
        .sample_in    (sensor_in),
        .avg_valid    (filtered_valid),
        .avg_out      (filtered_value)
    );

    // ---- 3. Alarm state machine ---------------------------------------------
    alarm_fsm #(
        .DATA_WIDTH    (DATA_WIDTH),
        .WARN_ON       (WARN_ON),
        .WARN_OFF      (WARN_OFF),
        .FAULT_ON      (FAULT_ON),
        .FAULT_OFF     (FAULT_OFF),
        .CONFIRM_COUNT (CONFIRM_COUNT)
    ) u_alarm (
        .clk           (clk),
        .rst           (rst),
        .value_valid   (filtered_valid),
        .value         (filtered_value),
        .ack           (ack),
        .alarm_state   (alarm_state),
        .normal_led    (normal_led),
        .warning_led   (warning_led),
        .fault_led     (fault_led),
        .fault_pending (fault_pending)
    );

    // ---- 4. Confirmed-fault event counter -----------------------------------
    fault_counter #(
        .WIDTH (8)
    ) u_counter (
        .clk             (clk),
        .rst             (rst),
        .fault_status    (fault_led),
        .fault_count     (fault_count),
        .count_saturated (count_saturated)
    );

    // ---- 5. Status packets over UART ----------------------------------------
    status_reporter u_reporter (
        .clk         (clk),
        .rst         (rst),
        .alarm_state (alarm_state),
        .value       (filtered_value[7:0]),
        .fault_count (fault_count),
        .tx_busy     (tx_busy),
        .tx_start    (tx_start),
        .tx_data     (tx_data)
    );

    uart_tx #(
        .CLKS_PER_BIT (CLKS_PER_BIT)
    ) u_uart (
        .clk      (clk),
        .rst      (rst),
        .tx_start (tx_start),
        .tx_data  (tx_data),
        .tx       (uart_txd),
        .tx_busy  (tx_busy)
    );

endmodule
