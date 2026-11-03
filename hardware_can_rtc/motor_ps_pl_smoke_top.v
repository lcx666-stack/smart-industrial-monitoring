`timescale 1ns/1ps

// Board-only PS/PL link test. No external PL pins or motor drive signals.
// Sensor status is deliberately zero; this is not a functional motor image.
module motor_ps_pl_smoke_top;
    wire        motor_clk;
    wire        motor_resetn;
    wire [31:0] motor_target;
    wire [1:0]  motor_ctrl;
    wire [9:0]  status_addr;
    wire [3:0]  status_web;
    wire        status_csb;
    wire [31:0] status_wdata;
    wire [31:0] status_rdata;

    system u_system (
        .motor_target (motor_target),
        .motor_ctrl   (motor_ctrl),
        .motor_clk    (motor_clk),
        .motor_resetn (motor_resetn),
        .status_addr  (status_addr),
        .status_web   (status_web),
        .status_csb   (status_csb),
        .status_wdata (status_wdata),
        .status_rdata (status_rdata)
    );

    motor_status_regs u_status (
        .clk             (motor_clk),
        .resetn          (motor_resetn),
        .mem_addr        (status_addr),
        .mem_web         (status_web),
        .mem_csb         (status_csb),
        .mem_din         (status_wdata),
        .mem_dout        (status_rdata),
        .speed           (32'd0),
        .current_mA      (32'sd0),
        .vibration1_data (16'sd0),
        .vibration2_data (16'sd0),
        .vibration3_data (16'sd0),
        .data_valid      (1'b0),
        .adc_error       (1'b0),
        .motor_fault     (1'b0),
        .fault_code      (3'd0),
        .direction       (1'b0),
        .motor_stby      (1'b0),
        .motor_an1       (1'b0),
        .motor_an2       (1'b0),
        .motor_target    (motor_target),
        .motor_ctrl      (motor_ctrl),
        .trial_status    (32'd0)
    );
endmodule
