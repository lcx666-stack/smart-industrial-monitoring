
module reset_gen (
    input wire     I_clk,
    input wire     I_pll_lock,
	input wire     I_rst,

    output reg     O_rst_n,
    output reg     O_rst,

    output reg     O_config_start
);


    reg[31:0]  S_cnt;

    always @(posedge I_clk or posedge I_rst) begin
		if(I_rst || (!I_pll_lock))    
			S_cnt <= 'd0;
        else
            if(S_cnt == 'd242857142)
                S_cnt <= S_cnt;
            else
                S_cnt <= S_cnt + 1'b1;
    end

    always @(posedge I_clk) begin
        if(S_cnt < 200)// if(S_cnt > 100 && S_cnt < 200)
            begin
                O_rst   <= 1'b1;
                O_rst_n <= 1'b0;
            end
        else
            begin
                O_rst   <= 1'b0;
                O_rst_n <= 1'b1;
            end
    end

    always @(posedge I_clk) begin
        if(S_cnt > 'd300 && S_cnt < 'd400)
            O_config_start <= 1'b1;
        else
            O_config_start <= 1'b0;
    end
    
endmodule