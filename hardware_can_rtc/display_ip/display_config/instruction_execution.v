module instruction_execution (
    input wire       I_clk,
    input wire       I_rst,

    input wire       I_long_packet_valid,
    input wire[7:0]  I_long_packet_data,

    input wire       I_short_packet_1_valid,
    input wire[7:0]  I_short_packet_1_data,

    input wire       I_short_packet_2_valid,
    input wire[7:0]  I_short_packet_2_data,

    input wire       I_delay_valid,
    input wire[7:0]  I_delay_data,

    input wire       I_end_valid,


    output wire      O_fetch_trig,
    output reg       O_config_done,


    output reg       O_lp_tx_valid,
    output reg       O_lp_tx_last,
    output reg[7:0]  O_lp_tx_data,
    input wire       I_lp_tx_ready
);
    

    localparam LONG_PACKET_DT    = 8'h39;
    localparam SHORT_PACKET_1_DT = 8'h15;
    localparam SHORT_PACKET_2_DT = 8'h05;


    reg        S_lp_tx_ready_1d;
    wire       S_lp_tx_ready_p_edge;
 
    ///************** ECC and CRC signal *************
    reg[23:0]  S_ecc_data_in;
    wire[7:0]  S_ecc_data_out;
    wire       S_crc_init;
    reg        S_crc_din_en;
    reg[7:0]   S_crc_din;
    wire[15:0] S_crc_out;


    ///************** long packet signal **************
    reg        S_long_packet_valid_1d;
    reg[7:0]   S_long_packet_data_1d;
    wire       S_long_packet_valid_p_edge;
    reg[8:0]   S_long_packet_num_lock;
    reg[7:0]   S_long_packet_word_count_lock;
    reg        S_long_packet_payload_valid;
    reg[7:0]   S_long_packet_payload_data;
    reg        S_long_packet_payload_valid_1d;
    reg[7:0]   S_long_packet_payload_data_1d;
    reg        S_long_packet_payload_valid_2d;
    reg[7:0]   S_long_packet_payload_data_2d;
    reg        S_long_packet_payload_valid_3d;
    reg[7:0]   S_long_packet_payload_data_3d;
    reg        S_lp_long_packet_valid_gen;
    reg[8:0]   S_lp_long_packet_valid_gen_cnt;
    reg        S_lp_long_packet_valid;
    wire       S_lp_long_packet_last;
    reg[7:0]   S_lp_long_packet_data;


    ///************** short packet 1 signal ***********
    reg        S_short_packet_1_valid_1d;
    reg[7:0]   S_short_packet_1_data_1d;
    reg[7:0]   S_short_packet_1_data_2d;
    reg[7:0]   S_short_packet_1_data_3d;
    wire       S_short_packet_1_trig;
    reg        S_lp_short_packet_1_valid_gen;
    reg[2:0]   S_lp_short_packet_1_valid_cnt;
    reg        S_lp_short_packet_1_valid;
    wire       S_lp_short_packet_1_last;
    reg[7:0]   S_lp_short_packet_1_data;

    ///************** short packet 2 signal ***********
    reg        S_short_packet_2_valid_1d;
    reg[7:0]   S_short_packet_2_data_1d;
    reg[7:0]   S_short_packet_2_data_2d;
    reg[7:0]   S_short_packet_2_data_3d;
    wire       S_short_packet_2_trig;
    reg        S_lp_short_packet_2_valid_gen;
    reg[2:0]   S_lp_short_packet_2_valid_cnt;
    reg        S_lp_short_packet_2_valid;
    wire       S_lp_short_packet_2_last;
    reg[7:0]   S_lp_short_packet_2_data;

    ///************** delay instruction signal ***********
    reg        S_delay_valid_1d;
    reg        S_delay_valid_2d;
    reg        S_delay_valid_3d;
    reg[7:0]   S_delay_data_1d;
    reg[7:0]   S_delay_data_2d;
    reg[7:0]   S_delay_data_3d;
    wire       S_delay_start;
    reg[31:0]  S_delay_time;
    reg        S_delay_en;
    reg[31:0]  S_delay_cnt;
    reg        S_delay_end;



    always @(posedge I_clk) begin
        S_lp_tx_ready_1d <= I_lp_tx_ready;
    end

    assign S_lp_tx_ready_p_edge = ~S_lp_tx_ready_1d & I_lp_tx_ready;

    assign O_fetch_trig = (S_lp_tx_ready_p_edge | S_delay_end) & (~O_config_done);


///************************************ long pakcet data pack *************************************

    always @(posedge I_clk) begin
        S_long_packet_valid_1d <= I_long_packet_valid;
        S_long_packet_data_1d  <= I_long_packet_data;
    end

    assign S_long_packet_valid_p_edge = ~S_long_packet_valid_1d & I_long_packet_valid;


    always @(posedge I_clk or posedge I_rst) begin
        if(I_rst)   
            begin
                S_long_packet_num_lock        <= 'd0;
                S_long_packet_word_count_lock <= 'd0;
            end
        else
            if(S_long_packet_valid_p_edge)
                begin
                    S_long_packet_num_lock        <= I_long_packet_data + 'd6;
                    S_long_packet_word_count_lock <= I_long_packet_data;
                end
            else
                begin
                    S_long_packet_num_lock        <= S_long_packet_num_lock;
                    S_long_packet_word_count_lock <= S_long_packet_word_count_lock;
                end
    end


    always @(posedge I_clk) begin
        if(S_long_packet_valid_1d && I_long_packet_valid)
            begin
                S_long_packet_payload_valid <= 1'b1;
                S_long_packet_payload_data  <= I_long_packet_data;
            end
        else
            begin
                S_long_packet_payload_valid <= 1'b0;
                S_long_packet_payload_data  <= 'd0;
            end
    end
    

    always @(posedge I_clk) begin
        S_long_packet_payload_valid_1d <= S_long_packet_payload_valid;
        S_long_packet_payload_data_1d  <= S_long_packet_payload_data;

        S_long_packet_payload_valid_2d <= S_long_packet_payload_valid_1d;
        S_long_packet_payload_data_2d  <= S_long_packet_payload_data_1d;

        S_long_packet_payload_valid_3d <= S_long_packet_payload_valid_2d;
        S_long_packet_payload_data_3d  <= S_long_packet_payload_data_2d;
    end


    always @(posedge I_clk or posedge I_rst) begin
        if(I_rst)
            S_lp_long_packet_valid_gen <= 1'b0;
        else
            if(S_long_packet_valid_p_edge)
                S_lp_long_packet_valid_gen <= 1'b1;
            else if(S_lp_long_packet_valid_gen_cnt == S_long_packet_num_lock-1)
                S_lp_long_packet_valid_gen <= 1'b0;
            else
                S_lp_long_packet_valid_gen <= S_lp_long_packet_valid_gen;
    end


    always @(posedge I_clk) begin
        if(S_lp_long_packet_valid_gen)
            S_lp_long_packet_valid_gen_cnt <= S_lp_long_packet_valid_gen_cnt + 1'b1;
        else
            S_lp_long_packet_valid_gen_cnt <= 'd0;
    end


    always @(posedge I_clk or posedge I_rst) begin
        if(I_rst)
            begin
                S_lp_long_packet_valid <= 1'b0;
                S_lp_long_packet_data  <= 'd0;
            end
        else
            if(S_lp_long_packet_valid_gen)
                begin
                    S_lp_long_packet_valid <= 1'b1;

                    if(S_long_packet_payload_valid_3d)
                        S_lp_long_packet_data <= S_long_packet_payload_data_3d;
                    else if(S_lp_long_packet_valid_gen_cnt == 'd0)
                        S_lp_long_packet_data <= LONG_PACKET_DT;
                    else if(S_lp_long_packet_valid_gen_cnt == 'd1)
                        S_lp_long_packet_data <= S_long_packet_word_count_lock;
                    else if(S_lp_long_packet_valid_gen_cnt == 'd2)
                        S_lp_long_packet_data <= 8'h00;
                    else if(S_lp_long_packet_valid_gen_cnt == 'd3)
                        S_lp_long_packet_data <= S_ecc_data_out;
                    else if(S_lp_long_packet_valid_gen_cnt == S_long_packet_num_lock-2)
                        S_lp_long_packet_data <= S_crc_out[7:0];
                    else if(S_lp_long_packet_valid_gen_cnt == S_long_packet_num_lock-1)
                        S_lp_long_packet_data <= S_crc_out[15:8];
                    else
                        S_lp_long_packet_data <= S_lp_long_packet_data;
                end
            else
                begin
                    S_lp_long_packet_valid <= 1'b0;
                    S_lp_long_packet_data  <= 'd0;
                end
    end

    assign S_lp_long_packet_last = ~S_lp_long_packet_valid_gen & S_lp_long_packet_valid;


///************************************ short pakcet 1 data pack *************************************

    always @(posedge I_clk) begin
        S_short_packet_1_valid_1d <= I_short_packet_1_valid;
        S_short_packet_1_data_1d  <= I_short_packet_1_data;
        S_short_packet_1_data_2d  <= S_short_packet_1_data_1d;
        S_short_packet_1_data_3d  <= S_short_packet_1_data_2d;
    end

    assign S_short_packet_1_trig = S_short_packet_1_valid_1d & I_short_packet_1_valid;


    always @(posedge I_clk or posedge I_rst) begin
        if(I_rst)   
            S_lp_short_packet_1_valid_gen <= 1'b0;
        else
            if(S_short_packet_1_trig)
                S_lp_short_packet_1_valid_gen <= 1'b1;
            else if(S_lp_short_packet_1_valid_cnt == 'd3)
                S_lp_short_packet_1_valid_gen <= 1'b0;
            else
                S_lp_short_packet_1_valid_gen <= S_lp_short_packet_1_valid_gen;
    end


    always @(posedge I_clk) begin
        if(S_lp_short_packet_1_valid_gen)
            S_lp_short_packet_1_valid_cnt <= S_lp_short_packet_1_valid_cnt + 1'b1;
        else
            S_lp_short_packet_1_valid_cnt <= 'd0;
    end


    always @(posedge I_clk) begin
        if(S_lp_short_packet_1_valid_gen)
            begin
                S_lp_short_packet_1_valid <= 1'b1;

                if(S_lp_short_packet_1_valid_cnt == 'd0)
                    S_lp_short_packet_1_data <= SHORT_PACKET_1_DT;
                else if(S_lp_short_packet_1_valid_cnt == 'd1)
                    S_lp_short_packet_1_data <= S_short_packet_1_data_3d;
                else if(S_lp_short_packet_1_valid_cnt == 'd2)
                    S_lp_short_packet_1_data <= S_short_packet_1_data_3d;
                else if(S_lp_short_packet_1_valid_cnt == 'd3)
                    S_lp_short_packet_1_data <= S_ecc_data_out;
                else
                    S_lp_short_packet_1_data <= S_lp_short_packet_1_data;
            end
        else
            begin
                S_lp_short_packet_1_valid <= 1'b0;
                S_lp_short_packet_1_data  <= 'd0;
            end
    end

    assign S_lp_short_packet_1_last = ~S_lp_short_packet_1_valid_gen & S_lp_short_packet_1_valid;

///************************************ short pakcet 2 data pack *************************************

    always @(posedge I_clk) begin
        S_short_packet_2_valid_1d <= I_short_packet_2_valid;
        S_short_packet_2_data_1d  <= I_short_packet_2_data;
        S_short_packet_2_data_2d  <= S_short_packet_2_data_1d;
        S_short_packet_2_data_3d  <= S_short_packet_2_data_2d;
    end

    assign S_short_packet_2_trig = S_short_packet_2_valid_1d & I_short_packet_2_valid;


    always @(posedge I_clk or posedge I_rst) begin
        if(I_rst)   
            S_lp_short_packet_2_valid_gen <= 1'b0;
        else
            if(S_short_packet_2_trig)
                S_lp_short_packet_2_valid_gen <= 1'b1;
            else if(S_lp_short_packet_2_valid_cnt == 'd3)
                S_lp_short_packet_2_valid_gen <= 1'b0;
            else
                S_lp_short_packet_2_valid_gen <= S_lp_short_packet_2_valid_gen;
    end


    always @(posedge I_clk) begin
        if(S_lp_short_packet_2_valid_gen)
            S_lp_short_packet_2_valid_cnt <= S_lp_short_packet_2_valid_cnt + 1'b1;
        else
            S_lp_short_packet_2_valid_cnt <= 'd0;
    end


    always @(posedge I_clk) begin
        if(S_lp_short_packet_2_valid_gen)
            begin
                S_lp_short_packet_2_valid <= 1'b1;

                if(S_lp_short_packet_2_valid_cnt == 'd0)
                    S_lp_short_packet_2_data <= SHORT_PACKET_2_DT;
                else if(S_lp_short_packet_2_valid_cnt == 'd1)
                    S_lp_short_packet_2_data <= S_short_packet_2_data_3d;
                else if(S_lp_short_packet_2_valid_cnt == 'd2)
                    S_lp_short_packet_2_data <= S_short_packet_2_data_3d;
                else if(S_lp_short_packet_2_valid_cnt == 'd3)
                    S_lp_short_packet_2_data <= S_ecc_data_out;
                else
                    S_lp_short_packet_2_data <= S_lp_short_packet_2_data;
            end
        else
            begin
                S_lp_short_packet_2_valid <= 1'b0;
                S_lp_short_packet_2_data  <= 'd0;
            end
    end

    assign S_lp_short_packet_2_last = ~S_lp_short_packet_2_valid_gen & S_lp_short_packet_2_valid;

///********************************* delay instruction execution *********************************

    always @(posedge I_clk) begin
        S_delay_valid_1d <= I_delay_valid;
        S_delay_valid_2d <= S_delay_valid_1d;
        S_delay_valid_3d <= S_delay_valid_2d;

        S_delay_data_1d  <= I_delay_data;
        S_delay_data_2d  <= S_delay_data_1d;
        S_delay_data_3d  <= S_delay_data_2d;
    end

    assign S_delay_start = I_delay_valid & S_delay_valid_3d;

    always @(posedge I_clk or posedge I_rst) begin
        if(I_rst)
            S_delay_time <= 'd0;
        else
            if(S_delay_start)
                S_delay_time <= {S_delay_data_3d,S_delay_data_2d,S_delay_data_1d,I_delay_data};
            else
                S_delay_time <= S_delay_time;
    end


    always @(posedge I_clk or posedge I_rst) begin
        if(I_rst)
            S_delay_en <= 1'b0;
        else
            if(S_delay_start)
                S_delay_en <= 1'b1;
            else if(S_delay_cnt == S_delay_time)
                S_delay_en <= 1'b0;
            else
                S_delay_en <= S_delay_en;
    end


    always @(posedge I_clk) begin
        if(S_delay_en)  
            S_delay_cnt <= S_delay_cnt + 1'b1;
        else
            S_delay_cnt <= 'd0;
    end


    always @(posedge I_clk) begin
        if(S_delay_en && S_delay_cnt == S_delay_time)
            S_delay_end <= 1'b1;
        else
            S_delay_end <= 1'b0;
    end


///********************************* end instruction execution *********************************

    always @(posedge I_clk or posedge I_rst) begin
        if(I_rst)
            O_config_done <= 1'b0;
        else
            if(I_end_valid)
                O_config_done <= 1'b1;
            else
                O_config_done <= O_config_done;
    end

///*********************************** ECC and CRC calculate ************************************

    always @(posedge I_clk or posedge I_rst) begin
        if(I_rst)
            S_ecc_data_in <= 'd0;
        else
            if(S_long_packet_valid_p_edge)
                S_ecc_data_in <= {LONG_PACKET_DT,I_long_packet_data,8'h00};
            else if(S_short_packet_1_trig)
                S_ecc_data_in <= {SHORT_PACKET_1_DT,S_short_packet_1_data_1d,I_short_packet_1_data};
            else if(S_short_packet_2_trig)
                S_ecc_data_in <= {SHORT_PACKET_2_DT,S_short_packet_2_data_1d,I_short_packet_2_data};
            else
                S_ecc_data_in <= S_ecc_data_in;
    end


    assign S_crc_init = S_long_packet_valid_p_edge;

    always @(posedge I_clk) begin
        if(S_long_packet_payload_valid)
            begin
                S_crc_din_en <= 1'b1;
                S_crc_din    <= S_long_packet_payload_data;
            end
        else
            begin
                S_crc_din_en <= 1'b0;
                S_crc_din    <= 'd0;
            end
    end

    ecc_gen u_ecc_gen(
        .I_clk          ( I_clk         ),
        .I_rst          ( I_rst         ),

        .I_ecc_data_in  ( S_ecc_data_in ),
        .O_ecc_data_out ( S_ecc_data_out  )
    );

    crc16_8b u_crc16_8b(
        .clk    ( I_clk        ),
        .rst    ( I_rst        ),

        .init   ( S_crc_init   ),

        .din    ( S_crc_din    ),
        .din_en ( S_crc_din_en ),

        .crc    ( S_crc_out    )
    );


///*********************************** 长包短包合并输出 ************************************

    always @(posedge I_clk) begin
        if(S_lp_long_packet_valid)
            begin
                O_lp_tx_valid <= 1'b1;
                O_lp_tx_last  <= S_lp_long_packet_last;
                O_lp_tx_data  <= S_lp_long_packet_data;
            end
        else if(S_lp_short_packet_1_valid)
            begin
                O_lp_tx_valid <= 1'b1;
                O_lp_tx_last  <= S_lp_short_packet_1_last;
                O_lp_tx_data  <= S_lp_short_packet_1_data;
            end
        else if(S_lp_short_packet_2_valid)
            begin
                O_lp_tx_valid <= 1'b1;
                O_lp_tx_last  <= S_lp_short_packet_2_last;
                O_lp_tx_data  <= S_lp_short_packet_2_data;
            end
        else
            begin
                O_lp_tx_valid <= 1'b0;
                O_lp_tx_last  <= 1'b0;
                O_lp_tx_data  <= 'd0;
            end
    end


endmodule