

module rgb_24b_to_32b (
    input wire        I_clk,
    input wire        I_rst,
  
    input wire        I_vsync,
    input wire        I_hsync,
    input wire        I_de,
    input wire[23:0]  I_data,
 
    output reg        O_vsync,
    output reg        O_hsync,
    output reg        O_de,
    output reg[31:0]  O_data
);

    parameter  H_ACTIVE     = 1024;


    localparam H_ACTIVE_32B   = H_ACTIVE*3/4;
    localparam FIFO_RD_OFFSET = H_ACTIVE - H_ACTIVE_32B;

    reg        S_de_1d;
    reg[23:0]  S_data_1d;
    wire       S_24b_to_32b_en;
    reg[1:0]   S_cnt;
    wire       S_fifo_full;//synthesis keep
    wire[8:0]  S_fifo_wr_count;//synthesis keep
    wire       S_fifo_wr_en;//synthesis keep
    wire[31:0] S_fifo_wr_data;//synthesis keep
    wire       S_fifo_empty;//synthesis keep
    wire       S_fifo_aempty;//synthesis keep
    reg        S_fifo_aempty_1d;//synthesis keep
    wire	   S_fifo_rd_flag;//synthesis keep
	wire[8:0]  S_fifo_rd_count;
    reg        S_fifo_rd_en;//synthesis keep
    wire[31:0] S_fifo_rd_data;//synthesis keep
    reg        S_de;

    reg        S_vsync_1d;
    reg        S_hsync_1d;
    wire       S_vsync_p_edge;
    wire       S_hsync_p_edge;
    reg        S_vsync_delay_en;
    reg        S_hsync_delay_en;
    reg[9:0]   S_vsync_delay_cnt;
    reg[9:0]   S_hsync_delay_cnt;
    wire       S_vsync_delay_pulse;
    wire       S_hsync_delay_pulse;



/*
	dsi接口是4条数据lane，因此在输出的时候将数据打包成32位输出，然后每个字节分配给不同的lane
	
	需要将24bit rgb排列的数据转换为32bit输出，过程如下：
	       
		    R G B  R G B  R G B  R G B  R G B  R G B  R G B  R G B 
			-----  -----  -----  -----  -----  -----  -----  -----
			  ↓      ↓      ↓      ↓      ↓      ↓      ↓      ↓
	        R G B  R G B  R G B  R G B  R G B  R G B  R G B  R G B
	        -------- -------- --------  -------- -------- --------
	            ↓       ↓        ↓         ↓        ↓        ↓
	           RGBR    GBRG     BRGB      RGBR     GBRG     BRGB
	
	所以每4个24bit的rgb排列的数据转换成3个32bit的bgr排列的数据
	
	在实现的时候将输入的数据打一拍，然后根据计数器的值对数据进行重新排列，组成32bit的数据，时序如下图：
	
	I_clk             __/--\__/--\__/--\__/--\__/--\__/--\__/--\__/--\__/--\__/--\__
	I_de              __/-----------------------------------------------\___________
	S_de_1d           ________/-----------------------------------------------\_____
	I_data            x>< rgb>< rgb>< rgb>< rgb>< rgb>< rgb>< rgb>< rgb><xxxxxxxxxxx
	S_data_1d         xxxxxxx>< rgb>< rgb>< rgb>< rgb>< rgb>< rgb>< rgb>< rgb><xxxxx
	S_24b_to_32b_en   ________/-----------------------------------------\___________
	S_cnt             xxxxxxx><  0 ><  1 ><  2 ><  3 ><  0 ><  1 ><  2 ><  3 ><xxxxx
    S_fifo_wr_en      ________/----------------\______/-----------------\___________
	S_fifo_wr_data    x><0000><rgbr><gbrg><brgb><0000><rgbr><gbrg><brgb><0000><0000>
*/


    always @(posedge I_clk) begin
        S_vsync_1d <= I_vsync;
        S_hsync_1d <= I_hsync;
        S_de_1d    <= I_de;
        S_data_1d  <= I_data;
    end

    assign S_vsync_p_edge = ~S_vsync_1d & I_vsync;
    assign S_hsync_p_edge = ~S_hsync_1d & I_hsync;

    assign S_24b_to_32b_en = S_de_1d & I_de;

    always @(posedge I_clk) begin
        if(S_24b_to_32b_en)
            S_cnt <= S_cnt + 1'b1;
        else
            S_cnt <= 'd0;
    end

    assign S_fifo_wr_en   = S_24b_to_32b_en && (S_cnt != 'd3) ? 1'b1 : 1'b0;

    assign S_fifo_wr_data = S_cnt == 2'd0 ? {S_data_1d[23:16], S_data_1d[15:8], S_data_1d[7:0],I_data[23:16]} : ///R G B R
                            S_cnt == 2'd1 ? {S_data_1d[15:8],  S_data_1d[7:0],  I_data[23:16], I_data[15:8]}  : ///G B R G
                            S_cnt == 2'd2 ? {S_data_1d[7:0],   I_data[23:16],   I_data[15:8],  I_data[7:0]}   : 32'd0;


	fifo_w32_d512 U_fifo_w32_d512(
		.rst            ( I_rst | I_vsync ),									      
		.clk            ( I_clk           ),
                        
		.di             ( S_fifo_wr_data  ),
		.we             ( S_fifo_wr_en    ),
        .full_flag      ( S_fifo_full     ),
        .afull          (),                            
        .wrusedw        ( S_fifo_wr_count ),                            

		.re             ( S_fifo_rd_en    ),
        .valid          (),
		.dout           ( S_fifo_rd_data  ),
		.empty_flag     ( S_fifo_empty    ),
        .aempty         ( S_fifo_aempty   ),		
        .rdusedw        ( S_fifo_rd_count )
	);
    


//    always @(posedge I_clk) begin
//        S_fifo_aempty_1d <= S_fifo_aempty;
//    end
//    assign S_fifo_rd_flag = S_fifo_aempty_1d & !S_fifo_aempty;
   
    always @(posedge I_clk or posedge I_rst) begin
        if(I_rst)
            S_fifo_rd_en <= 1'b0;
        else
            if(S_fifo_rd_count == FIFO_RD_OFFSET)//S_fifo_rd_flag
                S_fifo_rd_en <= 1'b1;
            else if(S_fifo_empty)
                S_fifo_rd_en <= 1'b0;
            else
                S_fifo_rd_en <= S_fifo_rd_en;
    end


    always @(posedge I_clk) begin
        if(!S_fifo_empty && S_fifo_rd_en)
            S_de <= 1'b1;
        else
            S_de <= 1'b0;
    end


    always @(posedge I_clk or posedge I_rst) begin
        if(I_rst)
            S_vsync_delay_en <= 1'b0;
        else
            if(S_vsync_p_edge)
                S_vsync_delay_en <= 1'b1;
            else if(S_vsync_delay_cnt == FIFO_RD_OFFSET)
                S_vsync_delay_en <= 1'b0;
            else
                S_vsync_delay_en <= S_vsync_delay_en;
    end

    always @(posedge I_clk) begin
        if(S_vsync_delay_en)
            S_vsync_delay_cnt <= S_vsync_delay_cnt + 1'b1;
        else
            S_vsync_delay_cnt <= 'd0;
    end

    always @(posedge I_clk or posedge I_rst) begin
        if(I_rst)
            S_hsync_delay_en <= 1'b0;
        else
            if(S_hsync_p_edge)
                S_hsync_delay_en <= 1'b1;
            else if(S_hsync_delay_cnt == FIFO_RD_OFFSET)
                S_hsync_delay_en <= 1'b0;
            else
                S_hsync_delay_en <= S_hsync_delay_en;
    end

    always @(posedge I_clk) begin
        if(S_hsync_delay_en)
            S_hsync_delay_cnt <= S_hsync_delay_cnt + 1'b1;
        else
            S_hsync_delay_cnt <= 'd0;
    end

    assign S_vsync_delay_pulse = S_vsync_delay_cnt == FIFO_RD_OFFSET && S_vsync_delay_en ? 1'b1 : 1'b0;
    assign S_hsync_delay_pulse = S_hsync_delay_cnt == FIFO_RD_OFFSET && S_hsync_delay_en ? 1'b1 : 1'b0;

    always @(posedge I_clk) begin
        O_de    <= S_de;
        O_data  <= {S_fifo_rd_data[7:0],S_fifo_rd_data[15:8],S_fifo_rd_data[23:16],S_fifo_rd_data[31:24]};
        O_vsync <= S_vsync_delay_pulse;
        O_hsync <= S_hsync_delay_pulse;
    end


endmodule