`timescale 1ns/1ps

// Board candidate: same protected 0x4143 motor/CS500 feature configuration
// and motor/camera pin mapping as the previously booted DSI wrapper. The
// unlit DSI pins are omitted so Ethernet remains the display transport.
module motor_camera_npu_eth_top (
    input wire [7:0] adc_data,
    input wire adc_busy, adc_first_data,
    output wire adc_reset, adc_convst_a, adc_convst_b, adc_cs_n, adc_rd_n,
    output wire pwm, AN1, AN2, STBY,
    output wire cam_mclk, cam_rst, cam_scl,
    inout wire cam_sda,
    inout wire rtc_scl, rtc_sda,
    input wire mipi_clk_hs_p,
    input wire [1:0] mipi_data_hs_p,
    input wire [1:0] mipi_data_lp_p,
    input wire [1:0] mipi_data_lp_n
);
    wire rtc_scl_oe, rtc_sda_oe;
    wire rtc_scl_in = rtc_scl;
    wire rtc_sda_in = rtc_sda;
    assign rtc_scl = rtc_scl_oe ? 1'b0 : 1'bz;
    assign rtc_sda = rtc_sda_oe ? 1'b0 : 1'bz;

    motor_soc_top #(
        .IMAGE_FEATURE_FLAGS(32'h0000_4143), .DUTY_MIN_PERCENT(10), .ENABLE_DSI(0)
    ) u_core (
        .encoder_a(1'b0), .encoder_b(1'b0),
        .adc_data(adc_data), .adc_busy(adc_busy),
        .adc_first_data(adc_first_data),
        .adc_reset(adc_reset), .adc_convst_a(adc_convst_a),
        .adc_convst_b(adc_convst_b), .adc_cs_n(adc_cs_n),
        .adc_rd_n(adc_rd_n), .pwm(pwm), .AN1(AN1),
        .AN2(AN2), .STBY(STBY),
        .cam_mclk(cam_mclk), .cam_rst(cam_rst),
        .cam_scl(cam_scl), .cam_sda(cam_sda),
        .rtc_scl_in(rtc_scl_in), .rtc_sda_in(rtc_sda_in),
        .rtc_scl_oe(rtc_scl_oe), .rtc_sda_oe(rtc_sda_oe),
        .mipi_clk_hs_p(mipi_clk_hs_p),
        .mipi_data_hs_p(mipi_data_hs_p),
        .mipi_data_lp_p(mipi_data_lp_p),
        .mipi_data_lp_n(mipi_data_lp_n),
        .O_clk_hs_p(),
        .O_clk_lp_p(), .O_clk_lp_n(),
        .O_data_hs_p(),
        .O_data_lp_p(),
        .O_data_lp_n()
    );
endmodule
