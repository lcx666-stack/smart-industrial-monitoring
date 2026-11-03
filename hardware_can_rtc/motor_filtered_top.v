`timescale 1ns/1ps

// Offline opt-in candidate, NOT the deployed 0x143 image. No extra package IO.
module motor_filtered_top (
    input wire encoder_a, encoder_b,
    input wire [7:0] adc_data,
    input wire adc_busy, adc_first_data,
    output wire adc_reset, adc_convst_a, adc_convst_b, adc_cs_n, adc_rd_n,
    output wire pwm, AN1, AN2, STBY
);
    motor_soc_top #(.IMAGE_FEATURE_FLAGS(32'h0000_0343), .ENCODER_FILTER_CYCLES(16)) u_core (
        .encoder_a(encoder_a), .encoder_b(encoder_b), .adc_data(adc_data),
        .adc_busy(adc_busy), .adc_first_data(adc_first_data), .adc_reset(adc_reset),
        .adc_convst_a(adc_convst_a), .adc_convst_b(adc_convst_b), .adc_cs_n(adc_cs_n),
        .adc_rd_n(adc_rd_n), .pwm(pwm), .AN1(AN1), .AN2(AN2), .STBY(STBY));
endmodule
