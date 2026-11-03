`timescale 1ns/1ps

// ADC-only board test. The motor is not instantiated or driven.
// J8 static configuration pins are hardwired on the ADC module, not FPGA pins.
module adc_soc_test_top (
    input  wire [7:0]  adc_data,
    input  wire        adc_busy,
    input  wire        adc_first_data,
    output wire        adc_reset,
    output wire        adc_convst_a,
    output wire        adc_convst_b,
    output wire        adc_cs_n,
    output wire        adc_rd_n
);
    wire        pl_clk;
    wire        pl_resetn;
    wire [31:0] motor_target_unused;
    wire [1:0]  motor_ctrl_unused;
    wire [9:0]  status_addr;
    wire [3:0]  status_web;
    wire        status_csb;
    wire [31:0] status_wdata;
    wire [31:0] status_rdata;

    wire [2:0]  adc_os_unused;
    wire        adc_range_unused;
    wire        adc_serial_unused;
    wire        adc_stby_unused;
    wire signed [31:0] current_mA;
    wire signed [15:0] current_raw_code;
    wire signed [15:0] vibration1_data;
    wire signed [15:0] vibration2_data;
    wire signed [15:0] vibration3_data;
    wire        data_valid;
    wire        adc_error;

    system u_system (
        .motor_target (motor_target_unused),
        .motor_ctrl   (motor_ctrl_unused),
        .motor_clk    (pl_clk),
        .motor_resetn (pl_resetn),
        .status_addr  (status_addr),
        .status_web   (status_web),
        .status_csb   (status_csb),
        .status_wdata (status_wdata),
        .status_rdata (status_rdata)
    );

    data_collect #(
        .CLOCK_HZ (100_000_000),
        .SAMPLE_HZ(50_000),
        .RANGE_10V(1'b0),
        .CURRENT_CHANNEL(4) // Diagnostic: ACS712 AO on AD7606 IN5
    ) u_adc (
        .clk             (pl_clk),
        .reset           (pl_resetn),
        .adc_data        (adc_data),
        .adc_busy        (adc_busy),
        .adc_first_data  (adc_first_data),
        .adc_reset       (adc_reset),
        .adc_convst_a    (adc_convst_a),
        .adc_convst_b    (adc_convst_b),
        .adc_cs_n        (adc_cs_n),
        .adc_rd_n        (adc_rd_n),
        .adc_os          (adc_os_unused),
        .adc_range       (adc_range_unused),
        .adc_serial      (adc_serial_unused),
        .adc_stby        (adc_stby_unused),
        .current_mA      (current_mA),
        .current_raw_code(current_raw_code),
        .vibration1_data (vibration1_data),
        .vibration2_data (vibration2_data),
        .vibration3_data (vibration3_data),
        .data_valid      (data_valid),
        .adc_error       (adc_error)
    );

    // Bit 0: 8-bit bus; bit 1: IN5 current; bit 2: raw IN5 code in
    // the otherwise unused ADC-only snapshot speed register (0x14).
    motor_status_regs #(.FEATURE_FLAGS(32'h0000_0007)) u_status (
        .clk             (pl_clk),
        .resetn          (pl_resetn),
        .mem_addr        (status_addr),
        .mem_web         (status_web),
        .mem_csb         (status_csb),
        .mem_din         (status_wdata),
        .mem_dout        (status_rdata),
        .speed           ({{16{current_raw_code[15]}}, current_raw_code}),
        .current_mA      (current_mA),
        .vibration1_data (vibration1_data),
        .vibration2_data (vibration2_data),
        .vibration3_data (vibration3_data),
        .data_valid      (data_valid),
        .adc_error       (adc_error),
        .motor_fault     (1'b0),
        .fault_code      (3'd0),
        .direction       (1'b0),
        .motor_stby      (1'b0),
        .motor_an1       (1'b0),
        .motor_an2       (1'b0),
        .motor_target    (motor_target_unused),
        .motor_ctrl      (motor_ctrl_unused),
        .trial_status    (32'd0)
    );
endmodule
