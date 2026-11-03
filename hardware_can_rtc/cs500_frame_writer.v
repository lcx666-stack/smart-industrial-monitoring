`timescale 1ns/1ps

// One-frame DDR writer built from the user's vendor uidbuf_write/uiFDMA RTL.
// AXI write channels are exposed for concurrent arbitration with waveform DMA.
// The read side of uiFDMA is disabled. This module is not board-approved.
module cs500_frame_writer (
    input  wire        clk_axi,
    input  wire        resetn,
    input  wire        pixel_clk,
    input  wire [127:0] pixel_data,
    input  wire        pixel_valid,
    input  wire        pixel_frame_start,
    input  wire [31:0] frame_base,
    input  wire        start_pulse,
    input  wire        clear_pulse,
    output wire        frame_done,
    output wire        fdma_busy,
    output wire        fifo_full,
    output reg         response_error,
    output wire [5:0]  m_awid,
    output wire [32:0] m_awaddr,
    output wire [3:0]  m_awlen,
    output wire [1:0]  m_awsize,
    output wire [1:0]  m_awburst,
    output wire        m_awlock,
    output wire [3:0]  m_awcache,
    output wire [2:0]  m_awprot,
    output wire [3:0]  m_awqos,
    output wire        m_awvalid,
    input  wire        m_awready,
    output wire [63:0] m_wdata,
    output wire [7:0]  m_wstrb,
    output wire        m_wlast,
    output wire        m_wvalid,
    input  wire        m_wready,
    input  wire [5:0]  m_bid,
    input  wire [1:0]  m_bresp,
    input  wire        m_bvalid,
    output wire        m_bready
);
    wire [32:0] fdma_waddr;
    wire fdma_wareq;
    wire [15:0] fdma_wsize;
    wire [63:0] fdma_wdata;
    wire fdma_wvalid, fdma_wready;
    wire [7:0] sync_count;
    wire [7:0] awlen_full;
    wire [2:0] awsize_full;

    uidbuf_write #(
        .VIDEO_ENABLE(1), .ENABLE_WRITE(1), .ENABLE_READ(0),
        .AXI_DATA_WIDTH(64), .AXI_ADDR_WIDTH(33),
        .W_BUFDEPTH(4096), .W_DATAWIDTH(128), .W_DSIZEBITS(25),
        .W_XSIZE(480), .W_XSTRIDE(480), .W_YSIZE(1080), .W_XDIV(1)
    ) u_frame_buffer (
        .W_BASEADDR({1'b0, frame_base}), .W_BUFSIZE(16'd1),
        .I_ui_clk(clk_axi), .I_ui_rstn(resetn),
        .I_W_clk(pixel_clk), .I_W_FS(pixel_frame_start),
        .I_W_wren(pixel_valid), .I_W_data(pixel_data),
        .O_W_sync_cnt(sync_count), .I_W_buf(sync_count),
        .O_W_full(fifo_full),
        .O_fdma_waddr(fdma_waddr), .O_fdma_wareq(fdma_wareq),
        .O_fdma_wsize(fdma_wsize), .I_fdma_wbusy(fdma_busy),
        .O_fdma_wdata(fdma_wdata), .I_fdma_wvalid(fdma_wvalid),
        .O_fdma_wready(fdma_wready),
        .O_fmda_wbuf(), .O_fdma_wirq(),
        .camera_start(start_pulse), .camera_done(frame_done),
        .camera_clear_intr(clear_pulse)
    );

    uiFDMA #(
        .M_AXI_ID_WIDTH(6), .M_AXI_ID(1),
        .M_AXI_ADDR_WIDTH(33), .M_AXI_DATA_WIDTH(64),
        .M_AXI_MAX_BURST_LEN(16)
    ) u_axi_writer (
        .I_fdma_waddr(fdma_waddr), .I_fdma_wareq(fdma_wareq),
        .I_fdma_wsize(fdma_wsize), .O_fdma_wbusy(fdma_busy),
        .I_fdma_wdata(fdma_wdata), .O_fdma_wvalid(fdma_wvalid),
        .I_fdma_wready(fdma_wready),
        .I_fdma_raddr(33'd0), .I_fdma_rareq(1'b0),
        .I_fdma_rsize(16'd0), .O_fdma_rbusy(),
        .O_fdma_rdata(), .O_fdma_rvalid(), .I_fdma_rready(1'b0),
        .M_AXI_ACLK(clk_axi), .M_AXI_ARESETN(resetn),
        .M_AXI_AWID(m_awid), .M_AXI_AWADDR(m_awaddr),
        .M_AXI_AWLEN(awlen_full), .M_AXI_AWSIZE(awsize_full),
        .M_AXI_AWBURST(m_awburst), .M_AXI_AWLOCK(m_awlock),
        .M_AXI_AWCACHE(m_awcache), .M_AXI_AWPROT(m_awprot),
        .M_AXI_AWQOS(m_awqos), .M_AXI_AWVALID(m_awvalid),
        .M_AXI_AWREADY(m_awready), .M_AXI_WID(),
        .M_AXI_WDATA(m_wdata), .M_AXI_WSTRB(m_wstrb),
        .M_AXI_WLAST(m_wlast), .M_AXI_WVALID(m_wvalid),
        .M_AXI_WREADY(m_wready),
        .M_AXI_BID(m_bid), .M_AXI_BRESP(m_bresp),
        .M_AXI_BVALID(m_bvalid), .M_AXI_BREADY(m_bready),
        .M_AXI_ARID(), .M_AXI_ARADDR(), .M_AXI_ARLEN(),
        .M_AXI_ARSIZE(), .M_AXI_ARBURST(), .M_AXI_ARLOCK(),
        .M_AXI_ARCACHE(), .M_AXI_ARPROT(), .M_AXI_ARQOS(),
        .M_AXI_ARVALID(), .M_AXI_ARREADY(1'b0),
        .M_AXI_RID(6'd0), .M_AXI_RDATA(64'd0),
        .M_AXI_RRESP(2'b00), .M_AXI_RLAST(1'b0),
        .M_AXI_RVALID(1'b0), .M_AXI_RREADY()
    );
    assign m_awlen = awlen_full[3:0];
    assign m_awsize = awsize_full[1:0];

    always @(posedge clk_axi or negedge resetn) begin
        if (!resetn) response_error <= 1'b0;
        else if (clear_pulse) response_error <= 1'b0;
        else if ((m_bvalid && m_bready && m_bresp != 2'b00) ||
                 (m_awvalid && (|awlen_full[7:4])) ||
                 (m_awvalid && awsize_full[2]))
            response_error <= 1'b1;
    end
endmodule
