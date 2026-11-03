module instruction_fetch (
    input wire       I_clk,
    input wire       I_rst,

    input wire       I_config_start,
    input wire       I_fetch_trig,

    output reg[9:0]  O_rom_addr,
    input wire[7:0]  I_rom_data,

    ///dcs long write command packet
    output reg       O_long_packet_valid,
    output reg[7:0]  O_long_packet_data,

    ///dcs short write command, 1 parameter
    output reg       O_short_packet_1_valid,
    output reg[7:0]  O_short_packet_1_data,

    ///dcs short write command, no parameter
    output reg       O_short_packet_2_valid,
    output reg[7:0]  O_short_packet_2_data,

    ///delay
    output reg       O_delay_valid,
    output reg[7:0]  O_delay_data,

    output reg       O_end_valid
);

    localparam LONG_PACKET_INST    = 8'h01;
    localparam SHORT_PACKET_1_INST = 8'h02;
    localparam SHORT_PACKET_2_INST = 8'h03;
    localparam DELAY_INST          = 8'h04;
    localparam END_INST            = 8'h05;


    reg       S_config_start_1d;
    reg       S_config_start_2d;
    wire      S_config_start_p_edge;//synthesis keep
    wire      S_instruction_fetch_trig;//synthesis keep
    wire      S_rom_en;
    reg[7:0]  S_rom_data_1d;


    reg       S_long_packet_inst_en;
    reg       S_long_packet_inst_en_1d;
    reg       S_long_packet_num_en;
    reg       S_long_packet_num_en_1d;
    reg       S_long_packet_data_en;
    reg       S_long_packet_data_en_1d;
    reg[7:0]  S_long_packet_data_cnt;
    reg[7:0]  S_long_packet_num_lock;


    reg       S_short_packet_1_inst_en;
    reg       S_short_packet_1_inst_en_1d;
    reg       S_short_packet_1_data_en;
    reg       S_short_packet_1_data_en_1d;


    reg       S_short_packet_2_inst_en;
    reg       S_short_packet_2_data_en;
    reg       S_short_packet_2_zero_en;


    reg       S_delay_inst_en;
    reg       S_delay_inst_en_1d;
    reg       S_delay_data_en;
    reg       S_delay_data_en_1d;
    reg[2:0]  S_delay_data_en_cnt;



    always @(posedge I_clk) begin
        S_config_start_1d <= I_config_start;
        S_config_start_2d <= S_config_start_1d;
    end


    assign S_config_start_p_edge = ~S_config_start_2d & S_config_start_1d;

    assign S_instruction_fetch_trig = S_config_start_p_edge | I_fetch_trig;

    assign S_rom_en = S_instruction_fetch_trig | S_long_packet_num_en  | 
                      S_long_packet_data_en | S_short_packet_1_data_en | 
                      S_short_packet_2_data_en | S_delay_data_en;


    always @(posedge I_clk or posedge I_rst) begin
        if(I_rst)
            O_rom_addr <= 'd0;
        else
            if(S_rom_en)
                O_rom_addr <= O_rom_addr + 1'b1;
            else
                O_rom_addr <= O_rom_addr;
    end

    always @(posedge I_clk) begin
        S_rom_data_1d  <= I_rom_data;
    end


///******************************  长包指令取指  ************************************

    always @(posedge I_clk) begin
        if(S_instruction_fetch_trig && I_rom_data == LONG_PACKET_INST)
            S_long_packet_inst_en <= 1'b1;
        else
            S_long_packet_inst_en <= 1'b0;
    end


    always @(posedge I_clk) begin
        S_long_packet_num_en <= S_long_packet_inst_en;
    end


    always @(posedge I_clk or posedge I_rst) begin
        if(I_rst)
            S_long_packet_num_lock <= 'd0;
        else
            if(S_long_packet_num_en)
                S_long_packet_num_lock <= I_rom_data;
            else if(!S_long_packet_data_en)
                S_long_packet_num_lock <= 'd0;
            else
                S_long_packet_num_lock <= S_long_packet_num_lock;
    end


    always @(posedge I_clk or posedge I_rst) begin
        if(I_rst)
            S_long_packet_data_en <= 1'b0;
        else
            if(S_long_packet_num_en)
                S_long_packet_data_en <= 1'b1;
            else if(S_long_packet_data_cnt == S_long_packet_num_lock-1)
                S_long_packet_data_en <= 1'b0;
            else
                S_long_packet_data_en <= S_long_packet_data_en;
    end


    always @(posedge I_clk) begin
        if(S_long_packet_data_en)
            S_long_packet_data_cnt <= S_long_packet_data_cnt + 1'b1;
        else
            S_long_packet_data_cnt <= 'd0;
    end


    always @(posedge I_clk) begin
        S_long_packet_inst_en_1d <= S_long_packet_inst_en;
        S_long_packet_num_en_1d  <= S_long_packet_num_en;
        S_long_packet_data_en_1d <= S_long_packet_data_en;
    end


    always @(posedge I_clk) begin
        if(S_long_packet_num_en_1d)
            begin
                O_long_packet_valid <= 1'b1;
                O_long_packet_data  <= S_rom_data_1d;
            end
        else if(S_long_packet_data_en_1d)
            begin
                O_long_packet_valid <= 1'b1;
                O_long_packet_data  <= I_rom_data;
            end
        else
            begin
                O_long_packet_valid <= 1'b0;
                O_long_packet_data  <= 'd0;
            end
    end


///******************************  短包指令1取指  ************************************

    always @(posedge I_clk) begin
        if(S_instruction_fetch_trig && I_rom_data == SHORT_PACKET_1_INST)
            S_short_packet_1_inst_en <= 1'b1;
        else
            S_short_packet_1_inst_en <= 1'b0;
    end


    always @(posedge I_clk or posedge I_rst) begin
        if(I_rst)
            S_short_packet_1_data_en <= 1'b0;
        else
            if(S_short_packet_1_inst_en)
                S_short_packet_1_data_en <= 1'b1;
            else if(S_short_packet_1_data_en_1d)
                S_short_packet_1_data_en <= 1'b0;
            else
                S_short_packet_1_data_en <= S_short_packet_1_data_en;
    end


    always @(posedge I_clk) begin
        S_short_packet_1_data_en_1d <= S_short_packet_1_data_en;
        S_short_packet_1_inst_en_1d <= S_short_packet_1_inst_en;
    end


    always @(posedge I_clk) begin
        if(S_short_packet_1_data_en_1d)
            begin
                O_short_packet_1_valid <= 1'b1;
                O_short_packet_1_data  <= I_rom_data;
            end
        else
            begin
                O_short_packet_1_valid <= 1'b0;
                O_short_packet_1_data  <= 'd0;
            end
    end


///******************************  短包指令2取指  ************************************

    always @(posedge I_clk) begin
        if(S_instruction_fetch_trig && I_rom_data == SHORT_PACKET_2_INST)
            S_short_packet_2_inst_en <= 1'b1;
        else
            S_short_packet_2_inst_en <= 1'b0;
    end


    always @(posedge I_clk) begin
        S_short_packet_2_data_en <= S_short_packet_2_inst_en;
        S_short_packet_2_zero_en <= S_short_packet_2_data_en;
    end


    always @(posedge I_clk) begin
        if(S_short_packet_2_data_en)
            begin
                O_short_packet_2_valid <= 1'b1;
                O_short_packet_2_data  <= I_rom_data;
            end
        else if(S_short_packet_2_zero_en)
            begin
                O_short_packet_2_valid <= 1'b1;
                O_short_packet_2_data  <= 'd0;
            end
        else
            begin
                O_short_packet_2_valid <= 1'b0;
                O_short_packet_2_data  <= 'd0;
            end
    end


///******************************  延时指令取指  ************************************

    always @(posedge I_clk) begin
        if(S_instruction_fetch_trig && I_rom_data == DELAY_INST)
            S_delay_inst_en <= 1'b1;
        else
            S_delay_inst_en <= 1'b0;
    end


    always @(posedge I_clk or posedge I_rst) begin
        if(I_rst)
            S_delay_data_en <= 1'b0;
        else
            if(S_delay_inst_en)
                S_delay_data_en <= 1'b1;
            else if(S_delay_data_en_cnt == 'd3)
                S_delay_data_en <= 1'b0;
            else
                S_delay_data_en <= S_delay_data_en;
    end


    always @(posedge I_clk) begin
        if(S_delay_data_en)
            S_delay_data_en_cnt <= S_delay_data_en_cnt + 1'b1;
        else
            S_delay_data_en_cnt <= 'd0;
    end


    always @(posedge I_clk) begin
        S_delay_inst_en_1d <= S_delay_inst_en;
        S_delay_data_en_1d <= S_delay_data_en;
    end


    always @(posedge I_clk) begin
        if(S_delay_data_en_1d)
            begin
                O_delay_valid <= 1'b1;
                O_delay_data  <= I_rom_data;
            end
        else
            begin
                O_delay_valid <= 1'b0;
                O_delay_data  <= 'd0;
            end
    end


///******************************  结束指令取指  ************************************

    always @(posedge I_clk) begin
        if(S_instruction_fetch_trig && I_rom_data == END_INST)
            O_end_valid <= 1'b1;
        else
            O_end_valid <= 1'b0;
    end


endmodule