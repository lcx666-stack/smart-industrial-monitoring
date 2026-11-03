`timescale 1ns/1ps

// Provisional static-frame scanout for the vendor 1024x600 MIPI-DSI panel.
// It crops a completed 1920x1080 BGRA frame in Linux CMA to the central
// 1024x600 region. The display base is latched once per enable cycle; callers
// must disable and drain reads before replacing that CMA allocation.
// Not yet connected to the active top or board-approved.
module dsi_frame_reader (
    input  wire        clk_axi,
    input  wire        resetn,
    input  wire        pixel_clk,
    input  wire        panel_vsync,
    input  wire        panel_de,
    input  wire        display_enable,
    input  wire [31:0] requested_frame_base,
    output reg  [31:0] active_frame_base,
    output reg         armed,
    output wire        read_busy,
    output reg         read_error,
    output wire [31:0] read_error_detail,
    output reg  [31:0] first_araddr,
    output wire [31:0] pixel_bgra,
    output wire        pixel_valid,
    output wire [5:0]  m_arid,
    output wire [32:0] m_araddr,
    output wire [3:0]  m_arlen,
    output wire [1:0]  m_arsize,
    output wire [1:0]  m_arburst,
    output wire        m_arlock,
    output wire [3:0]  m_arcache,
    output wire [2:0]  m_arprot,
    output wire [3:0]  m_arqos,
    output wire        m_arvalid,
    input  wire        m_arready,
    input  wire [5:0]  m_rid,
    input  wire [63:0] m_rdata,
    input  wire [1:0]  m_rresp,
    input  wire        m_rlast,
    input  wire        m_rvalid,
    output wire        m_rready
);
    localparam [32:0] CENTER_CROP_BYTES = 33'd1_844_992;
    localparam [32:0] FRAME_BYTES = 33'd8_294_400;
    wire base_valid = requested_frame_base[5:0] == 0 &&
                      requested_frame_base != 0 &&
                      ({1'b0, requested_frame_base} + FRAME_BYTES - 1) <=
                      33'h0_ffff_ffff;
    reg [1:0] arm_pixel_sync;
    always @(posedge pixel_clk or negedge resetn) begin
        if (!resetn) arm_pixel_sync <= 0;
        else arm_pixel_sync <= {arm_pixel_sync[0], armed};
    end
    always @(posedge clk_axi or negedge resetn) begin
        if (!resetn) begin
            active_frame_base <= 0;
            armed <= 0;
        end else if (!display_enable) begin
            armed <= 0;
        end else if (!armed && !read_busy && base_valid) begin
            active_frame_base <= requested_frame_base;
            armed <= 1;
        end
    end

    wire [32:0] fdma_raddr;
    wire fdma_rareq;
    wire [15:0] fdma_rsize;
    wire [63:0] fdma_rdata;
    wire fdma_rvalid, fdma_rready;
    wire [7:0] arlen_full;
    wire [2:0] arsize_full;
    wire read_frame_user, read_line_last, read_frame_reset;
    wire [7:0] read_buf_sync;

    ui_dbuf #(
        .AXI_DATA_WIDTH(64), .AXI_ADDR_WIDTH(33),
        .ENABLE_VSYNC(1),
        .W_BUFDEPTH(16), .W_DATAWIDTH(128), .W_BASEADDR(33'd0),
        .W_DSIZEBITS(23), .W_XSIZE(480), .W_XSTRIDE(480),
        .W_YSIZE(1080), .W_XDIV(1), .W_BUFSIZE(1),
        .R_BUFDEPTH(2048), .R_DATAWIDTH(32), .R_BASEADDR(33'd0),
        .R_DSIZEBITS(23), .R_XSIZE(1024), .R_XSTRIDE(1920),
        .R_YSIZE(600), .R_XDIV(2), .R_BUFSIZE(1)
    ) u_read_buffer (
        .I_ui_clk(clk_axi), .I_ui_rstn(resetn),
        .I_W_en(1'b0), .I_W_wclk(pixel_clk),
        .I_W_tuser(1'b0), .I_W_tvalid(1'b0),
        .I_W_tdata(128'd0), .I_W_tlast(1'b0),
        .O_W_tready(), .O_W_sync_cnt(), .I_W_buf(8'd0),
        .O_fdma_waddr(), .O_fdma_wareq(), .O_fdma_wsize(),
        .I_fdma_wbusy(1'b0), .O_fdma_wdata(),
        .I_fdma_wvalid(1'b0), .O_fdma_wready(),
        .O_fdma_wbuf(), .O_fdma_wirq(),
        .I_R_en(panel_vsync && arm_pixel_sync[1]),
        .I_Rsync_en(1'b0), .I_R_rclk(pixel_clk),
        .I_R_tready(panel_de),
        .O_R_tuser(read_frame_user), .O_R_tvalid(pixel_valid),
        .O_R_tdata(pixel_bgra), .O_R_vrst(read_frame_reset),
        .O_R_tlast(read_line_last),
        .O_R_sync_cnt(read_buf_sync), .I_R_buf(8'd0),
        .I_R_baseaddr({1'b0, active_frame_base} + CENTER_CROP_BYTES),
        .O_fdma_raddr(fdma_raddr), .O_fdma_rareq(fdma_rareq),
        .O_fdma_rsize(fdma_rsize), .I_fdma_rbusy(read_busy),
        .I_fdma_rdata(fdma_rdata), .I_fdma_rvalid(fdma_rvalid),
        .O_fdma_rready(fdma_rready),
        .O_fdma_rbuf(), .O_fdma_rirq()
    );

    // Use the FDMA read controller from the vendor's 1024x600 CSI-to-DSI demo.
    // The other project FDMA's exact-multiple-of-16 read path emitted ARLEN=255.
    uiFDMA_display #(
        .M_AXI_B2B_SET(1), .M_AXI_ID_WIDTH(6), .M_AXI_ID(2),
        .M_AXI_ADDR_WIDTH(33), .M_AXI_DATA_WIDTH(64),
        .M_AXI_MAX_BURST_LEN(16)
    ) u_axi_reader (
        .I_fdma_waddr(33'd0), .I_fdma_wareq(1'b0),
        .I_fdma_wsize(16'd0), .O_fdma_wbusy(),
        .I_fdma_wdata(64'd0), .O_fdma_wvalid(),
        .I_fdma_wready(1'b0),
        .I_fdma_raddr(fdma_raddr), .I_fdma_rareq(fdma_rareq),
        .I_fdma_rsize(fdma_rsize), .O_fdma_rbusy(read_busy),
        .O_fdma_rdata(fdma_rdata), .O_fdma_rvalid(fdma_rvalid),
        .I_fdma_rready(fdma_rready),
        .M_AXI_ACLK(clk_axi), .M_AXI_ARESETN(resetn),
        .M_AXI_AWID(), .M_AXI_AWADDR(), .M_AXI_AWLEN(),
        .M_AXI_AWSIZE(), .M_AXI_AWBURST(), .M_AXI_AWLOCK(),
        .M_AXI_AWCACHE(), .M_AXI_AWPROT(), .M_AXI_AWQOS(),
        .M_AXI_AWVALID(), .M_AXI_AWREADY(1'b0),
        .M_AXI_WID(), .M_AXI_WDATA(), .M_AXI_WSTRB(),
        .M_AXI_WLAST(), .M_AXI_WVALID(), .M_AXI_WREADY(1'b0),
        .M_AXI_BID(6'd0), .M_AXI_BRESP(2'd0),
        .M_AXI_BVALID(1'b0), .M_AXI_BREADY(),
        .M_AXI_ARID(m_arid), .M_AXI_ARADDR(m_araddr),
        .M_AXI_ARLEN(arlen_full), .M_AXI_ARSIZE(arsize_full),
        .M_AXI_ARBURST(m_arburst), .M_AXI_ARLOCK(m_arlock),
        .M_AXI_ARCACHE(m_arcache), .M_AXI_ARPROT(m_arprot),
        .M_AXI_ARQOS(m_arqos), .M_AXI_ARVALID(m_arvalid),
        .M_AXI_ARREADY(m_arready),
        .M_AXI_RID(m_rid), .M_AXI_RDATA(m_rdata),
        .M_AXI_RRESP(m_rresp), .M_AXI_RLAST(m_rlast),
        .M_AXI_RVALID(m_rvalid), .M_AXI_RREADY(m_rready)
    );
    assign m_arlen = arlen_full[3:0];
    assign m_arsize = arsize_full[1:0];
    wire bad_rresp = m_rvalid && m_rready && m_rresp != 0;
    wire bad_rid = m_rvalid && m_rready && m_rid != 6'd2;
    wire bad_arlen = m_arvalid && (|arlen_full[7:4]);
    wire bad_arsize = m_arvalid && arsize_full[2];
    reg [3:0] error_flags;
    reg [5:0] first_bad_rid;
    reg [1:0] first_bad_rresp;
    reg [7:0] first_bad_arlen;
    reg [2:0] first_bad_arsize;
    reg first_error_seen;
    reg first_ar_seen;
    // 0xCA0: [3:0] sticky causes (RRESP, RID, ARLEN, ARSIZE),
    // [9:4] first RID, [11:10] first RRESP, [19:12] first ARLEN,
    // [22:20] first ARSIZE. 0xCA4: first accepted AR address, low 32 bits.
    assign read_error_detail = {9'd0, first_bad_arsize, first_bad_arlen,
                                first_bad_rresp, first_bad_rid, error_flags};
    always @(posedge clk_axi or negedge resetn) begin
        if (!resetn) begin
            read_error <= 0;
            error_flags <= 0;
            first_bad_rid <= 0;
            first_bad_rresp <= 0;
            first_bad_arlen <= 0;
            first_bad_arsize <= 0;
            first_error_seen <= 0;
            first_ar_seen <= 0;
            first_araddr <= 0;
        end else begin
            if (m_arvalid && m_arready && !first_ar_seen) begin
                first_ar_seen <= 1;
                first_araddr <= m_araddr[31:0];
            end
            if (bad_rresp || bad_rid || bad_arlen || bad_arsize) begin
                read_error <= 1;
                error_flags <= error_flags |
                               {bad_arsize, bad_arlen, bad_rid, bad_rresp};
                if (!first_error_seen) begin
                    first_error_seen <= 1;
                    first_bad_rid <= m_rid;
                    first_bad_rresp <= m_rresp;
                    first_bad_arlen <= arlen_full;
                    first_bad_arsize <= arsize_full;
                end
            end
        end
    end
endmodule
