`timescale 1ns/1ps

// CS500/VID005 receive-only front end, adapted from the user's Milianke DR1
// 07_mipi_HDMI reference. No DDR write or motor-control logic lives here.
module cs500_capture_frontend (
    input  wire       clk_100m,
    input  wire       resetn,
    output wire       cam_mclk,
    output wire       cam_rst,
    output wire       cam_scl,
    inout  wire       cam_sda,
    input  wire       mipi_clk_hs_p,
    input  wire [1:0] mipi_data_hs_p,
    input  wire [1:0] mipi_data_lp_p,
    input  wire [1:0] mipi_data_lp_n,
    output wire       pixel_clk,
    output wire       pll_locked,
    output wire       sensor_configured,
    output wire       sensor_i2c_error,
    output wire       sensor_cfg_done_raw,
    output wire       sensor_wait_done,
    output wire [12:0] link_diag_seen,
    output wire [9:0] packet_type_seen,
    output wire [8:0] first_nonshort_header,
    output wire [1:0] lane_error,
    output wire [127:0] pixel_data,
    output wire       pixel_valid,
    output wire       pixel_frame_start,
    output wire       pixel_line_end
);
    wire clk_68m, clk_24m;
    wire sensor_ae_done;
    wire sensor_cfg_done;
    assign sensor_cfg_done_raw = sensor_cfg_done;
    reg [1:0] sensor_config_pixel_sync = 0;
    wire [15:0] hs_data;
    wire hs_valid;
    wire csi_start, csi_end, csi_valid;
    wire [31:0] csi_data;
    wire raw_start, raw_end, raw_valid;
    wire [39:0] raw_data;
    wire axis_valid, axis_user, axis_last;
    wire [39:0] axis_data;
    wire [127:0] isp_data;
    wire isp_valid, isp_user, isp_last;
    // Sticky stage observations are diagnostic only; they never enable DMA or
    // alter motor control. Bit 0 proves a recovered pixel clock exists.
    reg [11:0] pixel_stage_seen = 0;
    reg [1:0] lane_error_seen_pixel = 0;
    reg hs_valid_previous = 0;
    reg [7:0] packet_type_seen_r = 0;
    reg first_nonshort_valid = 0;
    reg [7:0] first_nonshort_id = 0;
    // Assert promptly if PS reset or PLL lock drops; release separately on
    // each derived clock. This avoids crossing the PS reset release directly
    // into the 24 MHz, 68 MHz and recovered MIPI pixel-clock domains.
    wire capture_async_resetn = resetn & pll_locked;
    reg [2:0] reset_sync_24 = 0;
    reg [2:0] reset_sync_68 = 0;
    reg [2:0] reset_sync_pixel = 0;
    wire resetn_24 = reset_sync_24[2];
    wire resetn_68 = reset_sync_68[2];
    wire resetn_pixel = reset_sync_pixel[2];

    always @(posedge clk_24m or negedge capture_async_resetn) begin
        if (!capture_async_resetn) reset_sync_24 <= 0;
        else reset_sync_24 <= {reset_sync_24[1:0], 1'b1};
    end
    always @(posedge clk_68m or negedge capture_async_resetn) begin
        if (!capture_async_resetn) reset_sync_68 <= 0;
        else reset_sync_68 <= {reset_sync_68[1:0], 1'b1};
    end
    always @(posedge pixel_clk or negedge capture_async_resetn) begin
        if (!capture_async_resetn) reset_sync_pixel <= 0;
        else reset_sync_pixel <= {reset_sync_pixel[1:0], 1'b1};
    end
    always @(posedge pixel_clk or negedge resetn_pixel) begin
        if (!resetn_pixel) sensor_config_pixel_sync <= 0;
        else sensor_config_pixel_sync <=
            {sensor_config_pixel_sync[0], sensor_configured};
    end
    always @(posedge pixel_clk or negedge resetn_pixel) begin
        if (!resetn_pixel) pixel_stage_seen <= 0;
        else pixel_stage_seen <= pixel_stage_seen |
            {pixel_valid, pixel_frame_start, isp_valid, isp_user,
             axis_valid, axis_user, raw_valid, raw_start,
             csi_valid, csi_start, hs_valid, 1'b1};
    end
    always @(posedge pixel_clk or negedge resetn_pixel) begin
        if (!resetn_pixel) lane_error_seen_pixel <= 0;
        else lane_error_seen_pixel <= lane_error_seen_pixel | lane_error;
    end
    assign link_diag_seen = {|lane_error_seen_pixel, pixel_stage_seen};
    // CSI-2 Data ID is the first byte of every HS packet. The low six bits
    // are the data type; the upper two bits are the virtual channel. We only
    // latch categories, not payload data or image bytes.
    always @(posedge pixel_clk or negedge resetn_pixel) begin
        if (!resetn_pixel) begin
            hs_valid_previous <= 0;
            packet_type_seen_r <= 0;
            first_nonshort_valid <= 0;
            first_nonshort_id <= 0;
        end else begin
            hs_valid_previous <= hs_valid;
            if (hs_valid && !hs_valid_previous) begin
                if (!first_nonshort_valid && hs_data[13:8] > 6'h03) begin
                    first_nonshort_valid <= 1;
                    first_nonshort_id <= hs_data[15:8];
                end
                if (|hs_data[15:14]) packet_type_seen_r[6] <= 1;
                case (hs_data[13:8])
                    6'h00: packet_type_seen_r[0] <= 1; // frame start
                    6'h01: packet_type_seen_r[1] <= 1; // frame end
                    6'h2a: packet_type_seen_r[2] <= 1; // RAW8
                    6'h2b: packet_type_seen_r[3] <= 1; // RAW10
                    6'h2c: packet_type_seen_r[4] <= 1; // RAW12
                    6'h12: packet_type_seen_r[5] <= 1; // embedded data
                    default: packet_type_seen_r[7] <= 1;
                endcase
            end
        end
    end
    assign packet_type_seen = {lane_error_seen_pixel, packet_type_seen_r};
    assign first_nonshort_header = {first_nonshort_valid, first_nonshort_id};

    pll u_camera_pll (
        .refclk(clk_100m), .reset(~resetn), .lock(pll_locked),
        .clk0_out(), .clk1_out(), .clk2_out(clk_68m), .clk3_out(clk_24m)
    );
    DR1_LOGIC_ODDR u_camera_mclk (
        .q(cam_mclk), .clk(clk_24m),
        .d0(1'b1), .d1(1'b0), .rst(~pll_locked)
    );
    assign cam_rst = pll_locked;

    uicfgcs500 #(.CLK_DIV(24_000_000 / 100_000 - 1)) u_sensor_config (
        .I_clk(clk_24m), .I_rst_n(resetn_24),
        .I_ae_req(1'b0), .I_ae(16'd3000), .I_ag(16'd60),
        .O_cam_scl(cam_scl), .IO_cam_sda(cam_sda),
        .O_cfg_done(sensor_cfg_done), .O_ae_cfg_done(sensor_ae_done),
        .O_iic_error(sensor_i2c_error), .O_wait_done(sensor_wait_done)
    );
    assign sensor_configured = sensor_cfg_done && !sensor_i2c_error;

    mipi_dphy_rx_over_lvds_wrapper #(.DEVICE("DR1"), .LANE_NUM(2)) u_mipi (
        .I_lp_clk(clk_68m), .I_rst(~resetn_68),
        .I_mipi_clk_p(mipi_clk_hs_p),
        .I_mipi_data_hs_p(mipi_data_hs_p),
        .I_mipi_data_lp_p(mipi_data_lp_p),
        .I_mipi_data_lp_n(mipi_data_lp_n),
        .I_lane_hs_invert(2'b00), .I_lane_lp_invert(2'b00),
        .O_hs_rx_clk(pixel_clk), .O_hs_rx_valid(hs_valid),
        .O_hs_rx_data(hs_data), .O_lp_rx_lane0_p(),
        .O_lp_rx_lane0_n(), .O_lane_error(lane_error)
    );
    csi_unpacket_2lane u_csi (
        .I_clk(pixel_clk), .I_rst_n(resetn_pixel),
        .I_hs_valid(hs_valid), .I_hs_data(hs_data),
        .O_csi_frame_start(csi_start), .O_csi_frame_end(csi_end),
        .O_csi_valid(csi_valid), .O_csi_data(csi_data), .O_csi_hs()
    );
    raw10_unpacket_2lane u_raw10 (
        .I_clk(pixel_clk), .I_rst_n(resetn_pixel),
        .I_csi_frame_start(csi_start), .I_csi_frame_end(csi_end),
        .I_csi_valid(csi_valid), .I_csi_data(csi_data),
        .I_camera_black_level(10'd0),
        .O_raw10_frame_start(raw_start), .O_raw10_frame_end(raw_end),
        .O_raw10_valid(raw_valid), .O_raw10_data(raw_data)
    );
    uial2axis #(.IMG_WIDTH(1920), .IMG_HEIGHT(1080),
                .INPUT_DATA_WIDTH(40)) u_axis (
        .I_native_clk(pixel_clk), .I_rst_n(resetn_pixel),
        .I_data(raw_data), .I_data_valid(raw_valid),
        .I_data_start(raw_start), .I_data_end(raw_end),
        .axis_tvalid(axis_valid), .axis_tdata(axis_data),
        .axis_tuser(axis_user), .axis_tlast(axis_last)
    );
    isp_top u_isp (
        .axi4s_video_aclk(pixel_clk), .I_rst_n(resetn_pixel),
        .I_tlast(axis_last), .I_tuser(axis_user),
        .I_tdata(axis_data), .I_tvalid(axis_valid),
        .I_tdest(10'd0), .O_tready(1'b1),
        .O_tdata(isp_data), .O_tlast(isp_last),
        .O_tuser(isp_user), .O_tvalid(isp_valid), .I_tready()
    );

    assign pixel_data = isp_data;
    assign pixel_valid = isp_valid & sensor_config_pixel_sync[1];
    assign pixel_frame_start = isp_user & sensor_config_pixel_sync[1];
    assign pixel_line_end = isp_last & sensor_config_pixel_sync[1];
endmodule
