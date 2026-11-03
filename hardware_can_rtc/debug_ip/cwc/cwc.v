/************************************************************\
**	Copyright (c) 2012-2026 Anlogic Inc.
**	All Right Reserved.
\************************************************************/
/************************************************************\
**	Gen time	:	Jun 16 2026 17:19:44
**	IpTool version	:	2026.03(193873 2026/03/31)
**	App version	:	Release_2026.1_SP2
**	Ip Version	:	1.0
\************************************************************/
module cwc
(
  input   [0:0]                 probe0,
  input   [0:0]                 probe1,
  input   [0:0]                 probe2,
  input   [23:0]                probe3,
  input                         clk
);

  ChipWatcher_cwc  ChipWatcher_Inst
  (
      .probe0(probe0),
      .probe1(probe1),
      .probe2(probe2),
      .probe3(probe3),
      .clk(clk)
  );
endmodule
