
module dsi_panel_tpg #(
    parameter DEBUG_LP = 0
) (
    input wire 			I_clk,
    input wire 			I_rst_n,
			
    output wire			O_clk_hs_p,
    output wire			O_clk_lp_p,
    output wire			O_clk_lp_n,

    output wire [3:0] 	O_data_hs_p,
    output wire [3:0] 	O_data_lp_p,
    output wire [3:0] 	O_data_lp_n
);

  wire        S_clk;
  wire        S_clk_x2;
  wire        S_clk_x4;
  wire        S_clk_x4_90d;
  wire        S_lp_clk;

  wire        S_lock;
  wire        S_rst;  
  wire        S_config_start;
  wire        S_config_done;

  wire        S_24b_vsync;  
  wire        S_24b_hsync;  
  wire        S_24b_de;  
  wire [23:0] S_24b_data;  

  wire        S_32b_vsync;  
  wire        S_32b_hsync;  
  wire        S_32b_de;  
  wire [31:0] S_32b_data;  

  wire        S_hs_en; 
  wire        S_hs_last;    
  wire [31:0] S_hs_data; 

  wire        S_lp_tx_valid;
  wire        S_lp_tx_last;
  wire [ 7:0] S_lp_tx_data;
  wire        S_lp_tx_ready;

  // Optional 10 MHz LP-command capture for a dedicated JTAG diagnostic build.
  // No display timing or output is changed in the normal build.
  generate if (DEBUG_LP) begin : g_lp_chipwatcher
    cwc u_dsi_lp_cwc (
        .clk(S_lp_clk),
        .probe0(S_config_done),
        .probe1(S_lp_tx_ready),
        .probe2(S_lp_tx_valid),
        .probe3({S_config_start, S_lp_tx_last, 14'd0, S_lp_tx_data})
    );
  end endgenerate

  reg  [ 7:0] S_frame_cnt;
  reg  [ 3:0] S_tgb_mode;

  dsi_pll u_pll (
      .refclk  (I_clk),
      .reset(~I_rst_n),

      .lock(S_lock),

      .clk0_out(S_clk),
      .clk1_out(S_clk_x2),
      .clk2_out(S_clk_x4),
      .clk3_out(S_clk_x4_90d),
      .clk4_out(S_lp_clk)
  );


  reset_gen u_reset_gen (
      .I_clk     (S_clk),
      .I_pll_lock(S_lock),
      .I_rst     (~I_rst_n),

      .O_rst_n       (),
      .O_rst         (S_rst),
      .O_config_start(S_config_start)
  );


  video_source #(
        .HTOTAL ( 1344 ),
        .HSA    ( 24    ),
        .HBP    ( 136   ),
        .HFP    ( 160   ),
 
        .VTOTAL ( 635 ),
        .VSA    ( 2    ),
        .VBP    ( 21   ),
        .VFP    ( 12   )
  ) u_video_source (
      .I_clk(S_clk),
      .I_rst(S_rst),

      .I_config_done(S_config_done),

      .O_rgb24b_vsync(S_24b_vsync),
      .O_rgb24b_hsync(S_24b_hsync),
      .O_rgb24b_de   (S_24b_de),
      .O_rgb24b_data (S_24b_data)
  );


  rgb_24b_to_32b #(
      .H_ACTIVE(1024)
  ) u_rgb_24b_to_32b (
      .I_clk(S_clk),
      .I_rst(S_rst),

      .I_vsync(S_24b_vsync),
      .I_hsync(S_24b_hsync),
      .I_de   (S_24b_de),
      .I_data (S_24b_data),

      .O_vsync(S_32b_vsync),
      .O_hsync(S_32b_hsync),
      .O_de   (S_32b_de),
      .O_data (S_32b_data)
  );


  dsi_video_mode_packet #(
      .H_ACTIVE(1024)
  ) u_dsi_video_mode_packet (
      .I_clk(S_clk),
      .I_rst(S_rst),

      .I_vsync(S_32b_vsync),
      .I_hsync(S_32b_hsync),
      .I_de   (S_32b_de),
      .I_data (S_32b_data),

      .O_hs_en  (S_hs_en),
      .O_hs_data(S_hs_data),
      .O_hs_last(S_hs_last)
  );


  display_config_wrapper u_display_config_wrapper (
      .I_clk(S_lp_clk),
      .I_rst(S_rst),

      .I_config_start(S_config_start),
      .O_config_done (S_config_done),

      .O_lp_tx_valid(S_lp_tx_valid),
      .O_lp_tx_last (S_lp_tx_last),
      .O_lp_tx_data (S_lp_tx_data),
      .I_lp_tx_ready(S_lp_tx_ready)
  );



  mipi_dphy_tx_wrapper #(
      .LANE_NUM(4),

      .HS_TX_FIFO_TYPE      ("DRAM"),  ///"DRAM","BRAM"
      .LP_TX_FIFO_TYPE      ("DRAM"),  ///"DRAM","BRAM"
      .LP_TX_MAX_DATA_LENGTH(8),       ///1-240

      .CLK_LANE_MODE("CONTINUE"),  ///"INTERRUPT","CONTINUE"

      .T_DATA_LPX       (10),
      .T_DATA_HS_PREPARE(10),
      .T_DATA_HS_ZERO   (20),
      .T_DATA_HS_TRAIL  (20),
      .T_CLK_LPX        (10),
      .T_CLK_PREPARE    (10),
      .T_CLK_ZERO       (10),
      .T_CLK_PRE        (10),
      .T_CLK_POST       (10),
      .T_CLK_TRAIL      (10)
  ) u_mipi_dphy_tx_wrapper (
      .I_hs_clk       (S_clk),
      .I_hs_clk_x2    (S_clk_x2),
      .I_hs_clk_x4    (S_clk_x4),
      .I_hs_clk_x4_90d(S_clk_x4_90d),

      .I_rst(S_rst),

      .I_hs_tx_valid(S_hs_en),
      .I_hs_tx_data (S_hs_data),
      .I_hs_tx_last (S_hs_last),
      .O_hs_tx_ready(),

      .I_lpdt_clk   (S_lp_clk),
      .I_lp_tx_valid(S_lp_tx_valid),
      .I_lp_tx_data (S_lp_tx_data),
      .I_lp_tx_last (S_lp_tx_last),
      .O_lp_tx_ready(S_lp_tx_ready),

      .O_clk_hs_p (O_clk_hs_p),
      .O_data_hs_p(O_data_hs_p),
      .O_clk_lp_p (O_clk_lp_p),
      .O_clk_lp_n (O_clk_lp_n),
      .O_data_lp_p(O_data_lp_p),
      .O_data_lp_n(O_data_lp_n)
  );

  assign O_clk_lp_dir  = 1'b1;
  assign O_data_lp_dir = 4'b1111;


endmodule
