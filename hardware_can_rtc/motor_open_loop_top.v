`timescale 1ns/1ps

// Distinct offline candidate: encoder pins are not used or exported. The old
// 0x1B43 boot image is unchanged until a separate deliberate deployment.
module motor_open_loop_top (
    input wire [7:0] adc_data,
    input wire adc_busy, adc_first_data,
    output wire adc_reset, adc_convst_a, adc_convst_b, adc_cs_n, adc_rd_n,
    output wire pwm, AN1, AN2, STBY,
    output wire cam_mclk, cam_rst, cam_scl,
    inout wire cam_sda,
    input wire mipi_clk_hs_p,
    input wire [1:0] mipi_data_hs_p,
    input wire [1:0] mipi_data_lp_p,
    input wire [1:0] mipi_data_lp_n
);
    motor_soc_top #(.IMAGE_FEATURE_FLAGS(32'h0000_4143)) u_core (
        .encoder_a(1'b0), .encoder_b(1'b0),
        .adc_data(adc_data), .adc_busy(adc_busy),
        .adc_first_data(adc_first_data),
        .adc_reset(adc_reset), .adc_convst_a(adc_convst_a),
        .adc_convst_b(adc_convst_b), .adc_cs_n(adc_cs_n),
        .adc_rd_n(adc_rd_n), .pwm(pwm), .AN1(AN1),
        .AN2(AN2), .STBY(STBY),
        .cam_mclk(cam_mclk), .cam_rst(cam_rst),
        .cam_scl(cam_scl), .cam_sda(cam_sda),
        .mipi_clk_hs_p(mipi_clk_hs_p),
        .mipi_data_hs_p(mipi_data_hs_p),
        .mipi_data_lp_p(mipi_data_lp_p),
        .mipi_data_lp_n(mipi_data_lp_n)
    );
endmodule
