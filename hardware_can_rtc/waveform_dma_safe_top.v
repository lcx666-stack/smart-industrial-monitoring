`timescale 1ns/1ps

// ADC/HP0 board-validation image. Motor driver and encoder pins do not exist
// at this package top; internal motor outputs cannot reach the TB6612 board.
// Feature bit 7 distinguishes this image from the motor-capable 0x43 image.
module waveform_dma_safe_top (
    input  wire [7:0] adc_data,
    input  wire adc_busy,
    input  wire adc_first_data,
    output wire adc_reset,
    output wire adc_convst_a,
    output wire adc_convst_b,
    output wire adc_cs_n,
    output wire adc_rd_n
);
    wire unused_pwm, unused_an1, unused_an2, unused_stby;

    motor_soc_top #(.IMAGE_FEATURE_FLAGS(32'h0000_00c3)) u_core (
        .encoder_a(1'b0), .encoder_b(1'b0),
        .adc_data(adc_data), .adc_busy(adc_busy),
        .adc_first_data(adc_first_data), .adc_reset(adc_reset),
        .adc_convst_a(adc_convst_a), .adc_convst_b(adc_convst_b),
        .adc_cs_n(adc_cs_n), .adc_rd_n(adc_rd_n),
        .pwm(unused_pwm), .AN1(unused_an1),
        .AN2(unused_an2), .STBY(unused_stby)
    );
endmodule
