`timescale 1ns/1ps

// Offline-only pin/resource candidate for the matching 1024x600 panel.
// The DSI output is the vendor test pattern, NOT camera pixels or AI boxes.
// Never package this top as the user's final image.
module motor_camera_dsi_tpg_top (
    input wire [7:0] adc_data,
    input wire adc_busy, adc_first_data,
    output wire adc_reset, adc_convst_a, adc_convst_b, adc_cs_n, adc_rd_n,
    output wire pwm, AN1, AN2, STBY,
    output wire cam_mclk, cam_rst, cam_scl,
    inout wire cam_sda,
    input wire mipi_clk_hs_p,
    input wire [1:0] mipi_data_hs_p,
    input wire [1:0] mipi_data_lp_p,
    input wire [1:0] mipi_data_lp_n,
    output wire O_clk_hs_p, O_clk_lp_p, O_clk_lp_n,
    output wire [3:0] O_data_hs_p, O_data_lp_p, O_data_lp_n
);
    wire pl_clk, pl_resetn;
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
        .mipi_data_lp_n(mipi_data_lp_n),
        .diagnostic_clk(pl_clk), .diagnostic_resetn(pl_resetn)
    );
    dsi_panel_tpg u_panel_pattern (
        .I_clk(pl_clk), .I_rst_n(pl_resetn),
        .O_clk_hs_p(O_clk_hs_p),
        .O_clk_lp_p(O_clk_lp_p), .O_clk_lp_n(O_clk_lp_n),
        .O_data_hs_p(O_data_hs_p),
        .O_data_lp_p(O_data_lp_p),
        .O_data_lp_n(O_data_lp_n)
    );
endmodule
