/************************************************************\
**	Copyright (c) 2012-2026 Anlogic Inc.
**	All Right Reserved.
\************************************************************/
/************************************************************\
**	Gen time	:	Jun 16 2026 14:07:40
**	IpTool version	:	2026.03(193873 2026/03/31)
**	App version	:	Release_2026.1_SP2
**	Ip Version	:	1.0
\************************************************************/
`timescale 1 ns / 1 ps
module rom
(
  output  [7:0]                 doa,
  input   [9:0]                 addra,
  input                         clka
);

  rom_rom
  #(
      .DATA_WIDTH_A(8),
      .ADDR_WIDTH_A(10),
      .DATA_DEPTH_A(1024),
      .INIT_FILE("../config_data_hyy7.dat"),
      .FILL_ALL("NONE")
  )rom_Inst
  (
      .doa(doa),
      .addra(addra),
      .clka(clka)
  );
endmodule
