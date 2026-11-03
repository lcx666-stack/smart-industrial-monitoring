/************************************************************\
**	Copyright (c) 2012-2026 Anlogic Inc.
**	All Right Reserved.
\************************************************************/
/************************************************************\
**	Gen time	:	Sep 26 2026 20:38:34
**	IpTool version	:	2026.03(193873 2026/03/31)
**	App version	:	Release_2026.1_SP2
**	Ip Version	:	1.0
\************************************************************/
module system_AXI_ERAM_Controller_0
(
  input   [12:0]                awid,
  input   [11:0]                awaddr,
  input   [7:0]                 awlen,
  input   [2:0]                 awsize,
  input   [1:0]                 awburst,
  input                         awlock,
  input                         awvalid,
  output                        awready,
  input   [31:0]                wdata,
  input   [3:0]                 wstrb,
  input                         wvalid,
  output                        wready,
  output  [12:0]                bid,
  output  [1:0]                 bresp,
  output                        bvalid,
  input                         bready,
  input   [12:0]                arid,
  input   [11:0]                araddr,
  input   [7:0]                 arlen,
  input   [2:0]                 arsize,
  input   [1:0]                 arburst,
  input                         arlock,
  input                         arvalid,
  output                        arready,
  output  [12:0]                rid,
  output  [31:0]                rdata,
  output  [1:0]                 rresp,
  output                        rlast,
  output                        rvalid,
  input                         rready,
  output  [9:0]                 mem_addr,
  output  [3:0]                 mem_web,
  output                        mem_csb,
  output  [31:0]                mem_din,
  input   [31:0]                mem_dout,
  input                         aclk,
  input                         aresetn
);

  axi_eram_controller_system_AXI_ERAM_Controller_0
  #(
      .AXI_ID_WIDTH(13),
      .AXI_DATA_WIDTH(32),
      .AXI_ADDR_WIDTH(12),
      .OOR_ERR_EN(1),
      .MEM_SIZE_KB(64'd4)
  )axi_eram_controller_Inst
  (
      .awid(awid),
      .awaddr(awaddr),
      .awlen(awlen),
      .awsize(awsize),
      .awburst(awburst),
      .awlock(awlock),
      .awvalid(awvalid),
      .awready(awready),
      .wdata(wdata),
      .wstrb(wstrb),
      .wvalid(wvalid),
      .wready(wready),
      .bid(bid),
      .bresp(bresp),
      .bvalid(bvalid),
      .bready(bready),
      .arid(arid),
      .araddr(araddr),
      .arlen(arlen),
      .arsize(arsize),
      .arburst(arburst),
      .arlock(arlock),
      .arvalid(arvalid),
      .arready(arready),
      .rid(rid),
      .rdata(rdata),
      .rresp(rresp),
      .rlast(rlast),
      .rvalid(rvalid),
      .rready(rready),
      .mem_addr(mem_addr),
      .mem_web(mem_web),
      .mem_csb(mem_csb),
      .mem_din(mem_din),
      .mem_dout(mem_dout),
      .aclk(aclk),
      .aresetn(aresetn)
  );
endmodule
