/************************************************************\
**	Copyright (c) 2012-2024 Anlogic Inc.
**	All Right Reserved.
\************************************************************/
/************************************************************\
**	Build time: Jun 04 2024 17:15:31
**	TD version	:	5.9.112797
\************************************************************/
`timescale 1 ns / 1 ps
module fifo_w32_d512
(
  input                         rst,
  input                         clk,
  input                         we,
  input   [31:0]                di,
  input                         re,
  output  [31:0]                dout,
  output                        valid,
  output                        full_flag,
  output                        empty_flag,
  output                        afull,
  output                        aempty,
  output  [8:0]                 wrusedw,
  output  [8:0]                 rdusedw
);

  soft_fifo_al_34cb2256ce16
  #(
      .DATA_WIDTH_W(32),
      .DATA_WIDTH_R(32),
      .ADDR_WIDTH_W(9),
      .ADDR_WIDTH_R(9),
      .AL_FULL_NUM(253),
      .AL_EMPTY_NUM(2),
      .SHOW_AHEAD_EN(0),
      .OUTREG_EN("NOREG")
  )soft_fifo_al_34cb2256ce16_Inst
  (
      .rst(rst),
      .clk(clk),
      .we(we),
      .di(di),
      .re(re),
      .dout(dout),
      .valid(valid),
      .full_flag(full_flag),
      .empty_flag(empty_flag),
      .afull(afull),
      .aempty(aempty),
      .wrusedw(wrusedw),
      .rdusedw(rdusedw)
  );
endmodule
