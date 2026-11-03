`timescale 1ns/1ps

// Opt-in, bounded-duty motor core for a separate guarded image. No encoder is
// sampled or used for startup, speed regulation, or fault qualification.
// Package outputs MUST also be gated by motor_run_guard in the parent top.
module motor_open_loop_core #(
    parameter integer DUTY_MIN_PERCENT = 10,
    parameter integer DUTY_MAX_PERCENT = 60,
    parameter integer PWM_PERIOD_CYCLES = 10_000,
    parameter integer RAMP_INTERVAL_CYCLES = 1_000_000
) (
    input  wire clk, resetn,
    input  wire [1:0] ctrl,
    input  wire [31:0] target,
    input  wire [7:0] adc_data,
    input  wire adc_busy, adc_first_data,
    output wire adc_reset, adc_convst_a, adc_convst_b, adc_cs_n, adc_rd_n,
    output wire [2:0] adc_os,
    output wire adc_range, adc_serial, adc_stby,
    output wire pwm, AN1, AN2, STBY,
    output wire [31:0] speed,
    output wire direction,
    output wire signed [31:0] current_mA,
    output wire signed [15:0] current_raw_code,
    output wire signed [15:0] vibration1_data, vibration2_data, vibration3_data,
    output wire data_valid,
    output wire [63:0] sample_ticks,
    output wire adc_error,
    output wire motor_fault,
    output wire [2:0] fault_code,
    output wire [6:0] debug_duty
);
    // Target is an integer duty percentage, NOT RPM or Q16.16 speed. A
    // distinct feature identity prevents old RPM scripts from arming this PL.
    // Only forward operation is supported; no encoder-dependent reversal.
    wire invalid_command = ctrl[1] ||
                           (target != 0 &&
                            (target < DUTY_MIN_PERCENT ||
                             target > DUTY_MAX_PERCENT));
    wire forward_request = ctrl == 2'b01 && target != 0 &&
                           !invalid_command;
    wire pwm_wave;
    reg [6:0] applied_duty;
    reg [31:0] ramp_phase;

    // Immediate zero on stop or invalid command. Raising/lowering a nonzero
    // request moves by at most one percentage point per 10 ms at 100 MHz.
    always @(posedge clk) begin
        if (!resetn || !forward_request) begin
            applied_duty <= 0;
            ramp_phase <= 0;
        end else if (ramp_phase == RAMP_INTERVAL_CYCLES - 1) begin
            ramp_phase <= 0;
            if (applied_duty < target[6:0])
                applied_duty <= applied_duty + 1'b1;
            else if (applied_duty > target[6:0])
                applied_duty <= applied_duty - 1'b1;
        end else begin
            ramp_phase <= ramp_phase + 1'b1;
        end
    end

    PWM #(.T(PWM_PERIOD_CYCLES - 1)) u_pwm (
        .clk(clk), .reset(resetn), .duty(applied_duty),
        .pwm(pwm_wave)
    );
    assign pwm = forward_request && pwm_wave;
    assign AN1 = forward_request;
    assign AN2 = 1'b0;
    assign STBY = forward_request;
    assign speed = 32'd0;  // No RPM claim without an encoder.
    assign direction = 1'b1;
    assign debug_duty = applied_duty;
    assign motor_fault = invalid_command;
    assign fault_code = {2'b00, invalid_command};

    data_collect #(
        .CLOCK_HZ(100_000_000), .SAMPLE_HZ(50_000),
        .RANGE_10V(1'b0), .CURRENT_ZERO_CODE(16_849),
        .CURRENT_SENSITIVITY_MV_PER_A(185), .CURRENT_CHANNEL(4)
    ) u_adc (
        .clk(clk), .reset(resetn), .adc_data(adc_data),
        .adc_busy(adc_busy), .adc_first_data(adc_first_data),
        .adc_reset(adc_reset), .adc_convst_a(adc_convst_a),
        .adc_convst_b(adc_convst_b), .adc_cs_n(adc_cs_n),
        .adc_rd_n(adc_rd_n), .adc_os(adc_os),
        .adc_range(adc_range), .adc_serial(adc_serial),
        .adc_stby(adc_stby), .current_mA(current_mA),
        .current_raw_code(current_raw_code),
        .vibration1_data(vibration1_data),
        .vibration2_data(vibration2_data),
        .vibration3_data(vibration3_data),
        .data_valid(data_valid), .sample_ticks(sample_ticks),
        .adc_error(adc_error)
    );

    // synthesis translate_off
    initial begin
        if (DUTY_MIN_PERCENT != 10 || DUTY_MAX_PERCENT != 60 ||
            PWM_PERIOD_CYCLES != 10_000 || RAMP_INTERVAL_CYCLES <= 0)
            $fatal(1, "open-loop duty/ramp parameters outside reviewed profile");
    end
    // synthesis translate_on
endmodule
