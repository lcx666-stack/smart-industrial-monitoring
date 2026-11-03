`timescale 1ns/1ps
// The vendor PLL configuration provides 100/120/150 MHz outputs from a 50 MHz
// reference. With REFCLK_DIV=2, the fused 100 MHz PS clock yields the same
// PLL reference; use 120 MHz for the NPU without changing motor/camera clocks.
module npu_sidecar (
    input wire clk,
    input wire resetn,
    output wire axi_clk,
    output wire [32:0] slave_hp1_axi_araddr,
    output wire [1:0] slave_hp1_axi_arburst,
    output wire [3:0] slave_hp1_axi_arcache,
    output wire [5:0] slave_hp1_axi_arid,
    output wire [3:0] slave_hp1_axi_arlen,
    output wire slave_hp1_axi_arlock,
    output wire [2:0] slave_hp1_axi_arprot,
    output wire [3:0] slave_hp1_axi_arqos,
    input wire slave_hp1_axi_arready,
    output wire [1:0] slave_hp1_axi_arsize,
    output wire slave_hp1_axi_arvalid,
    output wire [32:0] slave_hp1_axi_awaddr,
    output wire [1:0] slave_hp1_axi_awburst,
    output wire [3:0] slave_hp1_axi_awcache,
    output wire [5:0] slave_hp1_axi_awid,
    output wire [3:0] slave_hp1_axi_awlen,
    output wire slave_hp1_axi_awlock,
    output wire [2:0] slave_hp1_axi_awprot,
    output wire [3:0] slave_hp1_axi_awqos,
    input wire slave_hp1_axi_awready,
    output wire [1:0] slave_hp1_axi_awsize,
    output wire slave_hp1_axi_awvalid,
    input wire [5:0] slave_hp1_axi_bid,
    output wire slave_hp1_axi_bready,
    input wire [1:0] slave_hp1_axi_bresp,
    input wire slave_hp1_axi_bvalid,
    input wire [63:0] slave_hp1_axi_rdata,
    input wire [5:0] slave_hp1_axi_rid,
    input wire slave_hp1_axi_rlast,
    output wire slave_hp1_axi_rready,
    input wire [1:0] slave_hp1_axi_rresp,
    input wire slave_hp1_axi_rvalid,
    output wire [63:0] slave_hp1_axi_wdata,
    output wire slave_hp1_axi_wlast,
    input wire slave_hp1_axi_wready,
    output wire [7:0] slave_hp1_axi_wstrb,
    output wire slave_hp1_axi_wvalid,
    input wire [32:0] master_gp1_axi_araddr,
    input wire [1:0] master_gp1_axi_arburst,
    input wire [3:0] master_gp1_axi_arcache,
    input wire [11:0] master_gp1_axi_arid,
    input wire [3:0] master_gp1_axi_arlen,
    input wire master_gp1_axi_arlock,
    input wire [2:0] master_gp1_axi_arprot,
    output wire master_gp1_axi_arready,
    input wire [1:0] master_gp1_axi_arsize,
    input wire master_gp1_axi_arvalid,
    input wire [32:0] master_gp1_axi_awaddr,
    input wire [1:0] master_gp1_axi_awburst,
    input wire [3:0] master_gp1_axi_awcache,
    input wire [11:0] master_gp1_axi_awid,
    input wire [3:0] master_gp1_axi_awlen,
    input wire master_gp1_axi_awlock,
    input wire [2:0] master_gp1_axi_awprot,
    output wire master_gp1_axi_awready,
    input wire [1:0] master_gp1_axi_awsize,
    input wire master_gp1_axi_awvalid,
    output wire [11:0] master_gp1_axi_bid,
    input wire master_gp1_axi_bready,
    output wire [1:0] master_gp1_axi_bresp,
    output wire master_gp1_axi_bvalid,
    output wire [31:0] master_gp1_axi_rdata,
    output wire [11:0] master_gp1_axi_rid,
    output wire master_gp1_axi_rlast,
    input wire master_gp1_axi_rready,
    output wire [1:0] master_gp1_axi_rresp,
    output wire master_gp1_axi_rvalid,
    input wire [31:0] master_gp1_axi_wdata,
    input wire master_gp1_axi_wlast,
    output wire master_gp1_axi_wready,
    input wire [3:0] master_gp1_axi_wstrb,
    input wire master_gp1_axi_wvalid,
    output wire [15:0] f2p_irq
);

    wire pll_locked;
    wire npu_resetn;
    wire npu_soft_intr;
    design_0_PLL_0 u_npu_pll (
        .refclk(clk),
        .clk0_out(),
        .clk1_out(axi_clk),
        .clk2_out(),
        .lock(pll_locked)
    );
    design_0_Processor_System_Reset_2 u_npu_reset (
        .clk(axi_clk),
        .external_reset(1'b0),
        .aux_rst(resetn),
        .system_rst(1'b0),
        .pll_locked(pll_locked),
        .soc_reset(),
        .bus_reset(),
        .peripheral_reset(),
        .interconnect_aresetn(),
        .peripheral_aresetn(npu_resetn)
    );
    assign f2p_irq = {npu_soft_intr, 15'b0};
    assign slave_hp1_axi_awqos = 4'b0;
    assign slave_hp1_axi_arqos = 4'b0;
    wire [12:0] conv_bid, conv_rid;
    assign master_gp1_axi_bid = conv_bid[11:0];
    assign master_gp1_axi_rid = conv_rid[11:0];
    wire [32:0] lite_awaddr;
    wire [2:0] lite_awprot;
    wire lite_awvalid;
    wire lite_awready;
    wire [31:0] lite_wdata;
    wire [3:0] lite_wstrb;
    wire lite_wvalid;
    wire lite_wready;
    wire [1:0] lite_bresp;
    wire lite_bvalid;
    wire lite_bready;
    wire [32:0] lite_araddr;
    wire [2:0] lite_arprot;
    wire lite_arvalid;
    wire lite_arready;
    wire [31:0] lite_rdata;
    wire [1:0] lite_rresp;
    wire lite_rvalid;
    wire lite_rready;

    design_0_AXI_Protocol_Converter_1 u_npu_axilite (
        .us_axi_awid({1'b0, master_gp1_axi_awid}),
        .us_axi_awaddr(master_gp1_axi_awaddr),
        .us_axi_awlen({4'b0, master_gp1_axi_awlen}),
        .us_axi_awsize({1'b0, master_gp1_axi_awsize}),
        .us_axi_awburst(master_gp1_axi_awburst),
        .us_axi_awlock(master_gp1_axi_awlock),
        .us_axi_awcache(master_gp1_axi_awcache),
        .us_axi_awprot(master_gp1_axi_awprot),
        .us_axi_awvalid(master_gp1_axi_awvalid),
        .us_axi_awready(master_gp1_axi_awready),
        .us_axi_wdata(master_gp1_axi_wdata),
        .us_axi_wstrb(master_gp1_axi_wstrb),
        .us_axi_wlast(master_gp1_axi_wlast),
        .us_axi_wvalid(master_gp1_axi_wvalid),
        .us_axi_wready(master_gp1_axi_wready),
        .us_axi_bid(conv_bid),
        .us_axi_bresp(master_gp1_axi_bresp),
        .us_axi_bvalid(master_gp1_axi_bvalid),
        .us_axi_bready(master_gp1_axi_bready),
        .us_axi_arid({1'b0, master_gp1_axi_arid}),
        .us_axi_araddr(master_gp1_axi_araddr),
        .us_axi_arlen({4'b0, master_gp1_axi_arlen}),
        .us_axi_arsize({1'b0, master_gp1_axi_arsize}),
        .us_axi_arburst(master_gp1_axi_arburst),
        .us_axi_arlock(master_gp1_axi_arlock),
        .us_axi_arcache(master_gp1_axi_arcache),
        .us_axi_arprot(master_gp1_axi_arprot),
        .us_axi_arvalid(master_gp1_axi_arvalid),
        .us_axi_arready(master_gp1_axi_arready),
        .us_axi_rid(conv_rid),
        .us_axi_rdata(master_gp1_axi_rdata),
        .us_axi_rresp(master_gp1_axi_rresp),
        .us_axi_rlast(master_gp1_axi_rlast),
        .us_axi_rvalid(master_gp1_axi_rvalid),
        .us_axi_rready(master_gp1_axi_rready),
        .us_axi_awuser(1'b0),
        .us_axi_awqos(4'b0),
        .us_axi_wuser(1'b0),
        .us_axi_buser(),
        .us_axi_aruser(1'b0),
        .us_axi_arqos(4'b0),
        .us_axi_ruser(),
        .aclk(axi_clk),
        .aresetn(npu_resetn),
        .ds_axi_awaddr(lite_awaddr),
        .ds_axi_awprot(lite_awprot),
        .ds_axi_awvalid(lite_awvalid),
        .ds_axi_awready(lite_awready),
        .ds_axi_wdata(lite_wdata),
        .ds_axi_wstrb(lite_wstrb),
        .ds_axi_wvalid(lite_wvalid),
        .ds_axi_wready(lite_wready),
        .ds_axi_bresp(lite_bresp),
        .ds_axi_bvalid(lite_bvalid),
        .ds_axi_bready(lite_bready),
        .ds_axi_araddr(lite_araddr),
        .ds_axi_arprot(lite_arprot),
        .ds_axi_arvalid(lite_arvalid),
        .ds_axi_arready(lite_arready),
        .ds_axi_rdata(lite_rdata),
        .ds_axi_rresp(lite_rresp),
        .ds_axi_rvalid(lite_rvalid),
        .ds_axi_rready(lite_rready)
    );

    design_0_Video_NPU_0 u_video_npu (
        .S_AXILite_ACLK(axi_clk),
        .S_AXILite_AResetn(npu_resetn),
        .s_axilite_awaddr_i(lite_awaddr),
        .s_axilite_awprot_i(lite_awprot),
        .s_axilite_awvalid_i(lite_awvalid),
        .s_axilite_awready_o(lite_awready),
        .s_axilite_wdata_i(lite_wdata),
        .s_axilite_wstrb_i(lite_wstrb),
        .s_axilite_wvalid_i(lite_wvalid),
        .s_axilite_wready_o(lite_wready),
        .s_axilite_bresp_o(lite_bresp),
        .s_axilite_bvalid_o(lite_bvalid),
        .s_axilite_bready_i(lite_bready),
        .s_axilite_araddr_i(lite_araddr),
        .s_axilite_arprot_i(lite_arprot),
        .s_axilite_arvalid_i(lite_arvalid),
        .s_axilite_arready_o(lite_arready),
        .s_axilite_rdata_o(lite_rdata),
        .s_axilite_rresp_o(lite_rresp),
        .s_axilite_rvalid_o(lite_rvalid),
        .s_axilite_rready_i(lite_rready),
        .M_AXI_ACLK(axi_clk),
        .M_AXI_AResetn(npu_resetn),
        .m_axi_awid_soft_o(slave_hp1_axi_awid),
        .m_axi_awaddr_soft_o(slave_hp1_axi_awaddr),
        .m_axi_awlen_soft_o(slave_hp1_axi_awlen),
        .m_axi_awsize_soft_o(slave_hp1_axi_awsize),
        .m_axi_awburst_soft_o(slave_hp1_axi_awburst),
        .m_axi_awlock_soft_o(slave_hp1_axi_awlock),
        .m_axi_awcache_soft_o(slave_hp1_axi_awcache),
        .m_axi_awprot_soft_o(slave_hp1_axi_awprot),
        .m_axi_awvalid_soft_o(slave_hp1_axi_awvalid),
        .m_axi_awready_soft_i(slave_hp1_axi_awready),
        .m_axi_wdata_soft_o(slave_hp1_axi_wdata),
        .m_axi_wstrb_soft_o(slave_hp1_axi_wstrb),
        .m_axi_wlast_soft_o(slave_hp1_axi_wlast),
        .m_axi_wvalid_soft_o(slave_hp1_axi_wvalid),
        .m_axi_wready_soft_i(slave_hp1_axi_wready),
        .m_axi_bid_soft_i(slave_hp1_axi_bid),
        .m_axi_bresp_soft_i(slave_hp1_axi_bresp),
        .m_axi_bvalid_soft_i(slave_hp1_axi_bvalid),
        .m_axi_bready_soft_o(slave_hp1_axi_bready),
        .m_axi_arid_soft_o(slave_hp1_axi_arid),
        .m_axi_araddr_soft_o(slave_hp1_axi_araddr),
        .m_axi_arlen_soft_o(slave_hp1_axi_arlen),
        .m_axi_arsize_soft_o(slave_hp1_axi_arsize),
        .m_axi_arburst_soft_o(slave_hp1_axi_arburst),
        .m_axi_arlock_soft_o(slave_hp1_axi_arlock),
        .m_axi_arcache_soft_o(slave_hp1_axi_arcache),
        .m_axi_arprot_soft_o(slave_hp1_axi_arprot),
        .m_axi_arvalid_soft_o(slave_hp1_axi_arvalid),
        .m_axi_arready_soft_i(slave_hp1_axi_arready),
        .m_axi_rid_soft_i(slave_hp1_axi_rid),
        .m_axi_rdata_soft_i(slave_hp1_axi_rdata),
        .m_axi_rresp_soft_i(slave_hp1_axi_rresp),
        .m_axi_rlast_soft_i(slave_hp1_axi_rlast),
        .m_axi_rvalid_soft_i(slave_hp1_axi_rvalid),
        .m_axi_rready_soft_o(slave_hp1_axi_rready),
        .npu_soft_intr(npu_soft_intr)
    );
endmodule
