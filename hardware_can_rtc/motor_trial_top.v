`timescale 1ns/1ps

// Short, one-shot motor bench trial. Unlike motor_soc_top, this top never
// exposes unguarded motor-controller outputs to package pins.
module motor_trial_top (
    input  wire        encoder_a,
    input  wire        encoder_b,
    output wire        motor_pwma,
    output wire        motor_ain1,
    output wire        motor_ain2,
    output wire        motor_stby,
    input  wire [7:0]  adc_data,
    input  wire        adc_busy,
    input  wire        adc_first_data,
    output wire        adc_reset,
    output wire        adc_convst_a,
    output wire        adc_convst_b,
    output wire        adc_cs_n,
    output wire        adc_rd_n
);
    wire clk, resetn;
    wire [31:0] motor_target;
    wire [1:0] motor_ctrl;
    wire [9:0] status_addr;
    wire [3:0] status_web;
    wire status_csb;
    wire [31:0] status_wdata, status_rdata;
    wire [31:0] speed;
    wire direction;
    wire signed [31:0] current_mA;
    wire signed [15:0] vibration1, vibration2, vibration3;
    wire data_valid, adc_error, core_fault;
    wire [2:0] core_fault_code;
    wire core_pwm, core_ain1, core_ain2, core_stby;
    wire [31:0] trial_status;
    wire [2:0] adc_os_unused;
    wire adc_range_unused, adc_serial_unused, adc_stby_unused;

    system u_system (
        .motor_target (motor_target),
        .motor_ctrl   (motor_ctrl),
        .motor_clk    (clk),
        .motor_resetn (resetn),
        .status_addr  (status_addr),
        .status_web   (status_web),
        .status_csb   (status_csb),
        .status_wdata (status_wdata),
        .status_rdata (status_rdata)
    );

    // Bit 5 explicitly marks that motor current is not sensed in this image.
    // Bit 4: guarded one-shot trial; bits 0/1: byte ADC/IN5.
    motor_status_regs #(.FEATURE_FLAGS(32'h0000_0033)) u_status (
        .clk             (clk),
        .resetn          (resetn),
        .mem_addr        (status_addr),
        .mem_web         (status_web),
        .mem_csb         (status_csb),
        .mem_din         (status_wdata),
        .mem_dout        (status_rdata),
        .speed           (speed),
        .current_mA      (current_mA),
        .vibration1_data (vibration1),
        .vibration2_data (vibration2),
        .vibration3_data (vibration3),
        .data_valid      (data_valid),
        .adc_error       (adc_error),
        .motor_fault     (core_fault | (|trial_status[5:2])),
        .fault_code      (core_fault_code),
        .direction       (direction),
        .motor_stby      (motor_stby),
        .motor_an1       (motor_ain1),
        .motor_an2       (motor_ain2),
        .motor_target    (motor_target),
        .motor_ctrl      (motor_ctrl),
        .trial_status    (trial_status)
    );

    motor #(
        .ADC_CURRENT_CHANNEL(4),
        .ADC_CURRENT_ZERO_CODE(16_849)
    ) u_motor (
        .clk             (clk),
        .reset           (resetn),
        .ctrl            (motor_ctrl),
        .Target          (motor_target),
        .encoder_a       (encoder_a),
        .encoder_b       (encoder_b),
        .direction       (direction),
        .pwm             (core_pwm),
        .AN1             (core_ain1),
        .AN2             (core_ain2),
        .STBY            (core_stby),
        .speed           (speed),
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
        .vibration1_data (vibration1),
        .vibration2_data (vibration2),
        .vibration3_data (vibration3),
        .data_valid      (data_valid),
        .adc_error       (adc_error),
        .motor_fault     (core_fault),
        .fault_code      (core_fault_code)
    );

    motor_trial_guard #(.CURRENT_SENSE_ENABLED(0)) u_guard (
        .clk           (clk),
        .resetn        (resetn),
        .mem_addr      (status_addr),
        .mem_web       (status_web),
        .mem_csb       (status_csb),
        .mem_din       (status_wdata),
        .motor_target  (motor_target),
        .motor_ctrl    (motor_ctrl),
        .current_mA    (current_mA),
        .data_valid    (data_valid),
        .adc_error     (adc_error),
        .core_fault    (core_fault),
        .core_ain1     (core_ain1),
        .core_ain2     (core_ain2),
        .core_stby     (core_stby),
        .motor_pwma    (motor_pwma),
        .motor_ain1    (motor_ain1),
        .motor_ain2    (motor_ain2),
        .motor_stby    (motor_stby),
        .status_word   (trial_status)
    );
endmodule
