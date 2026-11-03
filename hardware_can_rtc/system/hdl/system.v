/************************************************************\
**	Copyright (c) 2012-2026 anlogic Inc.
**	All Right Reserved.
\************************************************************/
/************************************************************\
**	Gen time	:	2026-09-26 21:12:34
**	DI version	:	197563 2026/05/12
**	App version	:	(build number:6.2.2.200067)
\************************************************************/

module system (
    input wire can0_rx_in,
    output wire can0_tx_out,
    input wire i2c1_scl_in, i2c1_sda_in,
    output wire i2c1_scl_oe, i2c1_sda_oe,
    output    wire       [31:0] motor_target ,
    output    wire        [1:0] motor_ctrl ,
    output    wire              motor_clk ,
    output    wire              motor_resetn,
    output    wire        [9:0] status_addr,
    output    wire        [3:0] status_web,
    output    wire              status_csb,
    output    wire       [31:0] status_wdata,
    input     wire       [31:0] status_rdata,
    input wire [5:0] dma_awid,
    input wire [32:0] dma_awaddr,
    input wire [3:0] dma_awlen,
    input wire [1:0] dma_awsize,
    input wire [1:0] dma_awburst,
    input wire dma_awlock,
    input wire [3:0] dma_awcache,
    input wire [2:0] dma_awprot,
    input wire [3:0] dma_awqos,
    input wire dma_awvalid,
    output wire dma_awready,
    input wire [63:0] dma_wdata,
    input wire [7:0] dma_wstrb,
    input wire dma_wlast,
    input wire dma_wvalid,
    output wire dma_wready,
    output wire [5:0] dma_bid,
    output wire [1:0] dma_bresp,
    output wire dma_bvalid,
    input wire dma_bready,
    input wire [5:0] display_arid,
    input wire [32:0] display_araddr,
    input wire [3:0] display_arlen,
    input wire [1:0] display_arsize,
    input wire [1:0] display_arburst,
    input wire display_arlock,
    input wire [3:0] display_arcache,
    input wire [2:0] display_arprot,
    input wire [3:0] display_arqos,
    input wire display_arvalid,
    output wire display_arready,
    output wire [5:0] display_rid,
    output wire [63:0] display_rdata,
    output wire [1:0] display_rresp,
    output wire display_rlast,
    output wire display_rvalid,
    input wire display_rready
); 

    // Isolated NPU sidecar; original GP0/HP0 motor and camera paths are unchanged.
    wire [32:0] npu_slave_hp1_axi_araddr;
    wire [1:0] npu_slave_hp1_axi_arburst;
    wire [3:0] npu_slave_hp1_axi_arcache;
    wire [5:0] npu_slave_hp1_axi_arid;
    wire [3:0] npu_slave_hp1_axi_arlen;
    wire npu_slave_hp1_axi_arlock;
    wire [2:0] npu_slave_hp1_axi_arprot;
    wire [3:0] npu_slave_hp1_axi_arqos;
    wire npu_slave_hp1_axi_arready;
    wire [1:0] npu_slave_hp1_axi_arsize;
    wire npu_slave_hp1_axi_arvalid;
    wire [32:0] npu_slave_hp1_axi_awaddr;
    wire [1:0] npu_slave_hp1_axi_awburst;
    wire [3:0] npu_slave_hp1_axi_awcache;
    wire [5:0] npu_slave_hp1_axi_awid;
    wire [3:0] npu_slave_hp1_axi_awlen;
    wire npu_slave_hp1_axi_awlock;
    wire [2:0] npu_slave_hp1_axi_awprot;
    wire [3:0] npu_slave_hp1_axi_awqos;
    wire npu_slave_hp1_axi_awready;
    wire [1:0] npu_slave_hp1_axi_awsize;
    wire npu_slave_hp1_axi_awvalid;
    wire [5:0] npu_slave_hp1_axi_bid;
    wire npu_slave_hp1_axi_bready;
    wire [1:0] npu_slave_hp1_axi_bresp;
    wire npu_slave_hp1_axi_bvalid;
    wire [63:0] npu_slave_hp1_axi_rdata;
    wire [5:0] npu_slave_hp1_axi_rid;
    wire npu_slave_hp1_axi_rlast;
    wire npu_slave_hp1_axi_rready;
    wire [1:0] npu_slave_hp1_axi_rresp;
    wire npu_slave_hp1_axi_rvalid;
    wire [63:0] npu_slave_hp1_axi_wdata;
    wire npu_slave_hp1_axi_wlast;
    wire npu_slave_hp1_axi_wready;
    wire [7:0] npu_slave_hp1_axi_wstrb;
    wire npu_slave_hp1_axi_wvalid;
    wire [32:0] npu_master_gp1_axi_araddr;
    wire [1:0] npu_master_gp1_axi_arburst;
    wire [3:0] npu_master_gp1_axi_arcache;
    wire [11:0] npu_master_gp1_axi_arid;
    wire [3:0] npu_master_gp1_axi_arlen;
    wire npu_master_gp1_axi_arlock;
    wire [2:0] npu_master_gp1_axi_arprot;
    wire npu_master_gp1_axi_arready;
    wire [1:0] npu_master_gp1_axi_arsize;
    wire npu_master_gp1_axi_arvalid;
    wire [32:0] npu_master_gp1_axi_awaddr;
    wire [1:0] npu_master_gp1_axi_awburst;
    wire [3:0] npu_master_gp1_axi_awcache;
    wire [11:0] npu_master_gp1_axi_awid;
    wire [3:0] npu_master_gp1_axi_awlen;
    wire npu_master_gp1_axi_awlock;
    wire [2:0] npu_master_gp1_axi_awprot;
    wire npu_master_gp1_axi_awready;
    wire [1:0] npu_master_gp1_axi_awsize;
    wire npu_master_gp1_axi_awvalid;
    wire [11:0] npu_master_gp1_axi_bid;
    wire npu_master_gp1_axi_bready;
    wire [1:0] npu_master_gp1_axi_bresp;
    wire npu_master_gp1_axi_bvalid;
    wire [31:0] npu_master_gp1_axi_rdata;
    wire [11:0] npu_master_gp1_axi_rid;
    wire npu_master_gp1_axi_rlast;
    wire npu_master_gp1_axi_rready;
    wire [1:0] npu_master_gp1_axi_rresp;
    wire npu_master_gp1_axi_rvalid;
    wire [31:0] npu_master_gp1_axi_wdata;
    wire npu_master_gp1_axi_wlast;
    wire npu_master_gp1_axi_wready;
    wire [3:0] npu_master_gp1_axi_wstrb;
    wire npu_master_gp1_axi_wvalid;
    wire [15:0] npu_f2p_irq;
    wire npu_axi_clk;
    wire              w_port__ARM_Processor_System_0__p2f_clk0 ;
    wire              w_port__ARM_Processor_System_0__master_gp0_axi_aclk ;
    wire              w_port__ARM_Processor_System_0__slave_hp0_axi_aclk ;
    wire              w_port__Processor_System_Reset_0__clk ;
    wire              w_port__AXI_ERAM_Controller_0__aclk ;
    wire              w_port__AXI_GPIO_0__s_axi_aclk ;
    wire              w_port__AXI_Matrix_0__aclk ;
    wire              w_port__AXI_Protocol_Converter_0__aclk ;
    wire              w_net__ARM_Processor_System_0__p2f_clk0 ; 

    wire              w_port__ARM_Processor_System_0__p2f_rst0_n ;
    wire              w_port__Processor_System_Reset_0__external_resetn ;
    wire              w_net__ARM_Processor_System_0__p2f_rst0_n ; 

    wire [0:0]        w_port__Constant_0__dout ;
    wire              w_port__Processor_System_Reset_0__aux_reset ;
    wire              w_port__Processor_System_Reset_0__system_rst ;
    wire [0:0]        w_net__Constant_0__dout ; 

    wire [0:0]        w_port__Constant_1__dout ;
    wire              w_port__Processor_System_Reset_0__pll_locked ;
    wire [0:0]        w_net__Constant_1__dout ; 

    wire [0:0]        w_port__Processor_System_Reset_0__peripheral_aresetn ;
    wire              w_port__AXI_ERAM_Controller_0__aresetn ;
    wire              w_port__AXI_GPIO_0__s_axi_aresetn ;
    wire [0:0]        w_net__Processor_System_Reset_0__peripheral_aresetn ; 

    wire [0:0]        w_port__Processor_System_Reset_0__interconnect_aresetn ;
    wire              w_port__AXI_Matrix_0__aresetn ;
    wire              w_port__AXI_Protocol_Converter_0__aresetn ;
    wire [0:0]        w_net__Processor_System_Reset_0__interconnect_aresetn ; 


    wire [32:0]       w_port__ARM_Processor_System_0__master_gp0_axi_araddr ;
    wire [32:0]       w_port__AXI_Matrix_0__us0_araddr ;
    wire [32:0]       w_net__ARM_Processor_System_0__master_gp0_axi_araddr ; 

    wire [1:0]        w_port__ARM_Processor_System_0__master_gp0_axi_arburst ;
    wire [1:0]        w_port__AXI_Matrix_0__us0_arburst ;
    wire [1:0]        w_net__ARM_Processor_System_0__master_gp0_axi_arburst ; 

    wire [3:0]        w_port__ARM_Processor_System_0__master_gp0_axi_arcache ;
    wire [3:0]        w_port__AXI_Matrix_0__us0_arcache ;
    wire [3:0]        w_net__ARM_Processor_System_0__master_gp0_axi_arcache ; 

    wire [11:0]       w_port__ARM_Processor_System_0__master_gp0_axi_arid ;
    wire [11:0]       w_port__AXI_Matrix_0__us0_arid ;
    wire [11:0]       w_net__ARM_Processor_System_0__master_gp0_axi_arid ; 

    wire [3:0]        w_port__ARM_Processor_System_0__master_gp0_axi_arlen ;
    wire [7:0]        w_port__AXI_Matrix_0__us0_arlen ;
    wire [3:0]        w_net__ARM_Processor_System_0__master_gp0_axi_arlen ; 

    wire              w_port__ARM_Processor_System_0__master_gp0_axi_arlock ;
    wire [0:0]        w_port__AXI_Matrix_0__us0_arlock ;
    wire              w_net__ARM_Processor_System_0__master_gp0_axi_arlock ; 

    wire [2:0]        w_port__ARM_Processor_System_0__master_gp0_axi_arprot ;
    wire [2:0]        w_port__AXI_Matrix_0__us0_arprot ;
    wire [2:0]        w_net__ARM_Processor_System_0__master_gp0_axi_arprot ; 

    wire              w_port__AXI_Matrix_0__us0_arready ;
    wire              w_port__ARM_Processor_System_0__master_gp0_axi_arready ;
    wire              w_net__AXI_Matrix_0__us0_arready ; 

    wire [1:0]        w_port__ARM_Processor_System_0__master_gp0_axi_arsize ;
    wire [2:0]        w_port__AXI_Matrix_0__us0_arsize ;
    wire [1:0]        w_net__ARM_Processor_System_0__master_gp0_axi_arsize ; 

    wire              w_port__ARM_Processor_System_0__master_gp0_axi_arvalid ;
    wire              w_port__AXI_Matrix_0__us0_arvalid ;
    wire              w_net__ARM_Processor_System_0__master_gp0_axi_arvalid ; 

    wire [32:0]       w_port__ARM_Processor_System_0__master_gp0_axi_awaddr ;
    wire [32:0]       w_port__AXI_Matrix_0__us0_awaddr ;
    wire [32:0]       w_net__ARM_Processor_System_0__master_gp0_axi_awaddr ; 

    wire [1:0]        w_port__ARM_Processor_System_0__master_gp0_axi_awburst ;
    wire [1:0]        w_port__AXI_Matrix_0__us0_awburst ;
    wire [1:0]        w_net__ARM_Processor_System_0__master_gp0_axi_awburst ; 

    wire [3:0]        w_port__ARM_Processor_System_0__master_gp0_axi_awcache ;
    wire [3:0]        w_port__AXI_Matrix_0__us0_awcache ;
    wire [3:0]        w_net__ARM_Processor_System_0__master_gp0_axi_awcache ; 

    wire [11:0]       w_port__ARM_Processor_System_0__master_gp0_axi_awid ;
    wire [11:0]       w_port__AXI_Matrix_0__us0_awid ;
    wire [11:0]       w_net__ARM_Processor_System_0__master_gp0_axi_awid ; 

    wire [3:0]        w_port__ARM_Processor_System_0__master_gp0_axi_awlen ;
    wire [7:0]        w_port__AXI_Matrix_0__us0_awlen ;
    wire [3:0]        w_net__ARM_Processor_System_0__master_gp0_axi_awlen ; 

    wire              w_port__ARM_Processor_System_0__master_gp0_axi_awlock ;
    wire [0:0]        w_port__AXI_Matrix_0__us0_awlock ;
    wire              w_net__ARM_Processor_System_0__master_gp0_axi_awlock ; 

    wire [2:0]        w_port__ARM_Processor_System_0__master_gp0_axi_awprot ;
    wire [2:0]        w_port__AXI_Matrix_0__us0_awprot ;
    wire [2:0]        w_net__ARM_Processor_System_0__master_gp0_axi_awprot ; 

    wire              w_port__AXI_Matrix_0__us0_awready ;
    wire              w_port__ARM_Processor_System_0__master_gp0_axi_awready ;
    wire              w_net__AXI_Matrix_0__us0_awready ; 

    wire [1:0]        w_port__ARM_Processor_System_0__master_gp0_axi_awsize ;
    wire [2:0]        w_port__AXI_Matrix_0__us0_awsize ;
    wire [1:0]        w_net__ARM_Processor_System_0__master_gp0_axi_awsize ; 

    wire              w_port__ARM_Processor_System_0__master_gp0_axi_awvalid ;
    wire              w_port__AXI_Matrix_0__us0_awvalid ;
    wire              w_net__ARM_Processor_System_0__master_gp0_axi_awvalid ; 

    wire [11:0]       w_port__AXI_Matrix_0__us0_bid ;
    wire [11:0]       w_port__ARM_Processor_System_0__master_gp0_axi_bid ;
    wire [11:0]       w_net__AXI_Matrix_0__us0_bid ; 

    wire              w_port__ARM_Processor_System_0__master_gp0_axi_bready ;
    wire              w_port__AXI_Matrix_0__us0_bready ;
    wire              w_net__ARM_Processor_System_0__master_gp0_axi_bready ; 

    wire [1:0]        w_port__AXI_Matrix_0__us0_bresp ;
    wire [1:0]        w_port__ARM_Processor_System_0__master_gp0_axi_bresp ;
    wire [1:0]        w_net__AXI_Matrix_0__us0_bresp ; 

    wire              w_port__AXI_Matrix_0__us0_bvalid ;
    wire              w_port__ARM_Processor_System_0__master_gp0_axi_bvalid ;
    wire              w_net__AXI_Matrix_0__us0_bvalid ; 

    wire [31:0]       w_port__AXI_Matrix_0__us0_rdata ;
    wire [31:0]       w_port__ARM_Processor_System_0__master_gp0_axi_rdata ;
    wire [31:0]       w_net__AXI_Matrix_0__us0_rdata ; 

    wire [11:0]       w_port__AXI_Matrix_0__us0_rid ;
    wire [11:0]       w_port__ARM_Processor_System_0__master_gp0_axi_rid ;
    wire [11:0]       w_net__AXI_Matrix_0__us0_rid ; 

    wire              w_port__AXI_Matrix_0__us0_rlast ;
    wire              w_port__ARM_Processor_System_0__master_gp0_axi_rlast ;
    wire              w_net__AXI_Matrix_0__us0_rlast ; 

    wire              w_port__ARM_Processor_System_0__master_gp0_axi_rready ;
    wire              w_port__AXI_Matrix_0__us0_rready ;
    wire              w_net__ARM_Processor_System_0__master_gp0_axi_rready ; 

    wire [1:0]        w_port__AXI_Matrix_0__us0_rresp ;
    wire [1:0]        w_port__ARM_Processor_System_0__master_gp0_axi_rresp ;
    wire [1:0]        w_net__AXI_Matrix_0__us0_rresp ; 

    wire              w_port__AXI_Matrix_0__us0_rvalid ;
    wire              w_port__ARM_Processor_System_0__master_gp0_axi_rvalid ;
    wire              w_net__AXI_Matrix_0__us0_rvalid ; 

    wire [31:0]       w_port__ARM_Processor_System_0__master_gp0_axi_wdata ;
    wire [31:0]       w_port__AXI_Matrix_0__us0_wdata ;
    wire [31:0]       w_net__ARM_Processor_System_0__master_gp0_axi_wdata ; 

    wire              w_port__ARM_Processor_System_0__master_gp0_axi_wlast ;
    wire              w_port__AXI_Matrix_0__us0_wlast ;
    wire              w_net__ARM_Processor_System_0__master_gp0_axi_wlast ; 

    wire              w_port__AXI_Matrix_0__us0_wready ;
    wire              w_port__ARM_Processor_System_0__master_gp0_axi_wready ;
    wire              w_net__AXI_Matrix_0__us0_wready ; 

    wire [3:0]        w_port__ARM_Processor_System_0__master_gp0_axi_wstrb ;
    wire [3:0]        w_port__AXI_Matrix_0__us0_wstrb ;
    wire [3:0]        w_net__ARM_Processor_System_0__master_gp0_axi_wstrb ; 

    wire              w_port__ARM_Processor_System_0__master_gp0_axi_wvalid ;
    wire              w_port__AXI_Matrix_0__us0_wvalid ;
    wire              w_net__ARM_Processor_System_0__master_gp0_axi_wvalid ; 


    wire [32:0]       w_port__AXI_Matrix_0__ds0_araddr ;
    wire [11:0]       w_port__AXI_ERAM_Controller_0__araddr ;
    wire [32:0]       w_net__AXI_Matrix_0__ds0_araddr ; 

    wire [1:0]        w_port__AXI_Matrix_0__ds0_arburst ;
    wire [1:0]        w_port__AXI_ERAM_Controller_0__arburst ;
    wire [1:0]        w_net__AXI_Matrix_0__ds0_arburst ; 

    wire [12:0]       w_port__AXI_Matrix_0__ds0_arid ;
    wire [12:0]       w_port__AXI_ERAM_Controller_0__arid ;
    wire [12:0]       w_net__AXI_Matrix_0__ds0_arid ; 

    wire [7:0]        w_port__AXI_Matrix_0__ds0_arlen ;
    wire [7:0]        w_port__AXI_ERAM_Controller_0__arlen ;
    wire [7:0]        w_net__AXI_Matrix_0__ds0_arlen ; 

    wire [0:0]        w_port__AXI_Matrix_0__ds0_arlock ;
    wire              w_port__AXI_ERAM_Controller_0__arlock ;
    wire [0:0]        w_net__AXI_Matrix_0__ds0_arlock ; 

    wire              w_port__AXI_ERAM_Controller_0__arready ;
    wire              w_port__AXI_Matrix_0__ds0_arready ;
    wire              w_net__AXI_ERAM_Controller_0__arready ; 

    wire [2:0]        w_port__AXI_Matrix_0__ds0_arsize ;
    wire [2:0]        w_port__AXI_ERAM_Controller_0__arsize ;
    wire [2:0]        w_net__AXI_Matrix_0__ds0_arsize ; 

    wire              w_port__AXI_Matrix_0__ds0_arvalid ;
    wire              w_port__AXI_ERAM_Controller_0__arvalid ;
    wire              w_net__AXI_Matrix_0__ds0_arvalid ; 

    wire [32:0]       w_port__AXI_Matrix_0__ds0_awaddr ;
    wire [11:0]       w_port__AXI_ERAM_Controller_0__awaddr ;
    wire [32:0]       w_net__AXI_Matrix_0__ds0_awaddr ; 

    wire [1:0]        w_port__AXI_Matrix_0__ds0_awburst ;
    wire [1:0]        w_port__AXI_ERAM_Controller_0__awburst ;
    wire [1:0]        w_net__AXI_Matrix_0__ds0_awburst ; 

    wire [12:0]       w_port__AXI_Matrix_0__ds0_awid ;
    wire [12:0]       w_port__AXI_ERAM_Controller_0__awid ;
    wire [12:0]       w_net__AXI_Matrix_0__ds0_awid ; 

    wire [7:0]        w_port__AXI_Matrix_0__ds0_awlen ;
    wire [7:0]        w_port__AXI_ERAM_Controller_0__awlen ;
    wire [7:0]        w_net__AXI_Matrix_0__ds0_awlen ; 

    wire [0:0]        w_port__AXI_Matrix_0__ds0_awlock ;
    wire              w_port__AXI_ERAM_Controller_0__awlock ;
    wire [0:0]        w_net__AXI_Matrix_0__ds0_awlock ; 

    wire              w_port__AXI_ERAM_Controller_0__awready ;
    wire              w_port__AXI_Matrix_0__ds0_awready ;
    wire              w_net__AXI_ERAM_Controller_0__awready ; 

    wire [2:0]        w_port__AXI_Matrix_0__ds0_awsize ;
    wire [2:0]        w_port__AXI_ERAM_Controller_0__awsize ;
    wire [2:0]        w_net__AXI_Matrix_0__ds0_awsize ; 

    wire              w_port__AXI_Matrix_0__ds0_awvalid ;
    wire              w_port__AXI_ERAM_Controller_0__awvalid ;
    wire              w_net__AXI_Matrix_0__ds0_awvalid ; 

    wire [12:0]       w_port__AXI_ERAM_Controller_0__bid ;
    wire [12:0]       w_port__AXI_Matrix_0__ds0_bid ;
    wire [12:0]       w_net__AXI_ERAM_Controller_0__bid ; 

    wire              w_port__AXI_Matrix_0__ds0_bready ;
    wire              w_port__AXI_ERAM_Controller_0__bready ;
    wire              w_net__AXI_Matrix_0__ds0_bready ; 

    wire [1:0]        w_port__AXI_ERAM_Controller_0__bresp ;
    wire [1:0]        w_port__AXI_Matrix_0__ds0_bresp ;
    wire [1:0]        w_net__AXI_ERAM_Controller_0__bresp ; 

    wire              w_port__AXI_ERAM_Controller_0__bvalid ;
    wire              w_port__AXI_Matrix_0__ds0_bvalid ;
    wire              w_net__AXI_ERAM_Controller_0__bvalid ; 

    wire [31:0]       w_port__AXI_ERAM_Controller_0__rdata ;
    wire [31:0]       w_port__AXI_Matrix_0__ds0_rdata ;
    wire [31:0]       w_net__AXI_ERAM_Controller_0__rdata ; 

    wire [12:0]       w_port__AXI_ERAM_Controller_0__rid ;
    wire [12:0]       w_port__AXI_Matrix_0__ds0_rid ;
    wire [12:0]       w_net__AXI_ERAM_Controller_0__rid ; 

    wire              w_port__AXI_ERAM_Controller_0__rlast ;
    wire              w_port__AXI_Matrix_0__ds0_rlast ;
    wire              w_net__AXI_ERAM_Controller_0__rlast ; 

    wire              w_port__AXI_Matrix_0__ds0_rready ;
    wire              w_port__AXI_ERAM_Controller_0__rready ;
    wire              w_net__AXI_Matrix_0__ds0_rready ; 

    wire [1:0]        w_port__AXI_ERAM_Controller_0__rresp ;
    wire [1:0]        w_port__AXI_Matrix_0__ds0_rresp ;
    wire [1:0]        w_net__AXI_ERAM_Controller_0__rresp ; 

    wire              w_port__AXI_ERAM_Controller_0__rvalid ;
    wire              w_port__AXI_Matrix_0__ds0_rvalid ;
    wire              w_net__AXI_ERAM_Controller_0__rvalid ; 

    wire [31:0]       w_port__AXI_Matrix_0__ds0_wdata ;
    wire [31:0]       w_port__AXI_ERAM_Controller_0__wdata ;
    wire [31:0]       w_net__AXI_Matrix_0__ds0_wdata ; 

    wire              w_port__AXI_ERAM_Controller_0__wready ;
    wire              w_port__AXI_Matrix_0__ds0_wready ;
    wire              w_net__AXI_ERAM_Controller_0__wready ; 

    wire [3:0]        w_port__AXI_Matrix_0__ds0_wstrb ;
    wire [3:0]        w_port__AXI_ERAM_Controller_0__wstrb ;
    wire [3:0]        w_net__AXI_Matrix_0__ds0_wstrb ; 

    wire              w_port__AXI_Matrix_0__ds0_wvalid ;
    wire              w_port__AXI_ERAM_Controller_0__wvalid ;
    wire              w_net__AXI_Matrix_0__ds0_wvalid ; 


    wire [32:0]       w_port__AXI_Matrix_0__ds1_araddr ;
    wire [32:0]       w_port__AXI_Protocol_Converter_0__us_axi_araddr ;
    wire [32:0]       w_net__AXI_Matrix_0__ds1_araddr ; 

    wire [1:0]        w_port__AXI_Matrix_0__ds1_arburst ;
    wire [1:0]        w_port__AXI_Protocol_Converter_0__us_axi_arburst ;
    wire [1:0]        w_net__AXI_Matrix_0__ds1_arburst ; 

    wire [3:0]        w_port__AXI_Matrix_0__ds1_arcache ;
    wire [3:0]        w_port__AXI_Protocol_Converter_0__us_axi_arcache ;
    wire [3:0]        w_net__AXI_Matrix_0__ds1_arcache ; 

    wire [12:0]       w_port__AXI_Matrix_0__ds1_arid ;
    wire [12:0]       w_port__AXI_Protocol_Converter_0__us_axi_arid ;
    wire [12:0]       w_net__AXI_Matrix_0__ds1_arid ; 

    wire [7:0]        w_port__AXI_Matrix_0__ds1_arlen ;
    wire [7:0]        w_port__AXI_Protocol_Converter_0__us_axi_arlen ;
    wire [7:0]        w_net__AXI_Matrix_0__ds1_arlen ; 

    wire [0:0]        w_port__AXI_Matrix_0__ds1_arlock ;
    wire [0:0]        w_port__AXI_Protocol_Converter_0__us_axi_arlock ;
    wire [0:0]        w_net__AXI_Matrix_0__ds1_arlock ; 

    wire [2:0]        w_port__AXI_Matrix_0__ds1_arprot ;
    wire [2:0]        w_port__AXI_Protocol_Converter_0__us_axi_arprot ;
    wire [2:0]        w_net__AXI_Matrix_0__ds1_arprot ; 

    wire [3:0]        w_port__AXI_Matrix_0__ds1_arqos ;
    wire [3:0]        w_port__AXI_Protocol_Converter_0__us_axi_arqos ;
    wire [3:0]        w_net__AXI_Matrix_0__ds1_arqos ; 

    wire              w_port__AXI_Protocol_Converter_0__us_axi_arready ;
    wire              w_port__AXI_Matrix_0__ds1_arready ;
    wire              w_net__AXI_Protocol_Converter_0__us_axi_arready ; 

    wire [2:0]        w_port__AXI_Matrix_0__ds1_arsize ;
    wire [2:0]        w_port__AXI_Protocol_Converter_0__us_axi_arsize ;
    wire [2:0]        w_net__AXI_Matrix_0__ds1_arsize ; 

    wire              w_port__AXI_Matrix_0__ds1_arvalid ;
    wire              w_port__AXI_Protocol_Converter_0__us_axi_arvalid ;
    wire              w_net__AXI_Matrix_0__ds1_arvalid ; 

    wire [32:0]       w_port__AXI_Matrix_0__ds1_awaddr ;
    wire [32:0]       w_port__AXI_Protocol_Converter_0__us_axi_awaddr ;
    wire [32:0]       w_net__AXI_Matrix_0__ds1_awaddr ; 

    wire [1:0]        w_port__AXI_Matrix_0__ds1_awburst ;
    wire [1:0]        w_port__AXI_Protocol_Converter_0__us_axi_awburst ;
    wire [1:0]        w_net__AXI_Matrix_0__ds1_awburst ; 

    wire [3:0]        w_port__AXI_Matrix_0__ds1_awcache ;
    wire [3:0]        w_port__AXI_Protocol_Converter_0__us_axi_awcache ;
    wire [3:0]        w_net__AXI_Matrix_0__ds1_awcache ; 

    wire [12:0]       w_port__AXI_Matrix_0__ds1_awid ;
    wire [12:0]       w_port__AXI_Protocol_Converter_0__us_axi_awid ;
    wire [12:0]       w_net__AXI_Matrix_0__ds1_awid ; 

    wire [7:0]        w_port__AXI_Matrix_0__ds1_awlen ;
    wire [7:0]        w_port__AXI_Protocol_Converter_0__us_axi_awlen ;
    wire [7:0]        w_net__AXI_Matrix_0__ds1_awlen ; 

    wire [0:0]        w_port__AXI_Matrix_0__ds1_awlock ;
    wire [0:0]        w_port__AXI_Protocol_Converter_0__us_axi_awlock ;
    wire [0:0]        w_net__AXI_Matrix_0__ds1_awlock ; 

    wire [2:0]        w_port__AXI_Matrix_0__ds1_awprot ;
    wire [2:0]        w_port__AXI_Protocol_Converter_0__us_axi_awprot ;
    wire [2:0]        w_net__AXI_Matrix_0__ds1_awprot ; 

    wire [3:0]        w_port__AXI_Matrix_0__ds1_awqos ;
    wire [3:0]        w_port__AXI_Protocol_Converter_0__us_axi_awqos ;
    wire [3:0]        w_net__AXI_Matrix_0__ds1_awqos ; 

    wire              w_port__AXI_Protocol_Converter_0__us_axi_awready ;
    wire              w_port__AXI_Matrix_0__ds1_awready ;
    wire              w_net__AXI_Protocol_Converter_0__us_axi_awready ; 

    wire [2:0]        w_port__AXI_Matrix_0__ds1_awsize ;
    wire [2:0]        w_port__AXI_Protocol_Converter_0__us_axi_awsize ;
    wire [2:0]        w_net__AXI_Matrix_0__ds1_awsize ; 

    wire              w_port__AXI_Matrix_0__ds1_awvalid ;
    wire              w_port__AXI_Protocol_Converter_0__us_axi_awvalid ;
    wire              w_net__AXI_Matrix_0__ds1_awvalid ; 

    wire [12:0]       w_port__AXI_Protocol_Converter_0__us_axi_bid ;
    wire [12:0]       w_port__AXI_Matrix_0__ds1_bid ;
    wire [12:0]       w_net__AXI_Protocol_Converter_0__us_axi_bid ; 

    wire              w_port__AXI_Matrix_0__ds1_bready ;
    wire              w_port__AXI_Protocol_Converter_0__us_axi_bready ;
    wire              w_net__AXI_Matrix_0__ds1_bready ; 

    wire [1:0]        w_port__AXI_Protocol_Converter_0__us_axi_bresp ;
    wire [1:0]        w_port__AXI_Matrix_0__ds1_bresp ;
    wire [1:0]        w_net__AXI_Protocol_Converter_0__us_axi_bresp ; 

    wire              w_port__AXI_Protocol_Converter_0__us_axi_bvalid ;
    wire              w_port__AXI_Matrix_0__ds1_bvalid ;
    wire              w_net__AXI_Protocol_Converter_0__us_axi_bvalid ; 

    wire [31:0]       w_port__AXI_Protocol_Converter_0__us_axi_rdata ;
    wire [31:0]       w_port__AXI_Matrix_0__ds1_rdata ;
    wire [31:0]       w_net__AXI_Protocol_Converter_0__us_axi_rdata ; 

    wire [12:0]       w_port__AXI_Protocol_Converter_0__us_axi_rid ;
    wire [12:0]       w_port__AXI_Matrix_0__ds1_rid ;
    wire [12:0]       w_net__AXI_Protocol_Converter_0__us_axi_rid ; 

    wire              w_port__AXI_Protocol_Converter_0__us_axi_rlast ;
    wire              w_port__AXI_Matrix_0__ds1_rlast ;
    wire              w_net__AXI_Protocol_Converter_0__us_axi_rlast ; 

    wire              w_port__AXI_Matrix_0__ds1_rready ;
    wire              w_port__AXI_Protocol_Converter_0__us_axi_rready ;
    wire              w_net__AXI_Matrix_0__ds1_rready ; 

    wire [1:0]        w_port__AXI_Protocol_Converter_0__us_axi_rresp ;
    wire [1:0]        w_port__AXI_Matrix_0__ds1_rresp ;
    wire [1:0]        w_net__AXI_Protocol_Converter_0__us_axi_rresp ; 

    wire              w_port__AXI_Protocol_Converter_0__us_axi_rvalid ;
    wire              w_port__AXI_Matrix_0__ds1_rvalid ;
    wire              w_net__AXI_Protocol_Converter_0__us_axi_rvalid ; 

    wire [31:0]       w_port__AXI_Matrix_0__ds1_wdata ;
    wire [31:0]       w_port__AXI_Protocol_Converter_0__us_axi_wdata ;
    wire [31:0]       w_net__AXI_Matrix_0__ds1_wdata ; 

    wire              w_port__AXI_Matrix_0__ds1_wlast ;
    wire              w_port__AXI_Protocol_Converter_0__us_axi_wlast ;
    wire              w_net__AXI_Matrix_0__ds1_wlast ; 

    wire              w_port__AXI_Protocol_Converter_0__us_axi_wready ;
    wire              w_port__AXI_Matrix_0__ds1_wready ;
    wire              w_net__AXI_Protocol_Converter_0__us_axi_wready ; 

    wire [3:0]        w_port__AXI_Matrix_0__ds1_wstrb ;
    wire [3:0]        w_port__AXI_Protocol_Converter_0__us_axi_wstrb ;
    wire [3:0]        w_net__AXI_Matrix_0__ds1_wstrb ; 

    wire              w_port__AXI_Matrix_0__ds1_wvalid ;
    wire              w_port__AXI_Protocol_Converter_0__us_axi_wvalid ;
    wire              w_net__AXI_Matrix_0__ds1_wvalid ; 


    wire [32:0]       w_port__AXI_Protocol_Converter_0__ds_axi_awaddr ;
    wire [8:0]        w_port__AXI_GPIO_0__s_axi_awaddr ;
    wire [32:0]       w_net__AXI_Protocol_Converter_0__ds_axi_awaddr ; 

    wire              w_port__AXI_Protocol_Converter_0__ds_axi_awvalid ;
    wire              w_port__AXI_GPIO_0__s_axi_awvalid ;
    wire              w_net__AXI_Protocol_Converter_0__ds_axi_awvalid ; 

    wire              w_port__AXI_GPIO_0__s_axi_awready ;
    wire              w_port__AXI_Protocol_Converter_0__ds_axi_awready ;
    wire              w_net__AXI_GPIO_0__s_axi_awready ; 

    wire [31:0]       w_port__AXI_Protocol_Converter_0__ds_axi_wdata ;
    wire [31:0]       w_port__AXI_GPIO_0__s_axi_wdata ;
    wire [31:0]       w_net__AXI_Protocol_Converter_0__ds_axi_wdata ; 

    wire [3:0]        w_port__AXI_Protocol_Converter_0__ds_axi_wstrb ;
    wire [3:0]        w_port__AXI_GPIO_0__s_axi_wstrb ;
    wire [3:0]        w_net__AXI_Protocol_Converter_0__ds_axi_wstrb ; 

    wire              w_port__AXI_Protocol_Converter_0__ds_axi_wvalid ;
    wire              w_port__AXI_GPIO_0__s_axi_wvalid ;
    wire              w_net__AXI_Protocol_Converter_0__ds_axi_wvalid ; 

    wire              w_port__AXI_GPIO_0__s_axi_wready ;
    wire              w_port__AXI_Protocol_Converter_0__ds_axi_wready ;
    wire              w_net__AXI_GPIO_0__s_axi_wready ; 

    wire [1:0]        w_port__AXI_GPIO_0__s_axi_bresp ;
    wire [1:0]        w_port__AXI_Protocol_Converter_0__ds_axi_bresp ;
    wire [1:0]        w_net__AXI_GPIO_0__s_axi_bresp ; 

    wire              w_port__AXI_GPIO_0__s_axi_bvalid ;
    wire              w_port__AXI_Protocol_Converter_0__ds_axi_bvalid ;
    wire              w_net__AXI_GPIO_0__s_axi_bvalid ; 

    wire              w_port__AXI_Protocol_Converter_0__ds_axi_bready ;
    wire              w_port__AXI_GPIO_0__s_axi_bready ;
    wire              w_net__AXI_Protocol_Converter_0__ds_axi_bready ; 

    wire [32:0]       w_port__AXI_Protocol_Converter_0__ds_axi_araddr ;
    wire [8:0]        w_port__AXI_GPIO_0__s_axi_araddr ;
    wire [32:0]       w_net__AXI_Protocol_Converter_0__ds_axi_araddr ; 

    wire              w_port__AXI_Protocol_Converter_0__ds_axi_arvalid ;
    wire              w_port__AXI_GPIO_0__s_axi_arvalid ;
    wire              w_net__AXI_Protocol_Converter_0__ds_axi_arvalid ; 

    wire              w_port__AXI_GPIO_0__s_axi_arready ;
    wire              w_port__AXI_Protocol_Converter_0__ds_axi_arready ;
    wire              w_net__AXI_GPIO_0__s_axi_arready ; 

    wire [31:0]       w_port__AXI_GPIO_0__s_axi_rdata ;
    wire [31:0]       w_port__AXI_Protocol_Converter_0__ds_axi_rdata ;
    wire [31:0]       w_net__AXI_GPIO_0__s_axi_rdata ; 

    wire [1:0]        w_port__AXI_GPIO_0__s_axi_rresp ;
    wire [1:0]        w_port__AXI_Protocol_Converter_0__ds_axi_rresp ;
    wire [1:0]        w_net__AXI_GPIO_0__s_axi_rresp ; 

    wire              w_port__AXI_GPIO_0__s_axi_rvalid ;
    wire              w_port__AXI_Protocol_Converter_0__ds_axi_rvalid ;
    wire              w_net__AXI_GPIO_0__s_axi_rvalid ; 

    wire              w_port__AXI_Protocol_Converter_0__ds_axi_rready ;
    wire              w_port__AXI_GPIO_0__s_axi_rready ;
    wire              w_net__AXI_Protocol_Converter_0__ds_axi_rready ; 

    wire [31:0]       w_port__AXI_GPIO_0__gpio_io_o ;
    wire [31:0]       w_net__AXI_GPIO_0__gpio_io_o ; 

    wire [1:0]        w_port__AXI_GPIO_0__gpio2_io_o ;
    wire [1:0]        w_net__AXI_GPIO_0__gpio2_io_o ; 

    assign w_net__ARM_Processor_System_0__p2f_clk0 = w_port__ARM_Processor_System_0__p2f_clk0 ;
    assign w_port__ARM_Processor_System_0__master_gp0_axi_aclk = w_net__ARM_Processor_System_0__p2f_clk0 ;
    assign w_port__ARM_Processor_System_0__slave_hp0_axi_aclk = w_net__ARM_Processor_System_0__p2f_clk0 ;
    assign w_port__Processor_System_Reset_0__clk = w_net__ARM_Processor_System_0__p2f_clk0 ;
    assign w_port__AXI_ERAM_Controller_0__aclk = w_net__ARM_Processor_System_0__p2f_clk0 ;
    assign w_port__AXI_GPIO_0__s_axi_aclk = w_net__ARM_Processor_System_0__p2f_clk0 ;
    assign w_port__AXI_Matrix_0__aclk = w_net__ARM_Processor_System_0__p2f_clk0 ;
    assign w_port__AXI_Protocol_Converter_0__aclk = w_net__ARM_Processor_System_0__p2f_clk0 ;
    assign motor_clk = w_net__ARM_Processor_System_0__p2f_clk0 ;

    assign w_net__ARM_Processor_System_0__p2f_rst0_n = w_port__ARM_Processor_System_0__p2f_rst0_n ;
    assign w_port__Processor_System_Reset_0__external_resetn = w_net__ARM_Processor_System_0__p2f_rst0_n ;

    assign w_net__Constant_0__dout = w_port__Constant_0__dout ;
    assign w_port__Processor_System_Reset_0__aux_reset = w_net__Constant_0__dout ;
    assign w_port__Processor_System_Reset_0__system_rst = w_net__Constant_0__dout ;

    assign w_net__Constant_1__dout = w_port__Constant_1__dout ;
    assign w_port__Processor_System_Reset_0__pll_locked = w_net__Constant_1__dout ;

    assign w_net__Processor_System_Reset_0__peripheral_aresetn = w_port__Processor_System_Reset_0__peripheral_aresetn ;
    assign w_port__AXI_ERAM_Controller_0__aresetn = w_net__Processor_System_Reset_0__peripheral_aresetn ;
    assign w_port__AXI_GPIO_0__s_axi_aresetn = w_net__Processor_System_Reset_0__peripheral_aresetn ;
    assign motor_resetn = w_net__Processor_System_Reset_0__peripheral_aresetn ;

    assign w_net__Processor_System_Reset_0__interconnect_aresetn = w_port__Processor_System_Reset_0__interconnect_aresetn ;
    assign w_port__AXI_Matrix_0__aresetn = w_net__Processor_System_Reset_0__interconnect_aresetn ;
    assign w_port__AXI_Protocol_Converter_0__aresetn = w_net__Processor_System_Reset_0__interconnect_aresetn ;


    assign w_net__ARM_Processor_System_0__master_gp0_axi_araddr = w_port__ARM_Processor_System_0__master_gp0_axi_araddr ;
    assign w_port__AXI_Matrix_0__us0_araddr = w_net__ARM_Processor_System_0__master_gp0_axi_araddr ;

    assign w_net__ARM_Processor_System_0__master_gp0_axi_arburst = w_port__ARM_Processor_System_0__master_gp0_axi_arburst ;
    assign w_port__AXI_Matrix_0__us0_arburst = w_net__ARM_Processor_System_0__master_gp0_axi_arburst ;

    assign w_net__ARM_Processor_System_0__master_gp0_axi_arcache = w_port__ARM_Processor_System_0__master_gp0_axi_arcache ;
    assign w_port__AXI_Matrix_0__us0_arcache = w_net__ARM_Processor_System_0__master_gp0_axi_arcache ;

    assign w_net__ARM_Processor_System_0__master_gp0_axi_arid = w_port__ARM_Processor_System_0__master_gp0_axi_arid ;
    assign w_port__AXI_Matrix_0__us0_arid = w_net__ARM_Processor_System_0__master_gp0_axi_arid ;

    assign w_net__ARM_Processor_System_0__master_gp0_axi_arlen = w_port__ARM_Processor_System_0__master_gp0_axi_arlen ;
    assign w_port__AXI_Matrix_0__us0_arlen = {4'b0,w_net__ARM_Processor_System_0__master_gp0_axi_arlen} ;

    assign w_net__ARM_Processor_System_0__master_gp0_axi_arlock = w_port__ARM_Processor_System_0__master_gp0_axi_arlock ;
    assign w_port__AXI_Matrix_0__us0_arlock = w_net__ARM_Processor_System_0__master_gp0_axi_arlock ;

    assign w_net__ARM_Processor_System_0__master_gp0_axi_arprot = w_port__ARM_Processor_System_0__master_gp0_axi_arprot ;
    assign w_port__AXI_Matrix_0__us0_arprot = w_net__ARM_Processor_System_0__master_gp0_axi_arprot ;

    assign w_net__AXI_Matrix_0__us0_arready = w_port__AXI_Matrix_0__us0_arready ;
    assign w_port__ARM_Processor_System_0__master_gp0_axi_arready = w_net__AXI_Matrix_0__us0_arready ;

    assign w_net__ARM_Processor_System_0__master_gp0_axi_arsize = w_port__ARM_Processor_System_0__master_gp0_axi_arsize ;
    assign w_port__AXI_Matrix_0__us0_arsize = {1'b0,w_net__ARM_Processor_System_0__master_gp0_axi_arsize} ;

    assign w_net__ARM_Processor_System_0__master_gp0_axi_arvalid = w_port__ARM_Processor_System_0__master_gp0_axi_arvalid ;
    assign w_port__AXI_Matrix_0__us0_arvalid = w_net__ARM_Processor_System_0__master_gp0_axi_arvalid ;

    assign w_net__ARM_Processor_System_0__master_gp0_axi_awaddr = w_port__ARM_Processor_System_0__master_gp0_axi_awaddr ;
    assign w_port__AXI_Matrix_0__us0_awaddr = w_net__ARM_Processor_System_0__master_gp0_axi_awaddr ;

    assign w_net__ARM_Processor_System_0__master_gp0_axi_awburst = w_port__ARM_Processor_System_0__master_gp0_axi_awburst ;
    assign w_port__AXI_Matrix_0__us0_awburst = w_net__ARM_Processor_System_0__master_gp0_axi_awburst ;

    assign w_net__ARM_Processor_System_0__master_gp0_axi_awcache = w_port__ARM_Processor_System_0__master_gp0_axi_awcache ;
    assign w_port__AXI_Matrix_0__us0_awcache = w_net__ARM_Processor_System_0__master_gp0_axi_awcache ;

    assign w_net__ARM_Processor_System_0__master_gp0_axi_awid = w_port__ARM_Processor_System_0__master_gp0_axi_awid ;
    assign w_port__AXI_Matrix_0__us0_awid = w_net__ARM_Processor_System_0__master_gp0_axi_awid ;

    assign w_net__ARM_Processor_System_0__master_gp0_axi_awlen = w_port__ARM_Processor_System_0__master_gp0_axi_awlen ;
    assign w_port__AXI_Matrix_0__us0_awlen = {4'b0,w_net__ARM_Processor_System_0__master_gp0_axi_awlen} ;

    assign w_net__ARM_Processor_System_0__master_gp0_axi_awlock = w_port__ARM_Processor_System_0__master_gp0_axi_awlock ;
    assign w_port__AXI_Matrix_0__us0_awlock = w_net__ARM_Processor_System_0__master_gp0_axi_awlock ;

    assign w_net__ARM_Processor_System_0__master_gp0_axi_awprot = w_port__ARM_Processor_System_0__master_gp0_axi_awprot ;
    assign w_port__AXI_Matrix_0__us0_awprot = w_net__ARM_Processor_System_0__master_gp0_axi_awprot ;

    assign w_net__AXI_Matrix_0__us0_awready = w_port__AXI_Matrix_0__us0_awready ;
    assign w_port__ARM_Processor_System_0__master_gp0_axi_awready = w_net__AXI_Matrix_0__us0_awready ;

    assign w_net__ARM_Processor_System_0__master_gp0_axi_awsize = w_port__ARM_Processor_System_0__master_gp0_axi_awsize ;
    assign w_port__AXI_Matrix_0__us0_awsize = {1'b0,w_net__ARM_Processor_System_0__master_gp0_axi_awsize} ;

    assign w_net__ARM_Processor_System_0__master_gp0_axi_awvalid = w_port__ARM_Processor_System_0__master_gp0_axi_awvalid ;
    assign w_port__AXI_Matrix_0__us0_awvalid = w_net__ARM_Processor_System_0__master_gp0_axi_awvalid ;

    assign w_net__AXI_Matrix_0__us0_bid = w_port__AXI_Matrix_0__us0_bid ;
    assign w_port__ARM_Processor_System_0__master_gp0_axi_bid = w_net__AXI_Matrix_0__us0_bid ;

    assign w_net__ARM_Processor_System_0__master_gp0_axi_bready = w_port__ARM_Processor_System_0__master_gp0_axi_bready ;
    assign w_port__AXI_Matrix_0__us0_bready = w_net__ARM_Processor_System_0__master_gp0_axi_bready ;

    assign w_net__AXI_Matrix_0__us0_bresp = w_port__AXI_Matrix_0__us0_bresp ;
    assign w_port__ARM_Processor_System_0__master_gp0_axi_bresp = w_net__AXI_Matrix_0__us0_bresp ;

    assign w_net__AXI_Matrix_0__us0_bvalid = w_port__AXI_Matrix_0__us0_bvalid ;
    assign w_port__ARM_Processor_System_0__master_gp0_axi_bvalid = w_net__AXI_Matrix_0__us0_bvalid ;

    assign w_net__AXI_Matrix_0__us0_rdata = w_port__AXI_Matrix_0__us0_rdata ;
    assign w_port__ARM_Processor_System_0__master_gp0_axi_rdata = w_net__AXI_Matrix_0__us0_rdata ;

    assign w_net__AXI_Matrix_0__us0_rid = w_port__AXI_Matrix_0__us0_rid ;
    assign w_port__ARM_Processor_System_0__master_gp0_axi_rid = w_net__AXI_Matrix_0__us0_rid ;

    assign w_net__AXI_Matrix_0__us0_rlast = w_port__AXI_Matrix_0__us0_rlast ;
    assign w_port__ARM_Processor_System_0__master_gp0_axi_rlast = w_net__AXI_Matrix_0__us0_rlast ;

    assign w_net__ARM_Processor_System_0__master_gp0_axi_rready = w_port__ARM_Processor_System_0__master_gp0_axi_rready ;
    assign w_port__AXI_Matrix_0__us0_rready = w_net__ARM_Processor_System_0__master_gp0_axi_rready ;

    assign w_net__AXI_Matrix_0__us0_rresp = w_port__AXI_Matrix_0__us0_rresp ;
    assign w_port__ARM_Processor_System_0__master_gp0_axi_rresp = w_net__AXI_Matrix_0__us0_rresp ;

    assign w_net__AXI_Matrix_0__us0_rvalid = w_port__AXI_Matrix_0__us0_rvalid ;
    assign w_port__ARM_Processor_System_0__master_gp0_axi_rvalid = w_net__AXI_Matrix_0__us0_rvalid ;

    assign w_net__ARM_Processor_System_0__master_gp0_axi_wdata = w_port__ARM_Processor_System_0__master_gp0_axi_wdata ;
    assign w_port__AXI_Matrix_0__us0_wdata = w_net__ARM_Processor_System_0__master_gp0_axi_wdata ;

    assign w_net__ARM_Processor_System_0__master_gp0_axi_wlast = w_port__ARM_Processor_System_0__master_gp0_axi_wlast ;
    assign w_port__AXI_Matrix_0__us0_wlast = w_net__ARM_Processor_System_0__master_gp0_axi_wlast ;

    assign w_net__AXI_Matrix_0__us0_wready = w_port__AXI_Matrix_0__us0_wready ;
    assign w_port__ARM_Processor_System_0__master_gp0_axi_wready = w_net__AXI_Matrix_0__us0_wready ;

    assign w_net__ARM_Processor_System_0__master_gp0_axi_wstrb = w_port__ARM_Processor_System_0__master_gp0_axi_wstrb ;
    assign w_port__AXI_Matrix_0__us0_wstrb = w_net__ARM_Processor_System_0__master_gp0_axi_wstrb ;

    assign w_net__ARM_Processor_System_0__master_gp0_axi_wvalid = w_port__ARM_Processor_System_0__master_gp0_axi_wvalid ;
    assign w_port__AXI_Matrix_0__us0_wvalid = w_net__ARM_Processor_System_0__master_gp0_axi_wvalid ;


    assign w_net__AXI_Matrix_0__ds0_araddr = w_port__AXI_Matrix_0__ds0_araddr ;
    assign w_port__AXI_ERAM_Controller_0__araddr = w_net__AXI_Matrix_0__ds0_araddr ;

    assign w_net__AXI_Matrix_0__ds0_arburst = w_port__AXI_Matrix_0__ds0_arburst ;
    assign w_port__AXI_ERAM_Controller_0__arburst = w_net__AXI_Matrix_0__ds0_arburst ;

    assign w_net__AXI_Matrix_0__ds0_arid = w_port__AXI_Matrix_0__ds0_arid ;
    assign w_port__AXI_ERAM_Controller_0__arid = w_net__AXI_Matrix_0__ds0_arid ;

    assign w_net__AXI_Matrix_0__ds0_arlen = w_port__AXI_Matrix_0__ds0_arlen ;
    assign w_port__AXI_ERAM_Controller_0__arlen = w_net__AXI_Matrix_0__ds0_arlen ;

    assign w_net__AXI_Matrix_0__ds0_arlock = w_port__AXI_Matrix_0__ds0_arlock ;
    assign w_port__AXI_ERAM_Controller_0__arlock = w_net__AXI_Matrix_0__ds0_arlock ;

    assign w_net__AXI_ERAM_Controller_0__arready = w_port__AXI_ERAM_Controller_0__arready ;
    assign w_port__AXI_Matrix_0__ds0_arready = w_net__AXI_ERAM_Controller_0__arready ;

    assign w_net__AXI_Matrix_0__ds0_arsize = w_port__AXI_Matrix_0__ds0_arsize ;
    assign w_port__AXI_ERAM_Controller_0__arsize = w_net__AXI_Matrix_0__ds0_arsize ;

    assign w_net__AXI_Matrix_0__ds0_arvalid = w_port__AXI_Matrix_0__ds0_arvalid ;
    assign w_port__AXI_ERAM_Controller_0__arvalid = w_net__AXI_Matrix_0__ds0_arvalid ;

    assign w_net__AXI_Matrix_0__ds0_awaddr = w_port__AXI_Matrix_0__ds0_awaddr ;
    assign w_port__AXI_ERAM_Controller_0__awaddr = w_net__AXI_Matrix_0__ds0_awaddr ;

    assign w_net__AXI_Matrix_0__ds0_awburst = w_port__AXI_Matrix_0__ds0_awburst ;
    assign w_port__AXI_ERAM_Controller_0__awburst = w_net__AXI_Matrix_0__ds0_awburst ;

    assign w_net__AXI_Matrix_0__ds0_awid = w_port__AXI_Matrix_0__ds0_awid ;
    assign w_port__AXI_ERAM_Controller_0__awid = w_net__AXI_Matrix_0__ds0_awid ;

    assign w_net__AXI_Matrix_0__ds0_awlen = w_port__AXI_Matrix_0__ds0_awlen ;
    assign w_port__AXI_ERAM_Controller_0__awlen = w_net__AXI_Matrix_0__ds0_awlen ;

    assign w_net__AXI_Matrix_0__ds0_awlock = w_port__AXI_Matrix_0__ds0_awlock ;
    assign w_port__AXI_ERAM_Controller_0__awlock = w_net__AXI_Matrix_0__ds0_awlock ;

    assign w_net__AXI_ERAM_Controller_0__awready = w_port__AXI_ERAM_Controller_0__awready ;
    assign w_port__AXI_Matrix_0__ds0_awready = w_net__AXI_ERAM_Controller_0__awready ;

    assign w_net__AXI_Matrix_0__ds0_awsize = w_port__AXI_Matrix_0__ds0_awsize ;
    assign w_port__AXI_ERAM_Controller_0__awsize = w_net__AXI_Matrix_0__ds0_awsize ;

    assign w_net__AXI_Matrix_0__ds0_awvalid = w_port__AXI_Matrix_0__ds0_awvalid ;
    assign w_port__AXI_ERAM_Controller_0__awvalid = w_net__AXI_Matrix_0__ds0_awvalid ;

    assign w_net__AXI_ERAM_Controller_0__bid = w_port__AXI_ERAM_Controller_0__bid ;
    assign w_port__AXI_Matrix_0__ds0_bid = w_net__AXI_ERAM_Controller_0__bid ;

    assign w_net__AXI_Matrix_0__ds0_bready = w_port__AXI_Matrix_0__ds0_bready ;
    assign w_port__AXI_ERAM_Controller_0__bready = w_net__AXI_Matrix_0__ds0_bready ;

    assign w_net__AXI_ERAM_Controller_0__bresp = w_port__AXI_ERAM_Controller_0__bresp ;
    assign w_port__AXI_Matrix_0__ds0_bresp = w_net__AXI_ERAM_Controller_0__bresp ;

    assign w_net__AXI_ERAM_Controller_0__bvalid = w_port__AXI_ERAM_Controller_0__bvalid ;
    assign w_port__AXI_Matrix_0__ds0_bvalid = w_net__AXI_ERAM_Controller_0__bvalid ;

    assign w_net__AXI_ERAM_Controller_0__rdata = w_port__AXI_ERAM_Controller_0__rdata ;
    assign w_port__AXI_Matrix_0__ds0_rdata = w_net__AXI_ERAM_Controller_0__rdata ;

    assign w_net__AXI_ERAM_Controller_0__rid = w_port__AXI_ERAM_Controller_0__rid ;
    assign w_port__AXI_Matrix_0__ds0_rid = w_net__AXI_ERAM_Controller_0__rid ;

    assign w_net__AXI_ERAM_Controller_0__rlast = w_port__AXI_ERAM_Controller_0__rlast ;
    assign w_port__AXI_Matrix_0__ds0_rlast = w_net__AXI_ERAM_Controller_0__rlast ;

    assign w_net__AXI_Matrix_0__ds0_rready = w_port__AXI_Matrix_0__ds0_rready ;
    assign w_port__AXI_ERAM_Controller_0__rready = w_net__AXI_Matrix_0__ds0_rready ;

    assign w_net__AXI_ERAM_Controller_0__rresp = w_port__AXI_ERAM_Controller_0__rresp ;
    assign w_port__AXI_Matrix_0__ds0_rresp = w_net__AXI_ERAM_Controller_0__rresp ;

    assign w_net__AXI_ERAM_Controller_0__rvalid = w_port__AXI_ERAM_Controller_0__rvalid ;
    assign w_port__AXI_Matrix_0__ds0_rvalid = w_net__AXI_ERAM_Controller_0__rvalid ;

    assign w_net__AXI_Matrix_0__ds0_wdata = w_port__AXI_Matrix_0__ds0_wdata ;
    assign w_port__AXI_ERAM_Controller_0__wdata = w_net__AXI_Matrix_0__ds0_wdata ;

    assign w_net__AXI_ERAM_Controller_0__wready = w_port__AXI_ERAM_Controller_0__wready ;
    assign w_port__AXI_Matrix_0__ds0_wready = w_net__AXI_ERAM_Controller_0__wready ;

    assign w_net__AXI_Matrix_0__ds0_wstrb = w_port__AXI_Matrix_0__ds0_wstrb ;
    assign w_port__AXI_ERAM_Controller_0__wstrb = w_net__AXI_Matrix_0__ds0_wstrb ;

    assign w_net__AXI_Matrix_0__ds0_wvalid = w_port__AXI_Matrix_0__ds0_wvalid ;
    assign w_port__AXI_ERAM_Controller_0__wvalid = w_net__AXI_Matrix_0__ds0_wvalid ;


    assign w_net__AXI_Matrix_0__ds1_araddr = w_port__AXI_Matrix_0__ds1_araddr ;
    assign w_port__AXI_Protocol_Converter_0__us_axi_araddr = w_net__AXI_Matrix_0__ds1_araddr ;

    assign w_net__AXI_Matrix_0__ds1_arburst = w_port__AXI_Matrix_0__ds1_arburst ;
    assign w_port__AXI_Protocol_Converter_0__us_axi_arburst = w_net__AXI_Matrix_0__ds1_arburst ;

    assign w_net__AXI_Matrix_0__ds1_arcache = w_port__AXI_Matrix_0__ds1_arcache ;
    assign w_port__AXI_Protocol_Converter_0__us_axi_arcache = w_net__AXI_Matrix_0__ds1_arcache ;

    assign w_net__AXI_Matrix_0__ds1_arid = w_port__AXI_Matrix_0__ds1_arid ;
    assign w_port__AXI_Protocol_Converter_0__us_axi_arid = w_net__AXI_Matrix_0__ds1_arid ;

    assign w_net__AXI_Matrix_0__ds1_arlen = w_port__AXI_Matrix_0__ds1_arlen ;
    assign w_port__AXI_Protocol_Converter_0__us_axi_arlen = w_net__AXI_Matrix_0__ds1_arlen ;

    assign w_net__AXI_Matrix_0__ds1_arlock = w_port__AXI_Matrix_0__ds1_arlock ;
    assign w_port__AXI_Protocol_Converter_0__us_axi_arlock = w_net__AXI_Matrix_0__ds1_arlock ;

    assign w_net__AXI_Matrix_0__ds1_arprot = w_port__AXI_Matrix_0__ds1_arprot ;
    assign w_port__AXI_Protocol_Converter_0__us_axi_arprot = w_net__AXI_Matrix_0__ds1_arprot ;

    assign w_net__AXI_Matrix_0__ds1_arqos = w_port__AXI_Matrix_0__ds1_arqos ;
    assign w_port__AXI_Protocol_Converter_0__us_axi_arqos = w_net__AXI_Matrix_0__ds1_arqos ;

    assign w_net__AXI_Protocol_Converter_0__us_axi_arready = w_port__AXI_Protocol_Converter_0__us_axi_arready ;
    assign w_port__AXI_Matrix_0__ds1_arready = w_net__AXI_Protocol_Converter_0__us_axi_arready ;

    assign w_net__AXI_Matrix_0__ds1_arsize = w_port__AXI_Matrix_0__ds1_arsize ;
    assign w_port__AXI_Protocol_Converter_0__us_axi_arsize = w_net__AXI_Matrix_0__ds1_arsize ;

    assign w_net__AXI_Matrix_0__ds1_arvalid = w_port__AXI_Matrix_0__ds1_arvalid ;
    assign w_port__AXI_Protocol_Converter_0__us_axi_arvalid = w_net__AXI_Matrix_0__ds1_arvalid ;

    assign w_net__AXI_Matrix_0__ds1_awaddr = w_port__AXI_Matrix_0__ds1_awaddr ;
    assign w_port__AXI_Protocol_Converter_0__us_axi_awaddr = w_net__AXI_Matrix_0__ds1_awaddr ;

    assign w_net__AXI_Matrix_0__ds1_awburst = w_port__AXI_Matrix_0__ds1_awburst ;
    assign w_port__AXI_Protocol_Converter_0__us_axi_awburst = w_net__AXI_Matrix_0__ds1_awburst ;

    assign w_net__AXI_Matrix_0__ds1_awcache = w_port__AXI_Matrix_0__ds1_awcache ;
    assign w_port__AXI_Protocol_Converter_0__us_axi_awcache = w_net__AXI_Matrix_0__ds1_awcache ;

    assign w_net__AXI_Matrix_0__ds1_awid = w_port__AXI_Matrix_0__ds1_awid ;
    assign w_port__AXI_Protocol_Converter_0__us_axi_awid = w_net__AXI_Matrix_0__ds1_awid ;

    assign w_net__AXI_Matrix_0__ds1_awlen = w_port__AXI_Matrix_0__ds1_awlen ;
    assign w_port__AXI_Protocol_Converter_0__us_axi_awlen = w_net__AXI_Matrix_0__ds1_awlen ;

    assign w_net__AXI_Matrix_0__ds1_awlock = w_port__AXI_Matrix_0__ds1_awlock ;
    assign w_port__AXI_Protocol_Converter_0__us_axi_awlock = w_net__AXI_Matrix_0__ds1_awlock ;

    assign w_net__AXI_Matrix_0__ds1_awprot = w_port__AXI_Matrix_0__ds1_awprot ;
    assign w_port__AXI_Protocol_Converter_0__us_axi_awprot = w_net__AXI_Matrix_0__ds1_awprot ;

    assign w_net__AXI_Matrix_0__ds1_awqos = w_port__AXI_Matrix_0__ds1_awqos ;
    assign w_port__AXI_Protocol_Converter_0__us_axi_awqos = w_net__AXI_Matrix_0__ds1_awqos ;

    assign w_net__AXI_Protocol_Converter_0__us_axi_awready = w_port__AXI_Protocol_Converter_0__us_axi_awready ;
    assign w_port__AXI_Matrix_0__ds1_awready = w_net__AXI_Protocol_Converter_0__us_axi_awready ;

    assign w_net__AXI_Matrix_0__ds1_awsize = w_port__AXI_Matrix_0__ds1_awsize ;
    assign w_port__AXI_Protocol_Converter_0__us_axi_awsize = w_net__AXI_Matrix_0__ds1_awsize ;

    assign w_net__AXI_Matrix_0__ds1_awvalid = w_port__AXI_Matrix_0__ds1_awvalid ;
    assign w_port__AXI_Protocol_Converter_0__us_axi_awvalid = w_net__AXI_Matrix_0__ds1_awvalid ;

    assign w_net__AXI_Protocol_Converter_0__us_axi_bid = w_port__AXI_Protocol_Converter_0__us_axi_bid ;
    assign w_port__AXI_Matrix_0__ds1_bid = w_net__AXI_Protocol_Converter_0__us_axi_bid ;

    assign w_net__AXI_Matrix_0__ds1_bready = w_port__AXI_Matrix_0__ds1_bready ;
    assign w_port__AXI_Protocol_Converter_0__us_axi_bready = w_net__AXI_Matrix_0__ds1_bready ;

    assign w_net__AXI_Protocol_Converter_0__us_axi_bresp = w_port__AXI_Protocol_Converter_0__us_axi_bresp ;
    assign w_port__AXI_Matrix_0__ds1_bresp = w_net__AXI_Protocol_Converter_0__us_axi_bresp ;

    assign w_net__AXI_Protocol_Converter_0__us_axi_bvalid = w_port__AXI_Protocol_Converter_0__us_axi_bvalid ;
    assign w_port__AXI_Matrix_0__ds1_bvalid = w_net__AXI_Protocol_Converter_0__us_axi_bvalid ;

    assign w_net__AXI_Protocol_Converter_0__us_axi_rdata = w_port__AXI_Protocol_Converter_0__us_axi_rdata ;
    assign w_port__AXI_Matrix_0__ds1_rdata = w_net__AXI_Protocol_Converter_0__us_axi_rdata ;

    assign w_net__AXI_Protocol_Converter_0__us_axi_rid = w_port__AXI_Protocol_Converter_0__us_axi_rid ;
    assign w_port__AXI_Matrix_0__ds1_rid = w_net__AXI_Protocol_Converter_0__us_axi_rid ;

    assign w_net__AXI_Protocol_Converter_0__us_axi_rlast = w_port__AXI_Protocol_Converter_0__us_axi_rlast ;
    assign w_port__AXI_Matrix_0__ds1_rlast = w_net__AXI_Protocol_Converter_0__us_axi_rlast ;

    assign w_net__AXI_Matrix_0__ds1_rready = w_port__AXI_Matrix_0__ds1_rready ;
    assign w_port__AXI_Protocol_Converter_0__us_axi_rready = w_net__AXI_Matrix_0__ds1_rready ;

    assign w_net__AXI_Protocol_Converter_0__us_axi_rresp = w_port__AXI_Protocol_Converter_0__us_axi_rresp ;
    assign w_port__AXI_Matrix_0__ds1_rresp = w_net__AXI_Protocol_Converter_0__us_axi_rresp ;

    assign w_net__AXI_Protocol_Converter_0__us_axi_rvalid = w_port__AXI_Protocol_Converter_0__us_axi_rvalid ;
    assign w_port__AXI_Matrix_0__ds1_rvalid = w_net__AXI_Protocol_Converter_0__us_axi_rvalid ;

    assign w_net__AXI_Matrix_0__ds1_wdata = w_port__AXI_Matrix_0__ds1_wdata ;
    assign w_port__AXI_Protocol_Converter_0__us_axi_wdata = w_net__AXI_Matrix_0__ds1_wdata ;

    assign w_net__AXI_Matrix_0__ds1_wlast = w_port__AXI_Matrix_0__ds1_wlast ;
    assign w_port__AXI_Protocol_Converter_0__us_axi_wlast = w_net__AXI_Matrix_0__ds1_wlast ;

    assign w_net__AXI_Protocol_Converter_0__us_axi_wready = w_port__AXI_Protocol_Converter_0__us_axi_wready ;
    assign w_port__AXI_Matrix_0__ds1_wready = w_net__AXI_Protocol_Converter_0__us_axi_wready ;

    assign w_net__AXI_Matrix_0__ds1_wstrb = w_port__AXI_Matrix_0__ds1_wstrb ;
    assign w_port__AXI_Protocol_Converter_0__us_axi_wstrb = w_net__AXI_Matrix_0__ds1_wstrb ;

    assign w_net__AXI_Matrix_0__ds1_wvalid = w_port__AXI_Matrix_0__ds1_wvalid ;
    assign w_port__AXI_Protocol_Converter_0__us_axi_wvalid = w_net__AXI_Matrix_0__ds1_wvalid ;


    assign w_net__AXI_Protocol_Converter_0__ds_axi_awaddr = w_port__AXI_Protocol_Converter_0__ds_axi_awaddr ;
    assign w_port__AXI_GPIO_0__s_axi_awaddr = w_net__AXI_Protocol_Converter_0__ds_axi_awaddr ;

    assign w_net__AXI_Protocol_Converter_0__ds_axi_awvalid = w_port__AXI_Protocol_Converter_0__ds_axi_awvalid ;
    assign w_port__AXI_GPIO_0__s_axi_awvalid = w_net__AXI_Protocol_Converter_0__ds_axi_awvalid ;

    assign w_net__AXI_GPIO_0__s_axi_awready = w_port__AXI_GPIO_0__s_axi_awready ;
    assign w_port__AXI_Protocol_Converter_0__ds_axi_awready = w_net__AXI_GPIO_0__s_axi_awready ;

    assign w_net__AXI_Protocol_Converter_0__ds_axi_wdata = w_port__AXI_Protocol_Converter_0__ds_axi_wdata ;
    assign w_port__AXI_GPIO_0__s_axi_wdata = w_net__AXI_Protocol_Converter_0__ds_axi_wdata ;

    assign w_net__AXI_Protocol_Converter_0__ds_axi_wstrb = w_port__AXI_Protocol_Converter_0__ds_axi_wstrb ;
    assign w_port__AXI_GPIO_0__s_axi_wstrb = w_net__AXI_Protocol_Converter_0__ds_axi_wstrb ;

    assign w_net__AXI_Protocol_Converter_0__ds_axi_wvalid = w_port__AXI_Protocol_Converter_0__ds_axi_wvalid ;
    assign w_port__AXI_GPIO_0__s_axi_wvalid = w_net__AXI_Protocol_Converter_0__ds_axi_wvalid ;

    assign w_net__AXI_GPIO_0__s_axi_wready = w_port__AXI_GPIO_0__s_axi_wready ;
    assign w_port__AXI_Protocol_Converter_0__ds_axi_wready = w_net__AXI_GPIO_0__s_axi_wready ;

    assign w_net__AXI_GPIO_0__s_axi_bresp = w_port__AXI_GPIO_0__s_axi_bresp ;
    assign w_port__AXI_Protocol_Converter_0__ds_axi_bresp = w_net__AXI_GPIO_0__s_axi_bresp ;

    assign w_net__AXI_GPIO_0__s_axi_bvalid = w_port__AXI_GPIO_0__s_axi_bvalid ;
    assign w_port__AXI_Protocol_Converter_0__ds_axi_bvalid = w_net__AXI_GPIO_0__s_axi_bvalid ;

    assign w_net__AXI_Protocol_Converter_0__ds_axi_bready = w_port__AXI_Protocol_Converter_0__ds_axi_bready ;
    assign w_port__AXI_GPIO_0__s_axi_bready = w_net__AXI_Protocol_Converter_0__ds_axi_bready ;

    assign w_net__AXI_Protocol_Converter_0__ds_axi_araddr = w_port__AXI_Protocol_Converter_0__ds_axi_araddr ;
    assign w_port__AXI_GPIO_0__s_axi_araddr = w_net__AXI_Protocol_Converter_0__ds_axi_araddr ;

    assign w_net__AXI_Protocol_Converter_0__ds_axi_arvalid = w_port__AXI_Protocol_Converter_0__ds_axi_arvalid ;
    assign w_port__AXI_GPIO_0__s_axi_arvalid = w_net__AXI_Protocol_Converter_0__ds_axi_arvalid ;

    assign w_net__AXI_GPIO_0__s_axi_arready = w_port__AXI_GPIO_0__s_axi_arready ;
    assign w_port__AXI_Protocol_Converter_0__ds_axi_arready = w_net__AXI_GPIO_0__s_axi_arready ;

    assign w_net__AXI_GPIO_0__s_axi_rdata = w_port__AXI_GPIO_0__s_axi_rdata ;
    assign w_port__AXI_Protocol_Converter_0__ds_axi_rdata = w_net__AXI_GPIO_0__s_axi_rdata ;

    assign w_net__AXI_GPIO_0__s_axi_rresp = w_port__AXI_GPIO_0__s_axi_rresp ;
    assign w_port__AXI_Protocol_Converter_0__ds_axi_rresp = w_net__AXI_GPIO_0__s_axi_rresp ;

    assign w_net__AXI_GPIO_0__s_axi_rvalid = w_port__AXI_GPIO_0__s_axi_rvalid ;
    assign w_port__AXI_Protocol_Converter_0__ds_axi_rvalid = w_net__AXI_GPIO_0__s_axi_rvalid ;

    assign w_net__AXI_Protocol_Converter_0__ds_axi_rready = w_port__AXI_Protocol_Converter_0__ds_axi_rready ;
    assign w_port__AXI_GPIO_0__s_axi_rready = w_net__AXI_Protocol_Converter_0__ds_axi_rready ;

    assign w_net__AXI_GPIO_0__gpio_io_o = w_port__AXI_GPIO_0__gpio_io_o ;
    assign motor_target = w_net__AXI_GPIO_0__gpio_io_o ;

    assign w_net__AXI_GPIO_0__gpio2_io_o = w_port__AXI_GPIO_0__gpio2_io_o ;
    assign motor_ctrl = w_net__AXI_GPIO_0__gpio2_io_o ;

    // Keep the vendor NPU on physical HP0. Adapt the unchanged camera/write
    // and display/read endpoints to physical HP1 through the same vendor AXI
    // matrix type that its video demo uses on HP1. Both video masters and this
    // matrix remain in the existing 100 MHz p2f_clk0 domain.
    wire [31:0] hp1m_araddr, hp1m_awaddr;
    wire [1:0] hp1m_arburst, hp1m_awburst;
    wire [3:0] hp1m_arcache, hp1m_awcache, hp1m_arqos, hp1m_awqos;
    wire [5:0] hp1m_arid, hp1m_awid, hp1m_bid, hp1m_rid;
    wire [7:0] hp1m_arlen, hp1m_awlen, hp1m_wstrb;
    wire hp1m_arlock, hp1m_awlock, hp1m_arready, hp1m_awready;
    wire hp1m_arvalid, hp1m_awvalid, hp1m_bready, hp1m_bvalid;
    wire hp1m_rlast, hp1m_rready, hp1m_rvalid;
    wire hp1m_wlast, hp1m_wready, hp1m_wvalid;
    wire [1:0] hp1m_bresp, hp1m_rresp;
    wire [2:0] hp1m_arprot, hp1m_awprot, hp1m_arsize, hp1m_awsize;
    wire [63:0] hp1m_rdata, hp1m_wdata;
    wire [4:0] hp1m_video_bid, hp1m_display_rid;
    assign dma_bid = {1'b0, hp1m_video_bid};
    assign display_rid = {1'b0, hp1m_display_rid};

    design_0_AXI_Matrix_2 u_vendor_hp1_video_matrix (
        .aclk(w_port__ARM_Processor_System_0__slave_hp0_axi_aclk),
        .aresetn(w_net__Processor_System_Reset_0__interconnect_aresetn),
        // Upstream 0: existing motor/CS500 write arbiter.
        .us0_araddr(32'd0), .us0_arburst(2'd0),
        .us0_arcache(4'd0), .us0_arid(5'd0),
        .us0_arlen(8'd0), .us0_arlock(1'b0),
        .us0_arprot(3'd0), .us0_arqos(4'd0),
        .us0_arsize(3'd0), .us0_arvalid(1'b0),
        .us0_awaddr(dma_awaddr[31:0]), .us0_awburst(dma_awburst),
        .us0_awcache(dma_awcache), .us0_awid(dma_awid[4:0]),
        .us0_awlen({4'd0, dma_awlen}), .us0_awlock(dma_awlock),
        .us0_awprot(dma_awprot), .us0_awqos(dma_awqos),
        .us0_awready(dma_awready), .us0_awsize({1'b0, dma_awsize}),
        .us0_awvalid(dma_awvalid), .us0_bid(hp1m_video_bid),
        .us0_bready(dma_bready), .us0_bresp(dma_bresp),
        .us0_bvalid(dma_bvalid), .us0_rready(1'b1),
        .us0_wdata(dma_wdata), .us0_wlast(dma_wlast),
        .us0_wready(dma_wready), .us0_wstrb(dma_wstrb),
        .us0_wvalid(dma_wvalid),
        // Upstream 1: existing display read-only master.
        .us1_araddr(display_araddr[31:0]),
        .us1_arburst(display_arburst), .us1_arcache(display_arcache),
        .us1_arid(display_arid[4:0]),
        .us1_arlen({4'd0, display_arlen}),
        .us1_arlock(display_arlock), .us1_arprot(display_arprot),
        .us1_arqos(display_arqos), .us1_arready(display_arready),
        .us1_arsize({1'b0, display_arsize}),
        .us1_arvalid(display_arvalid),
        .us1_awaddr(32'd0), .us1_awburst(2'd0),
        .us1_awcache(4'd0), .us1_awid(5'd0),
        .us1_awlen(8'd0), .us1_awlock(1'b0),
        .us1_awprot(3'd0), .us1_awqos(4'd0),
        .us1_awsize(3'd0), .us1_awvalid(1'b0),
        .us1_bready(1'b1), .us1_rdata(display_rdata),
        .us1_rid(hp1m_display_rid), .us1_rlast(display_rlast),
        .us1_rready(display_rready), .us1_rresp(display_rresp),
        .us1_rvalid(display_rvalid), .us1_wdata(64'd0),
        .us1_wlast(1'b0), .us1_wstrb(8'd0),
        .us1_wvalid(1'b0),
        // Downstream: physical HP1 via the swapped PS wrapper.
        .ds0_araddr(hp1m_araddr), .ds0_arburst(hp1m_arburst),
        .ds0_arcache(hp1m_arcache), .ds0_arid(hp1m_arid),
        .ds0_arlen(hp1m_arlen), .ds0_arlock(hp1m_arlock),
        .ds0_arprot(hp1m_arprot), .ds0_arqos(hp1m_arqos),
        .ds0_arready(hp1m_arready), .ds0_arsize(hp1m_arsize),
        .ds0_arvalid(hp1m_arvalid),
        .ds0_awaddr(hp1m_awaddr), .ds0_awburst(hp1m_awburst),
        .ds0_awcache(hp1m_awcache), .ds0_awid(hp1m_awid),
        .ds0_awlen(hp1m_awlen), .ds0_awlock(hp1m_awlock),
        .ds0_awprot(hp1m_awprot), .ds0_awqos(hp1m_awqos),
        .ds0_awready(hp1m_awready), .ds0_awsize(hp1m_awsize),
        .ds0_awvalid(hp1m_awvalid), .ds0_bid(hp1m_bid),
        .ds0_bready(hp1m_bready), .ds0_bresp(hp1m_bresp),
        .ds0_bvalid(hp1m_bvalid), .ds0_rdata(hp1m_rdata),
        .ds0_rid(hp1m_rid), .ds0_rlast(hp1m_rlast),
        .ds0_rready(hp1m_rready), .ds0_rresp(hp1m_rresp),
        .ds0_rvalid(hp1m_rvalid), .ds0_wdata(hp1m_wdata),
        .ds0_wlast(hp1m_wlast), .ds0_wready(hp1m_wready),
        .ds0_wstrb(hp1m_wstrb), .ds0_wvalid(hp1m_wvalid)
    );

    system_ARM_Processor_System_0 system_ARM_Processor_System_0_Inst ( 
        .can0_rx_in(can0_rx_in), .can0_tx_out(can0_tx_out),
        .i2c1_scl_in(i2c1_scl_in), .i2c1_sda_in(i2c1_sda_in),
        .i2c1_scl_oe(i2c1_scl_oe), .i2c1_sda_oe(i2c1_sda_oe),
                                                                        .slave_hp0_axi_araddr({1'b0, hp1m_araddr})
                                                                      , .slave_hp0_axi_arburst(hp1m_arburst)
                                                                      , .slave_hp0_axi_arcache(hp1m_arcache)
                                                                      , .slave_hp0_axi_arid(hp1m_arid)
                                                                      , .slave_hp0_axi_arlen(hp1m_arlen[3:0])
                                                                      , .slave_hp0_axi_arlock(hp1m_arlock)
                                                                      , .slave_hp0_axi_arprot(hp1m_arprot)
                                                                      , .slave_hp0_axi_arqos(hp1m_arqos)
                                                                      , .slave_hp0_axi_arready(hp1m_arready)
                                                                      , .slave_hp0_axi_arsize(hp1m_arsize[1:0])
                                                                      , .slave_hp0_axi_arvalid(hp1m_arvalid)
                                                                      , .slave_hp0_axi_awaddr({1'b0, hp1m_awaddr})
                                                                      , .slave_hp0_axi_awburst(hp1m_awburst)
                                                                      , .slave_hp0_axi_awcache(hp1m_awcache)
                                                                      , .slave_hp0_axi_awid(hp1m_awid)
                                                                      , .slave_hp0_axi_awlen(hp1m_awlen[3:0])
                                                                      , .slave_hp0_axi_awlock(hp1m_awlock)
                                                                      , .slave_hp0_axi_awprot(hp1m_awprot)
                                                                      , .slave_hp0_axi_awqos(hp1m_awqos)
                                                                      , .slave_hp0_axi_awready(hp1m_awready)
                                                                      , .slave_hp0_axi_awsize(hp1m_awsize[1:0])
                                                                      , .slave_hp0_axi_awvalid(hp1m_awvalid)
                                                                      , .slave_hp0_axi_bid(hp1m_bid)
                                                                      , .slave_hp0_axi_bready(hp1m_bready)
                                                                      , .slave_hp0_axi_bresp(hp1m_bresp)
                                                                      , .slave_hp0_axi_bvalid(hp1m_bvalid)
                                                                      , .slave_hp0_axi_rdata(hp1m_rdata)
                                                                      , .slave_hp0_axi_rid(hp1m_rid)
                                                                      , .slave_hp0_axi_rlast(hp1m_rlast)
                                                                      , .slave_hp0_axi_rready(hp1m_rready)
                                                                      , .slave_hp0_axi_rresp(hp1m_rresp)
                                                                      , .slave_hp0_axi_rvalid(hp1m_rvalid)
                                                                      , .slave_hp0_axi_wdata(hp1m_wdata)
                                                                      , .slave_hp0_axi_wlast(hp1m_wlast)
                                                                      , .slave_hp0_axi_wready(hp1m_wready)
                                                                      , .slave_hp0_axi_wstrb(hp1m_wstrb)
                                                                      , .slave_hp0_axi_wvalid(hp1m_wvalid)
                                                                      , .slave_hp0_axi_aclk(w_port__ARM_Processor_System_0__slave_hp0_axi_aclk)
                                                                      , .master_gp0_axi_aclk(w_port__ARM_Processor_System_0__master_gp0_axi_aclk)
                                                                      , .master_gp0_axi_araddr(w_port__ARM_Processor_System_0__master_gp0_axi_araddr)
                                                                      , .master_gp0_axi_arburst(w_port__ARM_Processor_System_0__master_gp0_axi_arburst)
                                                                      , .master_gp0_axi_arcache(w_port__ARM_Processor_System_0__master_gp0_axi_arcache)
                                                                      , .master_gp0_axi_arid(w_port__ARM_Processor_System_0__master_gp0_axi_arid)
                                                                      , .master_gp0_axi_arlen(w_port__ARM_Processor_System_0__master_gp0_axi_arlen)
                                                                      , .master_gp0_axi_arlock(w_port__ARM_Processor_System_0__master_gp0_axi_arlock)
                                                                      , .master_gp0_axi_arprot(w_port__ARM_Processor_System_0__master_gp0_axi_arprot)
                                                                      , .master_gp0_axi_arready(w_port__ARM_Processor_System_0__master_gp0_axi_arready)
                                                                      , .master_gp0_axi_arsize(w_port__ARM_Processor_System_0__master_gp0_axi_arsize)
                                                                      , .master_gp0_axi_arvalid(w_port__ARM_Processor_System_0__master_gp0_axi_arvalid)
                                                                      , .master_gp0_axi_awaddr(w_port__ARM_Processor_System_0__master_gp0_axi_awaddr)
                                                                      , .master_gp0_axi_awburst(w_port__ARM_Processor_System_0__master_gp0_axi_awburst)
                                                                      , .master_gp0_axi_awcache(w_port__ARM_Processor_System_0__master_gp0_axi_awcache)
                                                                      , .master_gp0_axi_awid(w_port__ARM_Processor_System_0__master_gp0_axi_awid)
                                                                      , .master_gp0_axi_awlen(w_port__ARM_Processor_System_0__master_gp0_axi_awlen)
                                                                      , .master_gp0_axi_awlock(w_port__ARM_Processor_System_0__master_gp0_axi_awlock)
                                                                      , .master_gp0_axi_awprot(w_port__ARM_Processor_System_0__master_gp0_axi_awprot)
                                                                      , .master_gp0_axi_awready(w_port__ARM_Processor_System_0__master_gp0_axi_awready)
                                                                      , .master_gp0_axi_awsize(w_port__ARM_Processor_System_0__master_gp0_axi_awsize)
                                                                      , .master_gp0_axi_awvalid(w_port__ARM_Processor_System_0__master_gp0_axi_awvalid)
                                                                      , .master_gp0_axi_bid(w_port__ARM_Processor_System_0__master_gp0_axi_bid)
                                                                      , .master_gp0_axi_bready(w_port__ARM_Processor_System_0__master_gp0_axi_bready)
                                                                      , .master_gp0_axi_bresp(w_port__ARM_Processor_System_0__master_gp0_axi_bresp)
                                                                      , .master_gp0_axi_bvalid(w_port__ARM_Processor_System_0__master_gp0_axi_bvalid)
                                                                      , .master_gp0_axi_rdata(w_port__ARM_Processor_System_0__master_gp0_axi_rdata)
                                                                      , .master_gp0_axi_rid(w_port__ARM_Processor_System_0__master_gp0_axi_rid)
                                                                      , .master_gp0_axi_rlast(w_port__ARM_Processor_System_0__master_gp0_axi_rlast)
                                                                      , .master_gp0_axi_rready(w_port__ARM_Processor_System_0__master_gp0_axi_rready)
                                                                      , .master_gp0_axi_rresp(w_port__ARM_Processor_System_0__master_gp0_axi_rresp)
                                                                      , .master_gp0_axi_rvalid(w_port__ARM_Processor_System_0__master_gp0_axi_rvalid)
                                                                      , .master_gp0_axi_wdata(w_port__ARM_Processor_System_0__master_gp0_axi_wdata)
                                                                      , .master_gp0_axi_wlast(w_port__ARM_Processor_System_0__master_gp0_axi_wlast)
                                                                      , .master_gp0_axi_wready(w_port__ARM_Processor_System_0__master_gp0_axi_wready)
                                                                      , .master_gp0_axi_wstrb(w_port__ARM_Processor_System_0__master_gp0_axi_wstrb)
                                                                      , .master_gp0_axi_wvalid(w_port__ARM_Processor_System_0__master_gp0_axi_wvalid)
                                                                      , .slave_hp1_axi_aclk(npu_axi_clk)
                                                                      , .slave_hp1_axi_araddr(npu_slave_hp1_axi_araddr)
                                                                      , .slave_hp1_axi_arburst(npu_slave_hp1_axi_arburst)
                                                                      , .slave_hp1_axi_arcache(npu_slave_hp1_axi_arcache)
                                                                      , .slave_hp1_axi_arid(npu_slave_hp1_axi_arid)
                                                                      , .slave_hp1_axi_arlen(npu_slave_hp1_axi_arlen)
                                                                      , .slave_hp1_axi_arlock(npu_slave_hp1_axi_arlock)
                                                                      , .slave_hp1_axi_arprot(npu_slave_hp1_axi_arprot)
                                                                      , .slave_hp1_axi_arqos(npu_slave_hp1_axi_arqos)
                                                                      , .slave_hp1_axi_arready(npu_slave_hp1_axi_arready)
                                                                      , .slave_hp1_axi_arsize(npu_slave_hp1_axi_arsize)
                                                                      , .slave_hp1_axi_arvalid(npu_slave_hp1_axi_arvalid)
                                                                      , .slave_hp1_axi_awaddr(npu_slave_hp1_axi_awaddr)
                                                                      , .slave_hp1_axi_awburst(npu_slave_hp1_axi_awburst)
                                                                      , .slave_hp1_axi_awcache(npu_slave_hp1_axi_awcache)
                                                                      , .slave_hp1_axi_awid(npu_slave_hp1_axi_awid)
                                                                      , .slave_hp1_axi_awlen(npu_slave_hp1_axi_awlen)
                                                                      , .slave_hp1_axi_awlock(npu_slave_hp1_axi_awlock)
                                                                      , .slave_hp1_axi_awprot(npu_slave_hp1_axi_awprot)
                                                                      , .slave_hp1_axi_awqos(npu_slave_hp1_axi_awqos)
                                                                      , .slave_hp1_axi_awready(npu_slave_hp1_axi_awready)
                                                                      , .slave_hp1_axi_awsize(npu_slave_hp1_axi_awsize)
                                                                      , .slave_hp1_axi_awvalid(npu_slave_hp1_axi_awvalid)
                                                                      , .slave_hp1_axi_bid(npu_slave_hp1_axi_bid)
                                                                      , .slave_hp1_axi_bready(npu_slave_hp1_axi_bready)
                                                                      , .slave_hp1_axi_bresp(npu_slave_hp1_axi_bresp)
                                                                      , .slave_hp1_axi_bvalid(npu_slave_hp1_axi_bvalid)
                                                                      , .slave_hp1_axi_rdata(npu_slave_hp1_axi_rdata)
                                                                      , .slave_hp1_axi_rid(npu_slave_hp1_axi_rid)
                                                                      , .slave_hp1_axi_rlast(npu_slave_hp1_axi_rlast)
                                                                      , .slave_hp1_axi_rready(npu_slave_hp1_axi_rready)
                                                                      , .slave_hp1_axi_rresp(npu_slave_hp1_axi_rresp)
                                                                      , .slave_hp1_axi_rvalid(npu_slave_hp1_axi_rvalid)
                                                                      , .slave_hp1_axi_wdata(npu_slave_hp1_axi_wdata)
                                                                      , .slave_hp1_axi_wlast(npu_slave_hp1_axi_wlast)
                                                                      , .slave_hp1_axi_wready(npu_slave_hp1_axi_wready)
                                                                      , .slave_hp1_axi_wstrb(npu_slave_hp1_axi_wstrb)
                                                                      , .slave_hp1_axi_wvalid(npu_slave_hp1_axi_wvalid)
                                                                      , .master_gp1_axi_aclk(npu_axi_clk)
                                                                      , .master_gp1_axi_araddr(npu_master_gp1_axi_araddr)
                                                                      , .master_gp1_axi_arburst(npu_master_gp1_axi_arburst)
                                                                      , .master_gp1_axi_arcache(npu_master_gp1_axi_arcache)
                                                                      , .master_gp1_axi_arid(npu_master_gp1_axi_arid)
                                                                      , .master_gp1_axi_arlen(npu_master_gp1_axi_arlen)
                                                                      , .master_gp1_axi_arlock(npu_master_gp1_axi_arlock)
                                                                      , .master_gp1_axi_arprot(npu_master_gp1_axi_arprot)
                                                                      , .master_gp1_axi_arready(npu_master_gp1_axi_arready)
                                                                      , .master_gp1_axi_arsize(npu_master_gp1_axi_arsize)
                                                                      , .master_gp1_axi_arvalid(npu_master_gp1_axi_arvalid)
                                                                      , .master_gp1_axi_awaddr(npu_master_gp1_axi_awaddr)
                                                                      , .master_gp1_axi_awburst(npu_master_gp1_axi_awburst)
                                                                      , .master_gp1_axi_awcache(npu_master_gp1_axi_awcache)
                                                                      , .master_gp1_axi_awid(npu_master_gp1_axi_awid)
                                                                      , .master_gp1_axi_awlen(npu_master_gp1_axi_awlen)
                                                                      , .master_gp1_axi_awlock(npu_master_gp1_axi_awlock)
                                                                      , .master_gp1_axi_awprot(npu_master_gp1_axi_awprot)
                                                                      , .master_gp1_axi_awready(npu_master_gp1_axi_awready)
                                                                      , .master_gp1_axi_awsize(npu_master_gp1_axi_awsize)
                                                                      , .master_gp1_axi_awvalid(npu_master_gp1_axi_awvalid)
                                                                      , .master_gp1_axi_bid(npu_master_gp1_axi_bid)
                                                                      , .master_gp1_axi_bready(npu_master_gp1_axi_bready)
                                                                      , .master_gp1_axi_bresp(npu_master_gp1_axi_bresp)
                                                                      , .master_gp1_axi_bvalid(npu_master_gp1_axi_bvalid)
                                                                      , .master_gp1_axi_rdata(npu_master_gp1_axi_rdata)
                                                                      , .master_gp1_axi_rid(npu_master_gp1_axi_rid)
                                                                      , .master_gp1_axi_rlast(npu_master_gp1_axi_rlast)
                                                                      , .master_gp1_axi_rready(npu_master_gp1_axi_rready)
                                                                      , .master_gp1_axi_rresp(npu_master_gp1_axi_rresp)
                                                                      , .master_gp1_axi_rvalid(npu_master_gp1_axi_rvalid)
                                                                      , .master_gp1_axi_wdata(npu_master_gp1_axi_wdata)
                                                                      , .master_gp1_axi_wlast(npu_master_gp1_axi_wlast)
                                                                      , .master_gp1_axi_wready(npu_master_gp1_axi_wready)
                                                                      , .master_gp1_axi_wstrb(npu_master_gp1_axi_wstrb)
                                                                      , .master_gp1_axi_wvalid(npu_master_gp1_axi_wvalid)
                                                                      , .f2p_irq(npu_f2p_irq)
                                                                      , .p2f_rst0_n(w_port__ARM_Processor_System_0__p2f_rst0_n)
                                                                      , .p2f_clk0(w_port__ARM_Processor_System_0__p2f_clk0) );


    npu_sidecar u_npu_sidecar (
        .clk(motor_clk),
        .resetn(motor_resetn),
        .axi_clk(npu_axi_clk),
        .slave_hp1_axi_araddr(npu_slave_hp1_axi_araddr),
        .slave_hp1_axi_arburst(npu_slave_hp1_axi_arburst),
        .slave_hp1_axi_arcache(npu_slave_hp1_axi_arcache),
        .slave_hp1_axi_arid(npu_slave_hp1_axi_arid),
        .slave_hp1_axi_arlen(npu_slave_hp1_axi_arlen),
        .slave_hp1_axi_arlock(npu_slave_hp1_axi_arlock),
        .slave_hp1_axi_arprot(npu_slave_hp1_axi_arprot),
        .slave_hp1_axi_arqos(npu_slave_hp1_axi_arqos),
        .slave_hp1_axi_arready(npu_slave_hp1_axi_arready),
        .slave_hp1_axi_arsize(npu_slave_hp1_axi_arsize),
        .slave_hp1_axi_arvalid(npu_slave_hp1_axi_arvalid),
        .slave_hp1_axi_awaddr(npu_slave_hp1_axi_awaddr),
        .slave_hp1_axi_awburst(npu_slave_hp1_axi_awburst),
        .slave_hp1_axi_awcache(npu_slave_hp1_axi_awcache),
        .slave_hp1_axi_awid(npu_slave_hp1_axi_awid),
        .slave_hp1_axi_awlen(npu_slave_hp1_axi_awlen),
        .slave_hp1_axi_awlock(npu_slave_hp1_axi_awlock),
        .slave_hp1_axi_awprot(npu_slave_hp1_axi_awprot),
        .slave_hp1_axi_awqos(npu_slave_hp1_axi_awqos),
        .slave_hp1_axi_awready(npu_slave_hp1_axi_awready),
        .slave_hp1_axi_awsize(npu_slave_hp1_axi_awsize),
        .slave_hp1_axi_awvalid(npu_slave_hp1_axi_awvalid),
        .slave_hp1_axi_bid(npu_slave_hp1_axi_bid),
        .slave_hp1_axi_bready(npu_slave_hp1_axi_bready),
        .slave_hp1_axi_bresp(npu_slave_hp1_axi_bresp),
        .slave_hp1_axi_bvalid(npu_slave_hp1_axi_bvalid),
        .slave_hp1_axi_rdata(npu_slave_hp1_axi_rdata),
        .slave_hp1_axi_rid(npu_slave_hp1_axi_rid),
        .slave_hp1_axi_rlast(npu_slave_hp1_axi_rlast),
        .slave_hp1_axi_rready(npu_slave_hp1_axi_rready),
        .slave_hp1_axi_rresp(npu_slave_hp1_axi_rresp),
        .slave_hp1_axi_rvalid(npu_slave_hp1_axi_rvalid),
        .slave_hp1_axi_wdata(npu_slave_hp1_axi_wdata),
        .slave_hp1_axi_wlast(npu_slave_hp1_axi_wlast),
        .slave_hp1_axi_wready(npu_slave_hp1_axi_wready),
        .slave_hp1_axi_wstrb(npu_slave_hp1_axi_wstrb),
        .slave_hp1_axi_wvalid(npu_slave_hp1_axi_wvalid),
        .master_gp1_axi_araddr(npu_master_gp1_axi_araddr),
        .master_gp1_axi_arburst(npu_master_gp1_axi_arburst),
        .master_gp1_axi_arcache(npu_master_gp1_axi_arcache),
        .master_gp1_axi_arid(npu_master_gp1_axi_arid),
        .master_gp1_axi_arlen(npu_master_gp1_axi_arlen),
        .master_gp1_axi_arlock(npu_master_gp1_axi_arlock),
        .master_gp1_axi_arprot(npu_master_gp1_axi_arprot),
        .master_gp1_axi_arready(npu_master_gp1_axi_arready),
        .master_gp1_axi_arsize(npu_master_gp1_axi_arsize),
        .master_gp1_axi_arvalid(npu_master_gp1_axi_arvalid),
        .master_gp1_axi_awaddr(npu_master_gp1_axi_awaddr),
        .master_gp1_axi_awburst(npu_master_gp1_axi_awburst),
        .master_gp1_axi_awcache(npu_master_gp1_axi_awcache),
        .master_gp1_axi_awid(npu_master_gp1_axi_awid),
        .master_gp1_axi_awlen(npu_master_gp1_axi_awlen),
        .master_gp1_axi_awlock(npu_master_gp1_axi_awlock),
        .master_gp1_axi_awprot(npu_master_gp1_axi_awprot),
        .master_gp1_axi_awready(npu_master_gp1_axi_awready),
        .master_gp1_axi_awsize(npu_master_gp1_axi_awsize),
        .master_gp1_axi_awvalid(npu_master_gp1_axi_awvalid),
        .master_gp1_axi_bid(npu_master_gp1_axi_bid),
        .master_gp1_axi_bready(npu_master_gp1_axi_bready),
        .master_gp1_axi_bresp(npu_master_gp1_axi_bresp),
        .master_gp1_axi_bvalid(npu_master_gp1_axi_bvalid),
        .master_gp1_axi_rdata(npu_master_gp1_axi_rdata),
        .master_gp1_axi_rid(npu_master_gp1_axi_rid),
        .master_gp1_axi_rlast(npu_master_gp1_axi_rlast),
        .master_gp1_axi_rready(npu_master_gp1_axi_rready),
        .master_gp1_axi_rresp(npu_master_gp1_axi_rresp),
        .master_gp1_axi_rvalid(npu_master_gp1_axi_rvalid),
        .master_gp1_axi_wdata(npu_master_gp1_axi_wdata),
        .master_gp1_axi_wlast(npu_master_gp1_axi_wlast),
        .master_gp1_axi_wready(npu_master_gp1_axi_wready),
        .master_gp1_axi_wstrb(npu_master_gp1_axi_wstrb),
        .master_gp1_axi_wvalid(npu_master_gp1_axi_wvalid),
        .f2p_irq(npu_f2p_irq)
    );

    system_Processor_System_Reset_0 system_Processor_System_Reset_0_Inst ( 
                                                                            .clk(w_port__Processor_System_Reset_0__clk)
                                                                          , .external_resetn(w_port__Processor_System_Reset_0__external_resetn)
                                                                          , .aux_reset(w_port__Processor_System_Reset_0__aux_reset)
                                                                          , .system_rst(w_port__Processor_System_Reset_0__system_rst)
                                                                          , .pll_locked(w_port__Processor_System_Reset_0__pll_locked)
                                                                          , .soc_reset()
                                                                          , .bus_reset()
                                                                          , .peripheral_reset()
                                                                          , .interconnect_aresetn(w_port__Processor_System_Reset_0__interconnect_aresetn)
                                                                          , .peripheral_aresetn(w_port__Processor_System_Reset_0__peripheral_aresetn) );

    system_Constant_0 system_Constant_0_Inst ( 
                                                .dout(w_port__Constant_0__dout) );

    system_Constant_1 system_Constant_1_Inst ( 
                                                .dout(w_port__Constant_1__dout) );

    system_AXI_ERAM_Controller_0 system_AXI_ERAM_Controller_0_Inst ( 
                                                                      .awid(w_port__AXI_ERAM_Controller_0__awid)
                                                                    , .awaddr(w_port__AXI_ERAM_Controller_0__awaddr)
                                                                    , .awlen(w_port__AXI_ERAM_Controller_0__awlen)
                                                                    , .awsize(w_port__AXI_ERAM_Controller_0__awsize)
                                                                    , .awburst(w_port__AXI_ERAM_Controller_0__awburst)
                                                                    , .awlock(w_port__AXI_ERAM_Controller_0__awlock)
                                                                    , .awvalid(w_port__AXI_ERAM_Controller_0__awvalid)
                                                                    , .awready(w_port__AXI_ERAM_Controller_0__awready)
                                                                    , .wdata(w_port__AXI_ERAM_Controller_0__wdata)
                                                                    , .wstrb(w_port__AXI_ERAM_Controller_0__wstrb)
                                                                    , .wvalid(w_port__AXI_ERAM_Controller_0__wvalid)
                                                                    , .wready(w_port__AXI_ERAM_Controller_0__wready)
                                                                    , .bid(w_port__AXI_ERAM_Controller_0__bid)
                                                                    , .bresp(w_port__AXI_ERAM_Controller_0__bresp)
                                                                    , .bvalid(w_port__AXI_ERAM_Controller_0__bvalid)
                                                                    , .bready(w_port__AXI_ERAM_Controller_0__bready)
                                                                    , .arid(w_port__AXI_ERAM_Controller_0__arid)
                                                                    , .araddr(w_port__AXI_ERAM_Controller_0__araddr)
                                                                    , .arlen(w_port__AXI_ERAM_Controller_0__arlen)
                                                                    , .arsize(w_port__AXI_ERAM_Controller_0__arsize)
                                                                    , .arburst(w_port__AXI_ERAM_Controller_0__arburst)
                                                                    , .arlock(w_port__AXI_ERAM_Controller_0__arlock)
                                                                    , .arvalid(w_port__AXI_ERAM_Controller_0__arvalid)
                                                                    , .arready(w_port__AXI_ERAM_Controller_0__arready)
                                                                    , .rid(w_port__AXI_ERAM_Controller_0__rid)
                                                                    , .rdata(w_port__AXI_ERAM_Controller_0__rdata)
                                                                    , .rresp(w_port__AXI_ERAM_Controller_0__rresp)
                                                                    , .rlast(w_port__AXI_ERAM_Controller_0__rlast)
                                                                    , .rvalid(w_port__AXI_ERAM_Controller_0__rvalid)
                                                                    , .rready(w_port__AXI_ERAM_Controller_0__rready)
                                                                    , .mem_dout(status_rdata)
                                                                    , .aclk(w_port__AXI_ERAM_Controller_0__aclk)
                                                                    , .aresetn(w_port__AXI_ERAM_Controller_0__aresetn)
                                                                    , .mem_addr(status_addr)
                                                                    , .mem_web(status_web)
                                                                    , .mem_csb(status_csb)
                                                                    , .mem_din(status_wdata) );

    system_AXI_GPIO_0 system_AXI_GPIO_0_Inst ( 
                                                .s_axi_awaddr(w_port__AXI_GPIO_0__s_axi_awaddr)
                                              , .s_axi_awvalid(w_port__AXI_GPIO_0__s_axi_awvalid)
                                              , .s_axi_awready(w_port__AXI_GPIO_0__s_axi_awready)
                                              , .s_axi_wdata(w_port__AXI_GPIO_0__s_axi_wdata)
                                              , .s_axi_wstrb(w_port__AXI_GPIO_0__s_axi_wstrb)
                                              , .s_axi_wvalid(w_port__AXI_GPIO_0__s_axi_wvalid)
                                              , .s_axi_wready(w_port__AXI_GPIO_0__s_axi_wready)
                                              , .s_axi_bresp(w_port__AXI_GPIO_0__s_axi_bresp)
                                              , .s_axi_bvalid(w_port__AXI_GPIO_0__s_axi_bvalid)
                                              , .s_axi_bready(w_port__AXI_GPIO_0__s_axi_bready)
                                              , .s_axi_araddr(w_port__AXI_GPIO_0__s_axi_araddr)
                                              , .s_axi_arvalid(w_port__AXI_GPIO_0__s_axi_arvalid)
                                              , .s_axi_arready(w_port__AXI_GPIO_0__s_axi_arready)
                                              , .s_axi_rdata(w_port__AXI_GPIO_0__s_axi_rdata)
                                              , .s_axi_rresp(w_port__AXI_GPIO_0__s_axi_rresp)
                                              , .s_axi_rvalid(w_port__AXI_GPIO_0__s_axi_rvalid)
                                              , .s_axi_rready(w_port__AXI_GPIO_0__s_axi_rready)
                                              , .s_axi_aclk(w_port__AXI_GPIO_0__s_axi_aclk)
                                              , .s_axi_aresetn(w_port__AXI_GPIO_0__s_axi_aresetn)
                                              , .gpio_io_o(w_port__AXI_GPIO_0__gpio_io_o)
                                              , .gpio2_io_o(w_port__AXI_GPIO_0__gpio2_io_o) );

    system_AXI_Matrix_0 system_AXI_Matrix_0_Inst ( 
                                                    .us0_araddr(w_port__AXI_Matrix_0__us0_araddr)
                                                  , .us0_arburst(w_port__AXI_Matrix_0__us0_arburst)
                                                  , .us0_arcache(w_port__AXI_Matrix_0__us0_arcache)
                                                  , .us0_arid(w_port__AXI_Matrix_0__us0_arid)
                                                  , .us0_arlen(w_port__AXI_Matrix_0__us0_arlen)
                                                  , .us0_arlock(w_port__AXI_Matrix_0__us0_arlock)
                                                  , .us0_arprot(w_port__AXI_Matrix_0__us0_arprot)
                                                  , .us0_arqos(4'b0)
                                                  , .us0_arready(w_port__AXI_Matrix_0__us0_arready)
                                                  , .us0_arsize(w_port__AXI_Matrix_0__us0_arsize)
                                                  , .us0_arvalid(w_port__AXI_Matrix_0__us0_arvalid)
                                                  , .us0_awaddr(w_port__AXI_Matrix_0__us0_awaddr)
                                                  , .us0_awburst(w_port__AXI_Matrix_0__us0_awburst)
                                                  , .us0_awcache(w_port__AXI_Matrix_0__us0_awcache)
                                                  , .us0_awid(w_port__AXI_Matrix_0__us0_awid)
                                                  , .us0_awlen(w_port__AXI_Matrix_0__us0_awlen)
                                                  , .us0_awlock(w_port__AXI_Matrix_0__us0_awlock)
                                                  , .us0_awprot(w_port__AXI_Matrix_0__us0_awprot)
                                                  , .us0_awqos(4'b0)
                                                  , .us0_awready(w_port__AXI_Matrix_0__us0_awready)
                                                  , .us0_awsize(w_port__AXI_Matrix_0__us0_awsize)
                                                  , .us0_awvalid(w_port__AXI_Matrix_0__us0_awvalid)
                                                  , .us0_bid(w_port__AXI_Matrix_0__us0_bid)
                                                  , .us0_bready(w_port__AXI_Matrix_0__us0_bready)
                                                  , .us0_bresp(w_port__AXI_Matrix_0__us0_bresp)
                                                  , .us0_bvalid(w_port__AXI_Matrix_0__us0_bvalid)
                                                  , .us0_rdata(w_port__AXI_Matrix_0__us0_rdata)
                                                  , .us0_rid(w_port__AXI_Matrix_0__us0_rid)
                                                  , .us0_rlast(w_port__AXI_Matrix_0__us0_rlast)
                                                  , .us0_rready(w_port__AXI_Matrix_0__us0_rready)
                                                  , .us0_rresp(w_port__AXI_Matrix_0__us0_rresp)
                                                  , .us0_rvalid(w_port__AXI_Matrix_0__us0_rvalid)
                                                  , .us0_wdata(w_port__AXI_Matrix_0__us0_wdata)
                                                  , .us0_wlast(w_port__AXI_Matrix_0__us0_wlast)
                                                  , .us0_wready(w_port__AXI_Matrix_0__us0_wready)
                                                  , .us0_wstrb(w_port__AXI_Matrix_0__us0_wstrb)
                                                  , .us0_wvalid(w_port__AXI_Matrix_0__us0_wvalid)
                                                  , .aclk(w_port__AXI_Matrix_0__aclk)
                                                  , .aresetn(w_port__AXI_Matrix_0__aresetn)
                                                  , .ds0_araddr(w_port__AXI_Matrix_0__ds0_araddr)
                                                  , .ds0_arburst(w_port__AXI_Matrix_0__ds0_arburst)
                                                  , .ds0_arcache()
                                                  , .ds0_arid(w_port__AXI_Matrix_0__ds0_arid)
                                                  , .ds0_arlen(w_port__AXI_Matrix_0__ds0_arlen)
                                                  , .ds0_arlock(w_port__AXI_Matrix_0__ds0_arlock)
                                                  , .ds0_arprot()
                                                  , .ds0_arqos()
                                                  , .ds0_arregion()
                                                  , .ds0_arready(w_port__AXI_Matrix_0__ds0_arready)
                                                  , .ds0_arsize(w_port__AXI_Matrix_0__ds0_arsize)
                                                  , .ds0_arvalid(w_port__AXI_Matrix_0__ds0_arvalid)
                                                  , .ds0_awaddr(w_port__AXI_Matrix_0__ds0_awaddr)
                                                  , .ds0_awburst(w_port__AXI_Matrix_0__ds0_awburst)
                                                  , .ds0_awcache()
                                                  , .ds0_awid(w_port__AXI_Matrix_0__ds0_awid)
                                                  , .ds0_awlen(w_port__AXI_Matrix_0__ds0_awlen)
                                                  , .ds0_awlock(w_port__AXI_Matrix_0__ds0_awlock)
                                                  , .ds0_awprot()
                                                  , .ds0_awqos()
                                                  , .ds0_awregion()
                                                  , .ds0_awready(w_port__AXI_Matrix_0__ds0_awready)
                                                  , .ds0_awsize(w_port__AXI_Matrix_0__ds0_awsize)
                                                  , .ds0_awvalid(w_port__AXI_Matrix_0__ds0_awvalid)
                                                  , .ds0_bid(w_port__AXI_Matrix_0__ds0_bid)
                                                  , .ds0_bready(w_port__AXI_Matrix_0__ds0_bready)
                                                  , .ds0_bresp(w_port__AXI_Matrix_0__ds0_bresp)
                                                  , .ds0_bvalid(w_port__AXI_Matrix_0__ds0_bvalid)
                                                  , .ds0_rdata(w_port__AXI_Matrix_0__ds0_rdata)
                                                  , .ds0_rid(w_port__AXI_Matrix_0__ds0_rid)
                                                  , .ds0_rlast(w_port__AXI_Matrix_0__ds0_rlast)
                                                  , .ds0_rready(w_port__AXI_Matrix_0__ds0_rready)
                                                  , .ds0_rresp(w_port__AXI_Matrix_0__ds0_rresp)
                                                  , .ds0_rvalid(w_port__AXI_Matrix_0__ds0_rvalid)
                                                  , .ds0_wdata(w_port__AXI_Matrix_0__ds0_wdata)
                                                  , .ds0_wlast()
                                                  , .ds0_wready(w_port__AXI_Matrix_0__ds0_wready)
                                                  , .ds0_wstrb(w_port__AXI_Matrix_0__ds0_wstrb)
                                                  , .ds0_wvalid(w_port__AXI_Matrix_0__ds0_wvalid)
                                                  , .ds1_araddr(w_port__AXI_Matrix_0__ds1_araddr)
                                                  , .ds1_arburst(w_port__AXI_Matrix_0__ds1_arburst)
                                                  , .ds1_arcache(w_port__AXI_Matrix_0__ds1_arcache)
                                                  , .ds1_arid(w_port__AXI_Matrix_0__ds1_arid)
                                                  , .ds1_arlen(w_port__AXI_Matrix_0__ds1_arlen)
                                                  , .ds1_arlock(w_port__AXI_Matrix_0__ds1_arlock)
                                                  , .ds1_arprot(w_port__AXI_Matrix_0__ds1_arprot)
                                                  , .ds1_arqos(w_port__AXI_Matrix_0__ds1_arqos)
                                                  , .ds1_arregion()
                                                  , .ds1_arready(w_port__AXI_Matrix_0__ds1_arready)
                                                  , .ds1_arsize(w_port__AXI_Matrix_0__ds1_arsize)
                                                  , .ds1_arvalid(w_port__AXI_Matrix_0__ds1_arvalid)
                                                  , .ds1_awaddr(w_port__AXI_Matrix_0__ds1_awaddr)
                                                  , .ds1_awburst(w_port__AXI_Matrix_0__ds1_awburst)
                                                  , .ds1_awcache(w_port__AXI_Matrix_0__ds1_awcache)
                                                  , .ds1_awid(w_port__AXI_Matrix_0__ds1_awid)
                                                  , .ds1_awlen(w_port__AXI_Matrix_0__ds1_awlen)
                                                  , .ds1_awlock(w_port__AXI_Matrix_0__ds1_awlock)
                                                  , .ds1_awprot(w_port__AXI_Matrix_0__ds1_awprot)
                                                  , .ds1_awqos(w_port__AXI_Matrix_0__ds1_awqos)
                                                  , .ds1_awregion()
                                                  , .ds1_awready(w_port__AXI_Matrix_0__ds1_awready)
                                                  , .ds1_awsize(w_port__AXI_Matrix_0__ds1_awsize)
                                                  , .ds1_awvalid(w_port__AXI_Matrix_0__ds1_awvalid)
                                                  , .ds1_bid(w_port__AXI_Matrix_0__ds1_bid)
                                                  , .ds1_bready(w_port__AXI_Matrix_0__ds1_bready)
                                                  , .ds1_bresp(w_port__AXI_Matrix_0__ds1_bresp)
                                                  , .ds1_bvalid(w_port__AXI_Matrix_0__ds1_bvalid)
                                                  , .ds1_rdata(w_port__AXI_Matrix_0__ds1_rdata)
                                                  , .ds1_rid(w_port__AXI_Matrix_0__ds1_rid)
                                                  , .ds1_rlast(w_port__AXI_Matrix_0__ds1_rlast)
                                                  , .ds1_rready(w_port__AXI_Matrix_0__ds1_rready)
                                                  , .ds1_rresp(w_port__AXI_Matrix_0__ds1_rresp)
                                                  , .ds1_rvalid(w_port__AXI_Matrix_0__ds1_rvalid)
                                                  , .ds1_wdata(w_port__AXI_Matrix_0__ds1_wdata)
                                                  , .ds1_wlast(w_port__AXI_Matrix_0__ds1_wlast)
                                                  , .ds1_wready(w_port__AXI_Matrix_0__ds1_wready)
                                                  , .ds1_wstrb(w_port__AXI_Matrix_0__ds1_wstrb)
                                                  , .ds1_wvalid(w_port__AXI_Matrix_0__ds1_wvalid) );

    system_AXI_Protocol_Converter_0 system_AXI_Protocol_Converter_0_Inst ( 
                                                                            .us_axi_awid(w_port__AXI_Protocol_Converter_0__us_axi_awid)
                                                                          , .us_axi_awaddr(w_port__AXI_Protocol_Converter_0__us_axi_awaddr)
                                                                          , .us_axi_awlen(w_port__AXI_Protocol_Converter_0__us_axi_awlen)
                                                                          , .us_axi_awsize(w_port__AXI_Protocol_Converter_0__us_axi_awsize)
                                                                          , .us_axi_awburst(w_port__AXI_Protocol_Converter_0__us_axi_awburst)
                                                                          , .us_axi_awlock(w_port__AXI_Protocol_Converter_0__us_axi_awlock)
                                                                          , .us_axi_awcache(w_port__AXI_Protocol_Converter_0__us_axi_awcache)
                                                                          , .us_axi_awprot(w_port__AXI_Protocol_Converter_0__us_axi_awprot)
                                                                          , .us_axi_awqos(w_port__AXI_Protocol_Converter_0__us_axi_awqos)
                                                                          , .us_axi_awvalid(w_port__AXI_Protocol_Converter_0__us_axi_awvalid)
                                                                          , .us_axi_awready(w_port__AXI_Protocol_Converter_0__us_axi_awready)
                                                                          , .us_axi_wdata(w_port__AXI_Protocol_Converter_0__us_axi_wdata)
                                                                          , .us_axi_wstrb(w_port__AXI_Protocol_Converter_0__us_axi_wstrb)
                                                                          , .us_axi_wlast(w_port__AXI_Protocol_Converter_0__us_axi_wlast)
                                                                          , .us_axi_wvalid(w_port__AXI_Protocol_Converter_0__us_axi_wvalid)
                                                                          , .us_axi_wready(w_port__AXI_Protocol_Converter_0__us_axi_wready)
                                                                          , .us_axi_bid(w_port__AXI_Protocol_Converter_0__us_axi_bid)
                                                                          , .us_axi_bresp(w_port__AXI_Protocol_Converter_0__us_axi_bresp)
                                                                          , .us_axi_bvalid(w_port__AXI_Protocol_Converter_0__us_axi_bvalid)
                                                                          , .us_axi_bready(w_port__AXI_Protocol_Converter_0__us_axi_bready)
                                                                          , .us_axi_arid(w_port__AXI_Protocol_Converter_0__us_axi_arid)
                                                                          , .us_axi_araddr(w_port__AXI_Protocol_Converter_0__us_axi_araddr)
                                                                          , .us_axi_arlen(w_port__AXI_Protocol_Converter_0__us_axi_arlen)
                                                                          , .us_axi_arsize(w_port__AXI_Protocol_Converter_0__us_axi_arsize)
                                                                          , .us_axi_arburst(w_port__AXI_Protocol_Converter_0__us_axi_arburst)
                                                                          , .us_axi_arlock(w_port__AXI_Protocol_Converter_0__us_axi_arlock)
                                                                          , .us_axi_arcache(w_port__AXI_Protocol_Converter_0__us_axi_arcache)
                                                                          , .us_axi_arprot(w_port__AXI_Protocol_Converter_0__us_axi_arprot)
                                                                          , .us_axi_arqos(w_port__AXI_Protocol_Converter_0__us_axi_arqos)
                                                                          , .us_axi_arvalid(w_port__AXI_Protocol_Converter_0__us_axi_arvalid)
                                                                          , .us_axi_arready(w_port__AXI_Protocol_Converter_0__us_axi_arready)
                                                                          , .us_axi_rid(w_port__AXI_Protocol_Converter_0__us_axi_rid)
                                                                          , .us_axi_rdata(w_port__AXI_Protocol_Converter_0__us_axi_rdata)
                                                                          , .us_axi_rresp(w_port__AXI_Protocol_Converter_0__us_axi_rresp)
                                                                          , .us_axi_rlast(w_port__AXI_Protocol_Converter_0__us_axi_rlast)
                                                                          , .us_axi_rvalid(w_port__AXI_Protocol_Converter_0__us_axi_rvalid)
                                                                          , .us_axi_rready(w_port__AXI_Protocol_Converter_0__us_axi_rready)
                                                                          , .aclk(w_port__AXI_Protocol_Converter_0__aclk)
                                                                          , .aresetn(w_port__AXI_Protocol_Converter_0__aresetn)
                                                                          , .ds_axi_awaddr(w_port__AXI_Protocol_Converter_0__ds_axi_awaddr)
                                                                          , .ds_axi_awprot()
                                                                          , .ds_axi_awvalid(w_port__AXI_Protocol_Converter_0__ds_axi_awvalid)
                                                                          , .ds_axi_awready(w_port__AXI_Protocol_Converter_0__ds_axi_awready)
                                                                          , .ds_axi_wdata(w_port__AXI_Protocol_Converter_0__ds_axi_wdata)
                                                                          , .ds_axi_wstrb(w_port__AXI_Protocol_Converter_0__ds_axi_wstrb)
                                                                          , .ds_axi_wvalid(w_port__AXI_Protocol_Converter_0__ds_axi_wvalid)
                                                                          , .ds_axi_wready(w_port__AXI_Protocol_Converter_0__ds_axi_wready)
                                                                          , .ds_axi_bresp(w_port__AXI_Protocol_Converter_0__ds_axi_bresp)
                                                                          , .ds_axi_bvalid(w_port__AXI_Protocol_Converter_0__ds_axi_bvalid)
                                                                          , .ds_axi_bready(w_port__AXI_Protocol_Converter_0__ds_axi_bready)
                                                                          , .ds_axi_araddr(w_port__AXI_Protocol_Converter_0__ds_axi_araddr)
                                                                          , .ds_axi_arprot()
                                                                          , .ds_axi_arvalid(w_port__AXI_Protocol_Converter_0__ds_axi_arvalid)
                                                                          , .ds_axi_arready(w_port__AXI_Protocol_Converter_0__ds_axi_arready)
                                                                          , .ds_axi_rdata(w_port__AXI_Protocol_Converter_0__ds_axi_rdata)
                                                                          , .ds_axi_rresp(w_port__AXI_Protocol_Converter_0__ds_axi_rresp)
                                                                          , .ds_axi_rvalid(w_port__AXI_Protocol_Converter_0__ds_axi_rvalid)
                                                                          , .ds_axi_rready(w_port__AXI_Protocol_Converter_0__ds_axi_rready) );

endmodule
