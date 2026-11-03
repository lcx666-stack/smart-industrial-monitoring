module isp_top (
    input 			axi4s_video_aclk,
    input 			I_rst_n			,
    input 			I_tlast			,
    input 			I_tuser			,
    input [39:0] 	I_tdata			,
    input 			I_tvalid		,
    input [9:0] 	I_tdest			,
    input 			O_tready		,
    output [127:0] 	O_tdata			,
    output 			O_tlast			,
    output 			O_tuser			,
    output 			O_tvalid		,
    output 			I_tready
);


  wire         	BLC_O_tlast;  
  wire         	BLC_O_tuser;  
  wire [39:0] 	BLC_O_tdata;  
  wire         	BLC_O_tvalid;  
  wire [9:0] 	BLC_O_tdest;  
  wire         	BLC_O_tready;  
  
  wire [9:0] 	black_level_offset_r0;
  wire [9:0] 	black_level_offset_r1;
  wire [9:0] 	black_level_offset_r2;
  wire [9:0] 	black_level_offset_r3;
  
  wire         	matrix_tlast;  
  wire         	matrix_tuser;  
  wire         	matrix_tvalid; 
  wire         	matrix_tready; 
  wire         	matrix_bayer_ypos;
  wire [ 95:0] 	matrix_last_line; 
  wire [ 95:0] 	matrix_cur_line;  
  wire [ 95:0] 	matrix_next_line; 

  wire         	m_aixs_tvalid;  
  wire [127:0] 	m_aixs_tdata;  
  wire         	m_aixs_tuser;  
  wire         	m_aixs_tlast;  
  wire         	m_aixs_tready;  
  wire [ 95:0] 	m_aixs_tdata_96;

  wire         	awb_O_tlast;  
  wire         	awb_O_tuser;  
  wire [ 95:0] 	awb_O_tdata;  
  wire         	awb_O_tvalid; 
  wire         	awb_O_tready; 
	
  wire         	gamma_O_tlast;  
  wire         	gamma_O_tuser;  
  wire [ 95:0] 	gamma_O_tdata;  
  wire         	gamma_O_tvalid;  
  wire         	gamma_O_tready;  
	
  wire         	cut_O_tlast;
  wire         	cut_O_tuser;
  wire [ 95:0] 	cut_O_tdata;
  wire         	cut_O_tvalid;
  wire         	cut_O_tready;
	
  wire         	contrast_O_tlast;
  wire         	contrast_O_tuser;
  wire [ 95:0] 	contrast_O_tdata;
  wire         	contrast_O_tvalid;
  wire         	contrast_O_tready;
	
  wire         	Brightness_O_tlast;
  wire         	Brightness_O_tuser;
  wire [ 95:0] 	Brightness_O_tdata;
  wire         	Brightness_O_tvalid;
  wire         	Brightness_O_tready;
	
  wire         	Saturation_O_tlast;
  wire         	Saturation_O_tuser;
  wire [ 95:0] 	Saturation_O_tdata;
  wire         	Saturation_O_tvalid;
  wire         	Saturation_O_tready;

  wire [127:0] 	Saturation_O_tdata_128;  

  assign Saturation_O_tready = O_tready;
  assign O_tdata  = Saturation_O_tdata_128;
  assign O_tlast  = Saturation_O_tlast    ;
  assign O_tuser  = Saturation_O_tuser    ;
  assign O_tvalid = Saturation_O_tvalid   ;


BLC #(
    .Black_level_offset_r0(65),
    .Black_level_offset_r1(65),
    .Black_level_offset_r2(65),
    .Black_level_offset_r3(65)
) u_BLC (
    .I_clk   (axi4s_video_aclk),
    .I_rst_n (I_rst_n ),
    .I_tlast (I_tlast ),
    .I_tuser (I_tuser ),
    .I_tdata (I_tdata ),
    .I_tvalid(I_tvalid),
    .I_tdest (I_tdest ),
    .I_tready(),

    .O_tlast (BLC_O_tlast),
    .O_tuser (BLC_O_tuser),
    .O_tdata (BLC_O_tdata),
    .O_tvalid(BLC_O_tvalid),
    .O_tdest (BLC_O_tdest),
    .O_tready(BLC_O_tready)
);

raw_matrix_3x3_buffer #(
    .IMG_WIDTH (1920),
    .IMG_HEIGHT(1080)
) u_raw_matrix_3x3_buffer (
    .I_clk             (axi4s_video_aclk),
    .I_rst_n           (I_rst_n),
    .axi4s_video_tdata (BLC_O_tdata),
    .axi4s_video_tdest (BLC_O_tdest),
    .axi4s_video_tlast (BLC_O_tlast),
    .axi4s_video_tvalid(BLC_O_tvalid),
    .axi4s_video_tuser (BLC_O_tuser),
    .axi4s_video_tready(BLC_O_tready),
    .O_tlast           (matrix_tlast),
    .O_tuser           (matrix_tuser),
    .O_tvalid          (matrix_tvalid),
    .O_tready          (matrix_tready),
    .bayer_ypos        (matrix_bayer_ypos),
    .matrix_last_line  (matrix_last_line),
    .matrix_cur_line   (matrix_cur_line),
    .matrix_next_line  (matrix_next_line)
);

bilinear_interpolation #(
    .BAYER_MODE("BGGR")
) u_bilinear_interpolation (
    .I_clk           (axi4s_video_aclk),
    .I_rst_n         (I_rst_n),
    .I_tlast         (matrix_tlast),
    .I_tuser         (matrix_tuser),
    .I_tvalid        (matrix_tvalid),
    .I_tready        (matrix_tready),
    .bayer_ypos      (matrix_bayer_ypos),
    .matrix_last_line(matrix_last_line),
    .matrix_cur_line (matrix_cur_line),
    .matrix_next_line(matrix_next_line),
    .O_tlast         (m_aixs_tlast),
    .O_tuser         (m_aixs_tuser),
    .O_tdata         (m_aixs_tdata),
    .O_tvalid        (m_aixs_tvalid),
    .O_tready        (m_aixs_tready)
);

data128_96 u_data128_96 (
    .I_tdata(m_aixs_tdata),
    .O_tdata(m_aixs_tdata_96)
);

// The eight AWB divider pipelines cost substantial PL area. This isolated
// candidate keeps the proven CSI/demosaic/DMA path; color correction is
// deferred to the PC preview or PS software for first NPU bring-up.
image_cut #(
    .IMG_WIDTH(1920),
    .IMG_HEIGHT(1080),
    .DATA_WIDTH(96),
    .SKIP_ROWS_top(0),
    .SKIP_ROWS_bottom(0),
    .SKIP_COLS_left(1),
    .SKIP_COLS_right(0)
) u_image_cut (
    .I_clk   (axi4s_video_aclk),
    .I_rst_n (I_rst_n),
    .I_tlast (m_aixs_tlast),
    .I_tuser (m_aixs_tuser),
    .I_tdata (m_aixs_tdata_96),
    .I_tvalid(m_aixs_tvalid),
    .I_tready(m_aixs_tready),
    .O_tlast (cut_O_tlast),
    .O_tuser (cut_O_tuser),
    .O_tdata (cut_O_tdata),
    .O_tvalid(cut_O_tvalid),
    .O_tready(cut_O_tready)
);

gamma #(
    .GAMMA_10x(22)
) u_gamma (
    .I_clk   (axi4s_video_aclk),
    .I_rst_n (I_rst_n),
    .I_tlast (cut_O_tlast),
    .I_tuser (cut_O_tuser),
    .I_tdata (cut_O_tdata),
    .I_tvalid(cut_O_tvalid),
    .I_tready(cut_O_tready),
    .O_tlast (gamma_O_tlast),
    .O_tuser (gamma_O_tuser),
    .O_tdata (gamma_O_tdata),
    .O_tvalid(gamma_O_tvalid),
    .O_tready(gamma_O_tready)
);

contrast_adj #(
    .contrast_level(140) 
) u_contrast_adj (
    .I_clk   (axi4s_video_aclk),
    .I_rst_n (I_rst_n),
    .I_tlast (gamma_O_tlast),
    .I_tuser (gamma_O_tuser),
    .I_tdata (gamma_O_tdata),
    .I_tvalid(gamma_O_tvalid),
    .I_tready(gamma_O_tready),
    .O_tlast (contrast_O_tlast),
    .O_tuser (contrast_O_tuser),
    .O_tdata (contrast_O_tdata),
    .O_tvalid(contrast_O_tvalid),
    .O_tready(contrast_O_tready)
);

Brightness_adjustment #(
    .BRIGHTNESS_ADD  (0),
    .BRIGHTNESS_MINUS(20)
) u_Brightness_adjustment (
    .I_clk   (axi4s_video_aclk),
    .I_rst_n (I_rst_n),
    .I_tlast (contrast_O_tlast),
    .I_tuser (contrast_O_tuser),
    .I_tdata (contrast_O_tdata),
    .I_tvalid(contrast_O_tvalid),
    .I_tready(contrast_O_tready),
    .O_tlast (Brightness_O_tlast),
    .O_tuser (Brightness_O_tuser),
    .O_tdata (Brightness_O_tdata),
    .O_tvalid(Brightness_O_tvalid),
    .O_tready(Brightness_O_tready)
);

Saturation_adj #(
    .ADJUST_VAL(130)
) u_Saturation_adj (
    .I_clk   (axi4s_video_aclk),
    .I_rst_n (I_rst_n),
    .I_tlast (Brightness_O_tlast),
    .I_tuser (Brightness_O_tuser),
    .I_tdata (Brightness_O_tdata),
    .I_tvalid(Brightness_O_tvalid),
    .I_tready(Brightness_O_tready),
    .O_tlast (Saturation_O_tlast ),
    .O_tuser (Saturation_O_tuser ),
    .O_tdata (Saturation_O_tdata ),
    .O_tvalid(Saturation_O_tvalid),
    .O_tready(Saturation_O_tready)
);

data96_128 u_data96_128 (
    .I_tdata(Saturation_O_tdata),
    .O_tdata(Saturation_O_tdata_128)
);
	
endmodule
