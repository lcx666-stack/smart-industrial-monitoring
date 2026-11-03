/************************************************************\
**	Copyright (c) 2012-2026 Anlogic Inc.
**	All Right Reserved.
\************************************************************/
/************************************************************\
**	Gen time	:	Sep 26 2026 16:48:42
**	IpTool version	:	2026.03(193873 2026/03/31)
**	App version	:	Release_2026.1_SP2
**	Ip Version	:	1.0
\************************************************************/
`timescale 1ns/1ns
module system_Processor_System_Reset_0
(
  input                         clk,
  input                         external_resetn,
  input                         aux_reset,
  input                         system_rst,
  input                         pll_locked,
  output                        soc_reset,
  output  [0:0]                 bus_reset,
  output  [0:0]                 peripheral_reset,
  output  [0:0]                 interconnect_aresetn,
  output  [0:0]                 peripheral_aresetn
);

  proc_sys_reset_system_Processor_System_Reset_0
  #(
      .EXTERNAL_RESET_PULSE_WIDTH(4),
      .AUXILIARY_RESET_PULSE_WIDTH(4),
      .EXTERNAL_RESET_IS_HIGH(0),
      .AUXILIARY_RESET_IS_HIGH(1),
      .NUMBER_BUS_OF_RESET(1),
      .NUMBER_OF_PERIPHERALS_RESET(1),
      .NUMBER_OF_INTERCONNECT_ARESETN(1),
      .NUMBER_OF_PERIPHERALS_ARESETN(1)
  )proc_sys_reset_Inst
  (
      .clk(clk),
      .external_resetn(external_resetn),
      .aux_reset(aux_reset),
      .system_rst(system_rst),
      .pll_locked(pll_locked),
      .soc_reset(soc_reset),
      .bus_reset(bus_reset),
      .peripheral_reset(peripheral_reset),
      .interconnect_aresetn(interconnect_aresetn),
      .peripheral_aresetn(peripheral_aresetn)
  );
endmodule
