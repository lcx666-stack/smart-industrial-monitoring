
///pcaket mode: Non-Brust Mode with Sync Events

module dsi_video_mode_packet (
    input wire        I_clk,
    input wire        I_rst,
 
    input wire        I_vsync,
    input wire        I_hsync,
    input wire        I_de,
    input wire[31:0]  I_data,

    output reg        O_hs_en,
    output reg[31:0]  O_hs_data,
    output reg        O_hs_last
);

    parameter  H_ACTIVE = 1024;
    localparam H_ACTIVE_WC = H_ACTIVE * 3;

	function [7:0] ECC;
		input [23:0] data;
		begin
			ECC[7] = 0;
			ECC[6] = 0;
			ECC[5] = data[10] ^ data[11] ^ data[12] ^ data[13] ^ data[14] ^ data[15] ^ data[0] ^ data[1] ^ data[2] ^ data[3] ^ data[5] ^ data[6] ^ data[7];
			ECC[4] = data[20] ^ data[21] ^ data[22] ^ data[23] ^ data[8]  ^ data[9] ^ data[0] ^ data[1] ^ data[2] ^ data[3] ^ data[4] ^ data[6] ^ data[7];
			ECC[3] = data[17] ^ data[18] ^ data[19] ^ data[23] ^ data[8]  ^ data[9] ^ data[13] ^ data[14] ^ data[15] ^ data[3] ^ data[4] ^ data[5] ^ data[7];
			ECC[2] = data[16] ^ data[18] ^ data[19] ^ data[21] ^ data[22] ^ data[9] ^ data[11] ^ data[12] ^ data[15] ^ data[2] ^ data[4] ^ data[5] ^ data[6];
			ECC[1] = data[16] ^ data[17] ^ data[19] ^ data[20] ^ data[22] ^ data[8] ^ data[10] ^ data[12] ^ data[14] ^ data[1] ^ data[4] ^ data[5] ^ data[6] ^ data[7];
			ECC[0] = data[16] ^ data[17] ^ data[18] ^ data[20] ^ data[21] ^ data[23] ^ data[10] ^ data[11] ^ data[13] ^ data[0] ^ data[4] ^ data[5] ^ data[6] ^ data[7];
		end
	endfunction

    localparam VSS_ECC     = ECC({8'h01, 8'h00,            8'h00});
    localparam HSS_ECC     = ECC({8'h21, 8'h00,            8'h00});
    localparam HACT_ST_ECC = ECC({8'h3e, H_ACTIVE_WC[7:0], H_ACTIVE_WC[15:8]});

    localparam VSS_CMD     = {VSS_ECC,     16'h0000,          8'h01};
    localparam HSS_CMD     = {HSS_ECC,     16'h0000,          8'h21};
    localparam HACT_ST_CMD = {HACT_ST_ECC, H_ACTIVE_WC[15:0], 8'h3e};


    reg       S_vsync_1d;
    reg       S_hsync_1d;
    reg       S_de_1d;
    reg       S_de_2d;
    reg[31:0] S_data_1d;
    wire      S_vsync_p_edge;
    wire      S_hsync_p_edge;
    wire      S_de_p_edge;
    wire      S_de_n_edge;

    
    always @(posedge I_clk) begin
        S_vsync_1d <= I_vsync;
        S_hsync_1d <= I_hsync;
        S_de_1d    <= I_de;
        S_de_2d    <= S_de_1d;
        S_data_1d  <= I_data;
    end

    assign S_vsync_p_edge = ~S_vsync_1d & I_vsync;
    assign S_hsync_p_edge = ~S_hsync_1d & I_hsync;
    assign S_de_p_edge    = ~S_de_1d    & I_de;
    assign S_de_n_edge    = ~S_de_1d    & S_de_2d;


    always @(posedge I_clk or posedge I_rst) begin
        if(I_rst)
            begin
                O_hs_en   <= 1'b0;
                O_hs_data <= 'd0;
                O_hs_last <= 1'b0;
            end
        else
            if(S_vsync_p_edge)  
                begin
                    O_hs_en   <= 1'b1;
                    O_hs_data <= VSS_CMD;
                    O_hs_last <= 1'b1;
                end
            else if(S_hsync_p_edge)
                begin
                    O_hs_en   <= 1'b1;
                    O_hs_data <= HSS_CMD;
                    O_hs_last <= 1'b1;
                end
            else if(S_de_p_edge)
                begin
                    O_hs_en   <= 1'b1;
                    O_hs_data <= HACT_ST_CMD;
                    O_hs_last <= 1'b0;
                end
            else if(S_de_1d)
                begin
                    O_hs_en   <= 1'b1;
                    O_hs_data <= S_data_1d;
                    O_hs_last <= 1'b0;
                end
            else if(S_de_n_edge)
                begin                  ///忽略了CRC，直接给0
                    O_hs_en   <= 1'b1;
                    O_hs_data <= 'd0;
                    O_hs_last <= 1'b1;
                end
            else
                begin
                    O_hs_en   <= 1'b0;
                    O_hs_data <= 'd0;
                    O_hs_last <= 1'b0;
                end
    end

endmodule