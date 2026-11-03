`timescale 1ns/1ps

// Top-level wrapper for the generated PS system and the PL motor/ADC logic.
// Add this file to the TD project and select motor_soc_top as the top module.
// Do not edit system/hdl/system.v: Design Integrator regenerates that file.
module motor_soc_top_can #(
    parameter [31:0] IMAGE_FEATURE_FLAGS = 32'h0000_0043,
    parameter integer ENCODER_FILTER_CYCLES = 16,
    parameter integer DUTY_MIN_PERCENT = 10,
    parameter integer ENABLE_DSI = 0
) (
    input  wire        encoder_a,
    input  wire        encoder_b,

    input  wire [7:0]  adc_data,
    input  wire        adc_busy,
    input  wire        adc_first_data,
    output wire        adc_reset,
    output wire        adc_convst_a,
    output wire        adc_convst_b,
    output wire        adc_cs_n,
    output wire        adc_rd_n,
    output wire        pwm,
    output wire        AN1,
    output wire        AN2,
    output wire        STBY,
    output wire        cam_mclk,
    output wire        cam_rst,
    output wire        cam_scl,
    inout  wire        cam_sda,
    input wire rtc_scl_in,
    input wire rtc_sda_in,
    output wire rtc_scl_oe,
    output wire rtc_sda_oe,
    input  wire        mipi_clk_hs_p,
    input  wire [1:0]  mipi_data_hs_p,
    input  wire [1:0]  mipi_data_lp_p,
    input  wire [1:0]  mipi_data_lp_n,
    output wire        O_clk_hs_p,
    output wire        O_clk_lp_p,
    output wire        O_clk_lp_n,
    output wire [3:0]  O_data_hs_p,
    output wire [3:0]  O_data_lp_p,
    output wire [3:0]  O_data_lp_n,
    // Internal taps for opt-in non-motor loopback wrappers; not package pins.
    output wire        diagnostic_clk,
    output wire        diagnostic_resetn,
    input  wire        can0_rx_in,
    output wire        can0_tx_out
);

    wire        motor_clk;
    wire        motor_resetn;
    assign diagnostic_clk = motor_clk;
    assign diagnostic_resetn = motor_resetn;
    wire [31:0] motor_target;
    wire [1:0]  motor_ctrl;

    // Status is read through the ERAM window (0x80000000). These are internal
    // FPGA nets, not new package pins. Full-rate sample DMA is a separate path.
    wire [9:0]  status_addr;
    wire [3:0]  status_web;
    wire        status_csb;
    wire [31:0] status_wdata;
    wire [31:0] status_rdata;
    wire [31:0] status_snapshot_rdata, status_dma_rdata, status_guard_rdata;
    wire [31:0] status_camera_rdata, status_display_rdata;
    wire [31:0] status_encoder_rdata;
    wire [31:0] status_trace_rdata;
    wire [31:0] status_observe_rdata;
    wire [1:0] qualified_ab, raw_ab;
    wire qualified_ready, raw_ready, raw_encoder_activity;
    wire [31:0] rejected_candidates;
    wire encoder_step_pl, encoder_invalid_pl;
    wire [6:0] debug_duty;
    wire decoder_a = IMAGE_FEATURE_FLAGS[14] ? 1'b0 :
                     (IMAGE_FEATURE_FLAGS[9] ? qualified_ab[1] : encoder_a);
    wire decoder_b = IMAGE_FEATURE_FLAGS[14] ? 1'b0 :
                     (IMAGE_FEATURE_FLAGS[9] ? qualified_ab[0] : encoder_b);
    wire drive_permit, guard_fault_pl;
    wire core_pwm, core_an1, core_an2, core_stby;
    wire [31:0]        speed_pl;
    wire               direction_pl;
    wire signed [31:0] current_mA_pl;
    wire signed [15:0] current_raw_pl;
    wire signed [15:0] vibration1_pl;
    wire signed [15:0] vibration2_pl;
    wire signed [15:0] vibration3_pl;
    wire               data_valid_pl;
    wire               adc_error_pl;
    wire               motor_fault_pl;
    wire combined_motor_fault = motor_fault_pl | guard_fault_pl;
    wire [2:0]         fault_code_pl;
    wire [32:0] dma_base;
    wire [31:0] dma_size, dma_consumed, dma_produced, dma_dropped, dma_seq;
    wire dma_start, dma_stop, dma_overflow, dma_error, dma_active, dma_busy;
    wire [1:0] dma_bresp;
    wire [4:0] dma_fifo_used;
    wire dma_irq_unused;
    wire [5:0] dma_awid, dma_bid;
    wire [32:0] dma_awaddr;
    wire [3:0] dma_awlen, dma_awcache, dma_awqos;
    wire [1:0] dma_awsize, dma_awburst, dma_bresp_bus;
    wire dma_awlock, dma_awvalid, dma_awready;
    wire [2:0] dma_awprot;
    wire [63:0] dma_wdata;
    wire [7:0] dma_wstrb;
    wire dma_wlast, dma_wvalid, dma_wready, dma_bvalid, dma_bready;
    wire [5:0] hp_awid, hp_bid;
    wire [32:0] hp_awaddr;
    wire [3:0] hp_awlen, hp_awcache, hp_awqos;
    wire [1:0] hp_awsize, hp_awburst, hp_bresp;
    wire hp_awlock, hp_awvalid, hp_awready;
    wire [2:0] hp_awprot;
    wire [63:0] hp_wdata;
    wire [7:0] hp_wstrb;
    wire hp_wlast, hp_wvalid, hp_wready, hp_bvalid, hp_bready;
    wire [5:0] cam_awid, cam_bid;
    wire [32:0] cam_awaddr;
    wire [3:0] cam_awlen, cam_awcache, cam_awqos;
    wire [1:0] cam_awsize, cam_awburst, cam_bresp;
    wire cam_awlock, cam_awvalid, cam_awready;
    wire [2:0] cam_awprot;
    wire [63:0] cam_wdata;
    wire [7:0] cam_wstrb;
    wire cam_wlast, cam_wvalid, cam_wready, cam_bvalid, cam_bready;
    wire [31:0] camera_frame_base;
    wire camera_start, camera_clear, camera_mode;
    wire camera_done, camera_fdma_busy, camera_fifo_full, camera_response_error;
    wire camera_rejected_start, camera_pll_locked, camera_sensor_configured;
    wire camera_i2c_error, camera_cfg_done_raw, camera_wait_done;
    wire [12:0] camera_link_diag;
    wire [9:0] camera_packet_diag;
    wire [8:0] camera_first_header;
    wire camera_pixel_clk, camera_pixel_valid, camera_pixel_fs, camera_pixel_last;
    wire [31:0] camera_sensor_frame_count;
    wire [127:0] camera_pixel_data;
    wire [1:0] camera_lane_error;
    wire arbiter_error, arbiter_busy;
    wire [5:0] display_arid, display_rid;
    wire [32:0] display_araddr;
    wire [3:0] display_arlen, display_arcache, display_arqos;
    wire [1:0] display_arsize, display_arburst, display_rresp;
    wire display_arlock, display_arvalid, display_arready;
    wire [2:0] display_arprot;
    wire [63:0] display_rdata;
    wire display_rlast, display_rvalid, display_rready;
    wire [63:0] sample_ticks_pl;
    // The module's mode/range/standby straps are hardwired, not FPGA outputs.
    wire [2:0]         adc_os_unused;
    wire               adc_range_unused;
    wire               adc_serial_unused;
    wire               adc_stby_unused;

    system u_system (
        .can0_rx_in(can0_rx_in),
        .can0_tx_out(can0_tx_out),
        .i2c1_scl_in(rtc_scl_in), .i2c1_sda_in(rtc_sda_in),
        .i2c1_scl_oe(rtc_scl_oe), .i2c1_sda_oe(rtc_sda_oe),
        .motor_target (motor_target),
        .motor_ctrl   (motor_ctrl),
        .motor_clk    (motor_clk),
        .motor_resetn (motor_resetn),
        .status_addr  (status_addr),
        .status_web   (status_web),
        .status_csb   (status_csb),
        .status_wdata (status_wdata),
        .status_rdata (status_rdata),
        .dma_awid      (hp_awid),
        .dma_awaddr    (hp_awaddr),
        .dma_awlen     (hp_awlen),
        .dma_awsize    (hp_awsize),
        .dma_awburst   (hp_awburst),
        .dma_awlock    (hp_awlock),
        .dma_awcache   (hp_awcache),
        .dma_awprot    (hp_awprot),
        .dma_awqos     (hp_awqos),
        .dma_awvalid   (hp_awvalid),
        .dma_awready   (hp_awready),
        .dma_wdata     (hp_wdata),
        .dma_wstrb     (hp_wstrb),
        .dma_wlast     (hp_wlast),
        .dma_wvalid    (hp_wvalid),
        .dma_wready    (hp_wready),
        .dma_bid       (hp_bid),
        .dma_bresp     (hp_bresp),
        .dma_bvalid    (hp_bvalid),
        .dma_bready    (hp_bready),
        .display_arid(display_arid), .display_araddr(display_araddr),
        .display_arlen(display_arlen), .display_arsize(display_arsize),
        .display_arburst(display_arburst), .display_arlock(display_arlock),
        .display_arcache(display_arcache), .display_arprot(display_arprot),
        .display_arqos(display_arqos), .display_arvalid(display_arvalid),
        .display_arready(display_arready), .display_rid(display_rid),
        .display_rdata(display_rdata), .display_rresp(display_rresp),
        .display_rlast(display_rlast), .display_rvalid(display_rvalid),
        .display_rready(display_rready)
    );

    cs500_capture_frontend u_camera_frontend (
        .clk_100m(motor_clk), .resetn(motor_resetn),
        .cam_mclk(cam_mclk), .cam_rst(cam_rst),
        .cam_scl(cam_scl), .cam_sda(cam_sda),
        .mipi_clk_hs_p(mipi_clk_hs_p),
        .mipi_data_hs_p(mipi_data_hs_p),
        .mipi_data_lp_p(mipi_data_lp_p),
        .mipi_data_lp_n(mipi_data_lp_n),
        .pixel_clk(camera_pixel_clk),
        .pll_locked(camera_pll_locked),
        .sensor_configured(camera_sensor_configured),
        .sensor_i2c_error(camera_i2c_error),
        .sensor_cfg_done_raw(camera_cfg_done_raw),
        .sensor_wait_done(camera_wait_done),
        .link_diag_seen(camera_link_diag),
        .packet_type_seen(camera_packet_diag),
        .first_nonshort_header(camera_first_header),
        .lane_error(camera_lane_error),
        .pixel_data(camera_pixel_data),
        .pixel_valid(camera_pixel_valid),
        .pixel_frame_start(camera_pixel_fs),
        .pixel_line_end(camera_pixel_last)
    );

    reg [1:0] camera_pll_sync, camera_sensor_sync, camera_full_sync;
    reg [1:0] camera_error_sync;
    reg [1:0] camera_cfg_sync, camera_wait_sync;
    reg [12:0] camera_link_sync1, camera_link_sync2;
    reg [9:0] camera_packet_sync1, camera_packet_sync2;
    reg [8:0] camera_first_sync1, camera_first_sync2;
    reg camera_full_sticky;
    always @(posedge motor_clk or negedge motor_resetn) begin
        if (!motor_resetn) begin
            camera_pll_sync <= 0;
            camera_sensor_sync <= 0;
            camera_full_sync <= 0;
            camera_error_sync <= 0;
            camera_cfg_sync <= 0;
            camera_wait_sync <= 0;
            camera_link_sync1 <= 0;
            camera_link_sync2 <= 0;
            camera_packet_sync1 <= 0;
            camera_packet_sync2 <= 0;
            camera_first_sync1 <= 0;
            camera_first_sync2 <= 0;
            camera_full_sticky <= 0;
        end else begin
            camera_pll_sync <= {camera_pll_sync[0], camera_pll_locked};
            camera_sensor_sync <= {camera_sensor_sync[0], camera_sensor_configured};
            camera_full_sync <= {camera_full_sync[0], camera_fifo_full};
            camera_error_sync <= {camera_error_sync[0], camera_i2c_error};
            camera_cfg_sync <= {camera_cfg_sync[0], camera_cfg_done_raw};
            camera_wait_sync <= {camera_wait_sync[0], camera_wait_done};
            camera_link_sync1 <= camera_link_diag;
            camera_link_sync2 <= camera_link_sync1;
            camera_packet_sync1 <= camera_packet_diag;
            camera_packet_sync2 <= camera_packet_sync1;
            camera_first_sync1 <= camera_first_header;
            camera_first_sync2 <= camera_first_sync1;
            if (camera_start) camera_full_sticky <= 0;
            else if (camera_mode && !camera_done &&
                     (cam_awvalid || camera_fdma_busy) &&
                     camera_full_sync[1])
                camera_full_sticky <= 1;
        end
    end

    cs500_sensor_frame_counter u_camera_sensor_frame_counter (
        .pixel_clk(camera_pixel_clk), .register_clk(motor_clk),
        .resetn(motor_resetn), .pixel_frame_start(camera_pixel_fs),
        .frame_count(camera_sensor_frame_count)
    );

    cs500_capture_regs u_camera_regs (
        .clk(motor_clk), .resetn(motor_resetn),
        .mem_addr(status_addr), .mem_web(status_web),
        .mem_csb(status_csb), .mem_din(status_wdata),
        .mem_dout(status_camera_rdata),
        .motor_running(core_stby && drive_permit),
        .waveform_dma_active(dma_active),
        .sensor_configured(camera_sensor_sync[1]),
        .sensor_i2c_error(camera_error_sync[1]),
        .sensor_cfg_done_raw(camera_cfg_sync[1]),
        .sensor_wait_done(camera_wait_sync[1]),
        .link_diag_seen(camera_link_sync2),
        .packet_type_seen(camera_packet_sync2),
        .first_nonshort_header(camera_first_sync2),
        .sensor_frame_count(camera_sensor_frame_count),
        .pll_locked(camera_pll_sync[1]),
        .frame_done(camera_done),
        .frame_writer_busy(camera_fdma_busy),
        .fifo_full(camera_full_sticky),
        .response_error(camera_response_error | arbiter_error),
        .frame_base(camera_frame_base),
        .capture_mode(camera_mode),
        .start_pulse(camera_start), .clear_pulse(camera_clear),
        .rejected_start(camera_rejected_start)
    );

    cs500_frame_writer u_camera_writer (
        .clk_axi(motor_clk), .resetn(motor_resetn),
        .pixel_clk(camera_pixel_clk),
        .pixel_data(camera_pixel_data),
        .pixel_valid(camera_pixel_valid),
        .pixel_frame_start(camera_pixel_fs),
        .frame_base(camera_frame_base),
        .start_pulse(camera_start), .clear_pulse(camera_clear),
        .frame_done(camera_done), .fdma_busy(camera_fdma_busy),
        .fifo_full(camera_fifo_full),
        .response_error(camera_response_error),
        .m_awid(cam_awid), .m_awaddr(cam_awaddr),
        .m_awlen(cam_awlen), .m_awsize(cam_awsize),
        .m_awburst(cam_awburst), .m_awlock(cam_awlock),
        .m_awcache(cam_awcache), .m_awprot(cam_awprot),
        .m_awqos(cam_awqos), .m_awvalid(cam_awvalid),
        .m_awready(cam_awready), .m_wdata(cam_wdata),
        .m_wstrb(cam_wstrb), .m_wlast(cam_wlast),
        .m_wvalid(cam_wvalid), .m_wready(cam_wready),
        .m_bid(cam_bid), .m_bresp(cam_bresp),
        .m_bvalid(cam_bvalid), .m_bready(cam_bready)
    );

    axi_write_burst_arbiter u_write_arbiter (
        .clk(motor_clk), .resetn(motor_resetn),
        .m_awvalid({cam_awvalid, dma_awvalid}),
        .m_awready({cam_awready, dma_awready}),
        .m_awid({cam_awid, dma_awid}),
        .m_awaddr({cam_awaddr, dma_awaddr}),
        .m_awlen({cam_awlen, dma_awlen}),
        .m_awsize({cam_awsize, dma_awsize}),
        .m_awburst({cam_awburst, dma_awburst}),
        .m_awlock({cam_awlock, dma_awlock}),
        .m_awcache({cam_awcache, dma_awcache}),
        .m_awprot({cam_awprot, dma_awprot}),
        .m_awqos({cam_awqos, dma_awqos}),
        .m_wvalid({cam_wvalid, dma_wvalid}),
        .m_wready({cam_wready, dma_wready}),
        .m_wdata({cam_wdata, dma_wdata}),
        .m_wstrb({cam_wstrb, dma_wstrb}),
        .m_wlast({cam_wlast, dma_wlast}),
        .m_bvalid({cam_bvalid, dma_bvalid}),
        .m_bready({cam_bready, dma_bready}),
        .m_bid({cam_bid, dma_bid}),
        .m_bresp({cam_bresp, dma_bresp_bus}),
        .s_awid(hp_awid), .s_awaddr(hp_awaddr),
        .s_awlen(hp_awlen), .s_awsize(hp_awsize),
        .s_awburst(hp_awburst), .s_awlock(hp_awlock),
        .s_awcache(hp_awcache), .s_awprot(hp_awprot),
        .s_awqos(hp_awqos), .s_awvalid(hp_awvalid),
        .s_awready(hp_awready), .s_wdata(hp_wdata),
        .s_wstrb(hp_wstrb), .s_wlast(hp_wlast),
        .s_wvalid(hp_wvalid), .s_wready(hp_wready),
        .s_bid(hp_bid), .s_bresp(hp_bresp),
        .s_bvalid(hp_bvalid), .s_bready(hp_bready),
        .protocol_error(arbiter_error), .busy(arbiter_busy)
    );

    generate
        if (ENABLE_DSI != 0) begin : g_dsi_display
            wire panel_pixel_clk, panel_vsync, panel_de, panel_configured;
            wire [31:0] requested_display_base, active_display_base;
            wire display_enable, display_rejected, reader_armed;
            wire display_busy, display_error, display_pixel_valid;
            wire [31:0] display_error_detail, display_first_araddr;
            wire [31:0] display_pixel_bgra;
            reg [1:0] panel_ready_sync;
            reg [2:0] panel_vsync_sync;
            wire panel_vsync_pulse = panel_vsync_sync[1] &&
                                     !panel_vsync_sync[2];
            always @(posedge motor_clk or negedge motor_resetn) begin
                if (!motor_resetn) begin
                    panel_ready_sync <= 0;
                    panel_vsync_sync <= 0;
                end else begin
                    panel_ready_sync <= {panel_ready_sync[0], panel_configured};
                    panel_vsync_sync <= {panel_vsync_sync[1:0], panel_vsync};
                end
            end

            dsi_panel_rgb u_panel (
                .I_clk(motor_clk), .I_rst_n(motor_resetn),
                .I_rgb24(display_pixel_valid ? display_pixel_bgra[23:0] : 24'd0),
                .O_pixel_clk(panel_pixel_clk),
                .O_vsync(panel_vsync), .O_de(panel_de),
                .O_panel_configured(panel_configured),
                .O_clk_hs_p(O_clk_hs_p),
                .O_clk_lp_p(O_clk_lp_p), .O_clk_lp_n(O_clk_lp_n),
                .O_data_hs_p(O_data_hs_p),
                .O_data_lp_p(O_data_lp_p),
                .O_data_lp_n(O_data_lp_n)
            );
            dsi_display_regs u_display_regs (
                .clk(motor_clk), .resetn(motor_resetn),
                .mem_addr(status_addr), .mem_web(status_web),
                .mem_csb(status_csb), .mem_din(status_wdata),
                .mem_dout(status_display_rdata),
                .panel_ready(panel_ready_sync[1]),
                .read_busy(display_busy), .reader_armed(reader_armed),
                .read_error(display_error),
                .read_error_detail(display_error_detail),
                .first_araddr(display_first_araddr),
                .active_frame_base(active_display_base),
                .vsync_pulse(panel_vsync_pulse),
                .requested_frame_base(requested_display_base),
                .display_enable(display_enable),
                .rejected_enable(display_rejected)
            );
            dsi_frame_reader u_display_reader (
                .clk_axi(motor_clk), .resetn(motor_resetn),
                .pixel_clk(panel_pixel_clk),
                .panel_vsync(panel_vsync), .panel_de(panel_de),
                .display_enable(display_enable),
                .requested_frame_base(requested_display_base),
                .active_frame_base(active_display_base),
                .armed(reader_armed), .read_busy(display_busy),
                .read_error(display_error),
                .read_error_detail(display_error_detail),
                .first_araddr(display_first_araddr),
                .pixel_bgra(display_pixel_bgra),
                .pixel_valid(display_pixel_valid),
                .m_arid(display_arid), .m_araddr(display_araddr),
                .m_arlen(display_arlen), .m_arsize(display_arsize),
                .m_arburst(display_arburst), .m_arlock(display_arlock),
                .m_arcache(display_arcache), .m_arprot(display_arprot),
                .m_arqos(display_arqos), .m_arvalid(display_arvalid),
                .m_arready(display_arready), .m_rid(display_rid),
                .m_rdata(display_rdata), .m_rresp(display_rresp),
                .m_rlast(display_rlast), .m_rvalid(display_rvalid),
                .m_rready(display_rready)
            );
        end else begin : g_no_dsi_display
            assign status_display_rdata = 32'd0;
            assign display_arid = 6'd0;
            assign display_araddr = 33'd0;
            assign display_arlen = 4'd0;
            assign display_arsize = 2'd0;
            assign display_arburst = 2'd0;
            assign display_arlock = 1'b0;
            assign display_arcache = 4'd0;
            assign display_arprot = 3'd0;
            assign display_arqos = 4'd0;
            assign display_arvalid = 1'b0;
            assign display_rready = 1'b0;
            assign O_clk_hs_p = 1'b0;
            assign O_clk_lp_p = 1'b0;
            assign O_clk_lp_n = 1'b0;
            assign O_data_hs_p = 4'd0;
            assign O_data_lp_p = 4'd0;
            assign O_data_lp_n = 4'd0;
        end
    endgenerate

    // Existing status ABI remains at 0x00..0x58; DMA registers occupy 0x80+.
    assign status_rdata = status_snapshot_rdata | status_dma_rdata | status_guard_rdata |
                          status_encoder_rdata | status_trace_rdata |
                          status_observe_rdata | status_camera_rdata |
                          status_display_rdata;
    assign pwm = drive_permit ? core_pwm : 1'b0;
    assign AN1 = drive_permit ? core_an1 : 1'b0;
    assign AN2 = drive_permit ? core_an2 : 1'b0;
    assign STBY = drive_permit ? core_stby : 1'b0;
    generate
        if (IMAGE_FEATURE_FLAGS[11]) begin : g_encoder_observe
            motor_encoder_observe u_observe (
                .clk(motor_clk), .resetn(motor_resetn), .mem_addr(status_addr),
                .mem_web(status_web), .mem_csb(status_csb), .mem_dout(status_observe_rdata),
                .raw_ab(raw_ab), .qualified_ab(qualified_ab), .raw_ready(raw_ready),
                .qualified_ready(qualified_ready), .raw_activity(raw_encoder_activity),
                .encoder_step(encoder_step_pl), .encoder_invalid(encoder_invalid_pl),
                .core_fault(motor_fault_pl), .guard_fault(guard_fault_pl),
                .drive_permit(drive_permit), .pwm(pwm), .stby(STBY), .an1(AN1), .an2(AN2),
                .duty(debug_duty), .motor_ctrl(motor_ctrl));
        end else begin : g_no_encoder_observe
            assign status_observe_rdata=0;
        end
        if (IMAGE_FEATURE_FLAGS[9]) begin : g_filtered_encoder
            motor_encoder_filter #(.STABLE_CYCLES(ENCODER_FILTER_CYCLES)) u_filter (
                .clk(motor_clk), .resetn(motor_resetn),
                .encoder_a(encoder_a), .encoder_b(encoder_b),
                .raw_ab(raw_ab), .raw_ready(raw_ready), .raw_activity(raw_encoder_activity),
                .qualified_ab(qualified_ab), .qualified_ready(qualified_ready),
                .rejected_candidates(rejected_candidates));
            motor_encoder_trace #(.FILTER_CYCLES(ENCODER_FILTER_CYCLES)) u_trace (
                .clk(motor_clk), .resetn(motor_resetn), .mem_addr(status_addr),
                .mem_web(status_web), .mem_csb(status_csb), .mem_dout(status_trace_rdata),
                .raw_ab(raw_ab), .qualified_ab(qualified_ab), .raw_ready(raw_ready),
                .qualified_ready(qualified_ready), .raw_activity(raw_encoder_activity),
                .encoder_step(encoder_step_pl), .encoder_invalid(encoder_invalid_pl),
                .core_fault(motor_fault_pl), .guard_fault(guard_fault_pl),
                .drive_permit(drive_permit), .pwm(pwm), .stby(STBY), .an1(AN1), .an2(AN2),
                .duty(debug_duty), .motor_ctrl(motor_ctrl), .rejected_candidates(rejected_candidates));
        end else begin : g_raw_encoder
            assign qualified_ab=0;
            assign raw_ab=0;
            assign qualified_ready=1;
            assign raw_ready=0;
            assign raw_encoder_activity=0;
            assign rejected_candidates=0;
            assign status_trace_rdata=0;
        end
        if (IMAGE_FEATURE_FLAGS[8]) begin : g_run_guard
            if (IMAGE_FEATURE_FLAGS[14]) begin : g_no_encoder_diag
                motor_open_loop_status #(.DUTY_MIN_PERCENT(DUTY_MIN_PERCENT)) u_open_loop_status (
                    .clk(motor_clk), .resetn(motor_resetn),
                    .mem_addr(status_addr), .mem_web(status_web),
                    .mem_csb(status_csb), .applied_duty(debug_duty),
                    .mem_dout(status_encoder_rdata)
                );
            end else begin : g_encoder_diag
                motor_encoder_diag #(.INPUT_IS_QUALIFIED(IMAGE_FEATURE_FLAGS[9])) u_encoder_diag (
                    .clk(motor_clk), .resetn(motor_resetn),
                    .encoder_a(decoder_a), .encoder_b(decoder_b), .qualified_ready(qualified_ready),
                    .mem_addr(status_addr), .mem_web(status_web), .mem_csb(status_csb),
                    .mem_din(status_wdata), .mem_dout(status_encoder_rdata)
                );
            end
            motor_run_guard #(.REQUIRE_ENCODER_READY(IMAGE_FEATURE_FLAGS[9])) u_guard (
                .clk(motor_clk), .resetn(motor_resetn),
                .mem_addr(status_addr), .mem_web(status_web), .mem_csb(status_csb),
                .mem_din(status_wdata), .mem_dout(status_guard_rdata),
                .data_valid(data_valid_pl), .adc_error(adc_error_pl),
                .core_fault(motor_fault_pl), .current_mA(current_mA_pl),
                .encoder_ready(qualified_ready),
                .motor_ctrl(motor_ctrl), .motor_target(motor_target),
                .drive_permit(drive_permit), .guard_fault(guard_fault_pl)
            );
        end else begin : g_legacy_control
            assign drive_permit = 1'b1;
            assign guard_fault_pl = 1'b0;
            assign status_guard_rdata = 32'd0;
            assign status_encoder_rdata = 32'd0;
        end
    endgenerate
    // bit 0: AD7606 byte bus; bit 1: current IN5; bit 6: waveform DMA.
    motor_status_regs #(.FEATURE_FLAGS(IMAGE_FEATURE_FLAGS)) u_status (
        .clk             (motor_clk),
        .resetn          (motor_resetn),
        .mem_addr        (status_addr),
        .mem_web         (status_web),
        .mem_csb         (status_csb),
        .mem_din         (status_wdata),
        .mem_dout        (status_snapshot_rdata),
        .speed           (speed_pl),
        .current_mA      (current_mA_pl),
        .vibration1_data (vibration1_pl),
        .vibration2_data (vibration2_pl),
        .vibration3_data (vibration3_pl),
        .data_valid      (data_valid_pl),
        .adc_error       (adc_error_pl),
        .motor_fault     (combined_motor_fault),
        .fault_code      (fault_code_pl),
        .direction       (direction_pl),
        .motor_stby      (STBY),
        .motor_an1       (AN1),
        .motor_an2       (AN2),
        .motor_target    (motor_target),
        .motor_ctrl      (motor_ctrl),
        .trial_status    (32'd0)
    );

    motor_dma_regs u_dma_regs (
        .clk(motor_clk), .resetn(motor_resetn),
        .mem_addr(status_addr), .mem_web(status_web),
        .mem_csb(status_csb), .mem_din(status_wdata),
        .mem_dout(status_dma_rdata),
        .dma_base(dma_base), .dma_size(dma_size),
        .consumed_bytes(dma_consumed),
        .start_pulse(dma_start), .stop_pulse(dma_stop),
        .produced_bytes(dma_produced), .dropped_frames(dma_dropped),
        .frame_seq(dma_seq), .overflow_sticky(dma_overflow),
        .dma_error(dma_error), .last_bresp(dma_bresp),
        .active(dma_active), .busy(dma_busy), .fifo_used(dma_fifo_used)
    );

    motor_sample_dma u_dma (
        .clk(motor_clk), .reset(motor_resetn),
        .start_pulse(dma_start), .stop_pulse(dma_stop),
        .dma_base(dma_base), .dma_size(dma_size),
        .consumed_bytes(dma_consumed),
        .data_valid(data_valid_pl), .current_raw_code(current_raw_pl),
        .vibration1_data(vibration1_pl), .vibration2_data(vibration2_pl),
        .vibration3_data(vibration3_pl), .current_mA(current_mA_pl),
        .sample_ticks(sample_ticks_pl),
        .frame_flags({29'd0, adc_error_pl, combined_motor_fault, 1'b1}),
        .produced_bytes(dma_produced), .dropped_frames(dma_dropped),
        .frame_seq(dma_seq), .overflow_sticky(dma_overflow),
        .dma_error(dma_error), .last_bresp(dma_bresp),
        .active(dma_active), .busy(dma_busy),
        .irq_pulse(dma_irq_unused), .fifo_used(dma_fifo_used),
        .m_axi_awid(dma_awid), .m_axi_awaddr(dma_awaddr),
        .m_axi_awlen(dma_awlen), .m_axi_awsize(dma_awsize),
        .m_axi_awburst(dma_awburst), .m_axi_awlock(dma_awlock),
        .m_axi_awcache(dma_awcache), .m_axi_awprot(dma_awprot),
        .m_axi_awqos(dma_awqos), .m_axi_awvalid(dma_awvalid),
        .m_axi_awready(dma_awready), .m_axi_wdata(dma_wdata),
        .m_axi_wstrb(dma_wstrb), .m_axi_wlast(dma_wlast),
        .m_axi_wvalid(dma_wvalid), .m_axi_wready(dma_wready),
        .m_axi_bid(dma_bid), .m_axi_bresp(dma_bresp_bus),
        .m_axi_bvalid(dma_bvalid), .m_axi_bready(dma_bready)
    );

    generate
    if (IMAGE_FEATURE_FLAGS[14]) begin : g_open_loop_core
        // A separate image, not a bypass of the encoder fault in the old core.
        // Raw command reaches core_fault without a drive_permit feedback loop;
        // physical outputs are still gated by motor_run_guard above.
        motor_open_loop_core #(.DUTY_MIN_PERCENT(DUTY_MIN_PERCENT)) u_open_loop (
            .clk(motor_clk), .resetn(motor_resetn),
            .ctrl(motor_ctrl), .target(motor_target),
            .adc_data(adc_data), .adc_busy(adc_busy),
            .adc_first_data(adc_first_data),
            .adc_reset(adc_reset), .adc_convst_a(adc_convst_a),
            .adc_convst_b(adc_convst_b), .adc_cs_n(adc_cs_n),
            .adc_rd_n(adc_rd_n), .adc_os(adc_os_unused),
            .adc_range(adc_range_unused),
            .adc_serial(adc_serial_unused), .adc_stby(adc_stby_unused),
            .pwm(core_pwm), .AN1(core_an1), .AN2(core_an2),
            .STBY(core_stby), .speed(speed_pl),
            .direction(direction_pl), .current_mA(current_mA_pl),
            .current_raw_code(current_raw_pl),
            .vibration1_data(vibration1_pl),
            .vibration2_data(vibration2_pl),
            .vibration3_data(vibration3_pl),
            .data_valid(data_valid_pl), .sample_ticks(sample_ticks_pl),
            .adc_error(adc_error_pl), .motor_fault(motor_fault_pl),
            .fault_code(fault_code_pl), .debug_duty(debug_duty)
        );
    end else begin : g_encoder_motor_core
    // Provisional no-load zero from the 2026-09-29 cold-start measurement:
    // 383.6 mA nominal offset corresponds to ADC code about 16849 at +/-5 V.
    // This is telemetry calibration only, not a proven motor current limit.
    motor #(
        .ADC_CURRENT_CHANNEL(4),
        .ADC_CURRENT_ZERO_CODE(16_849),
        .ENCODER_INPUT_QUALIFIED(IMAGE_FEATURE_FLAGS[9]),
        .IMMEDIATE_START(IMAGE_FEATURE_FLAGS[9])
    ) u_motor (
        .clk             (motor_clk),
        .reset           (motor_resetn),
        .ctrl            (drive_permit ? motor_ctrl : 2'b00),
        .Target          (drive_permit ? motor_target : 32'd0),
        .encoder_a       (decoder_a),
        .encoder_b       (decoder_b),
        .qualified_ready (qualified_ready),
        .raw_activity    (raw_encoder_activity),
        .encoder_step_event(encoder_step_pl),
        .encoder_invalid_event(encoder_invalid_pl),
        .debug_duty      (debug_duty),
        .direction       (direction_pl),
        .pwm             (core_pwm),
        .AN1             (core_an1),
        .AN2             (core_an2),
        .STBY            (core_stby),
        .speed           (speed_pl),
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
        .current_mA      (current_mA_pl),
        .current_raw_code(current_raw_pl),
        .vibration1_data (vibration1_pl),
        .vibration2_data (vibration2_pl),
        .vibration3_data (vibration3_pl),
        .data_valid      (data_valid_pl),
        .sample_ticks    (sample_ticks_pl),
        .adc_error       (adc_error_pl),
        .motor_fault     (motor_fault_pl),
        .fault_code      (fault_code_pl)
    );
    end
    endgenerate

    // synthesis translate_off
    initial begin
        if (IMAGE_FEATURE_FLAGS[9] && !IMAGE_FEATURE_FLAGS[8])
            $fatal(1,"motor_soc_top: filtered encoder requires independent run guard");
        if (IMAGE_FEATURE_FLAGS[10] && (!IMAGE_FEATURE_FLAGS[9] || ENCODER_FILTER_CYCLES != 1))
            $fatal(1,"motor_soc_top: bypass identity requires the traced one-sample encoder path");
        if (IMAGE_FEATURE_FLAGS[11] && !(IMAGE_FEATURE_FLAGS[10] || IMAGE_FEATURE_FLAGS[12]))
            $fatal(1,"motor_soc_top: observation identity requires an explicit guarded input profile");
        if (IMAGE_FEATURE_FLAGS[12] &&
            (!IMAGE_FEATURE_FLAGS[11] || !IMAGE_FEATURE_FLAGS[9] || !IMAGE_FEATURE_FLAGS[8] ||
             IMAGE_FEATURE_FLAGS[10] || ENCODER_FILTER_CYCLES != 4))
            $fatal(1,"motor_soc_top: filter4 identity requires guarded four-sample observation without bypass");
        if (IMAGE_FEATURE_FLAGS[13] && !IMAGE_FEATURE_FLAGS[12])
            $fatal(1,"motor_soc_top: loopback identity requires four-sample observation");
        if (IMAGE_FEATURE_FLAGS[14] && IMAGE_FEATURE_FLAGS != 32'h0000_4143)
            $fatal(1,"motor_soc_top: open-loop candidate requires exact 0x4143 identity");
    end
    // synthesis translate_on

endmodule
