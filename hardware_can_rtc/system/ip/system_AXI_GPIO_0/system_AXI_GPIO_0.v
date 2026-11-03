/************************************************************\
**	Copyright (c) 2012-2026 Anlogic Inc.
**	All Right Reserved.
\************************************************************/
/************************************************************\
**	Gen time	:	Sep 26 2026 17:22:45
**	IpTool version	:	2026.03(193873 2026/03/31)
**	App version	:	Release_2026.1_SP2
**	Ip Version	:	1.0
\************************************************************/
`timescale 1ns/1ps
module system_AXI_GPIO_0
(
  input                         s_axi_aclk,
  input                         s_axi_aresetn,
  input   [8:0]                 s_axi_awaddr,
  input                         s_axi_awvalid,
  output                        s_axi_awready,
  input   [31:0]                s_axi_wdata,
  input   [3:0]                 s_axi_wstrb,
  input                         s_axi_wvalid,
  output                        s_axi_wready,
  output  [1:0]                 s_axi_bresp,
  output                        s_axi_bvalid,
  input                         s_axi_bready,
  input   [8:0]                 s_axi_araddr,
  input                         s_axi_arvalid,
  output                        s_axi_arready,
  output  [31:0]                s_axi_rdata,
  output  [1:0]                 s_axi_rresp,
  output                        s_axi_rvalid,
  input                         s_axi_rready,
  output  [31:0]                gpio_io_o,
  output  [1:0]                 gpio2_io_o
);

  axi_gpio_top_system_AXI_GPIO_0
  #(
      .AL_AXIS_ADDR_WD(9),
      .AL_AXIS_DATA_WD(32),
      .AL_GPIO_WD(32),
      .AL_GPIO2_WD(2),
      .AL_RESET_DOUT(32'h00000000),
      .AL_RESET_TRI(0),
      .AL_RESET_DOUT_2(2'h00000000),
      .AL_RESET_TRI_2(0)
  )axi_gpio_top_Inst
  (
      .s_axi_aclk(s_axi_aclk),
      .s_axi_aresetn(s_axi_aresetn),
      .s_axi_awaddr(s_axi_awaddr),
      .s_axi_awvalid(s_axi_awvalid),
      .s_axi_awready(s_axi_awready),
      .s_axi_wdata(s_axi_wdata),
      .s_axi_wstrb(s_axi_wstrb),
      .s_axi_wvalid(s_axi_wvalid),
      .s_axi_wready(s_axi_wready),
      .s_axi_bresp(s_axi_bresp),
      .s_axi_bvalid(s_axi_bvalid),
      .s_axi_bready(s_axi_bready),
      .s_axi_araddr(s_axi_araddr),
      .s_axi_arvalid(s_axi_arvalid),
      .s_axi_arready(s_axi_arready),
      .s_axi_rdata(s_axi_rdata),
      .s_axi_rresp(s_axi_rresp),
      .s_axi_rvalid(s_axi_rvalid),
      .s_axi_rready(s_axi_rready),
      .gpio_io_o(gpio_io_o),
      .gpio2_io_o(gpio2_io_o)
  );
endmodule
