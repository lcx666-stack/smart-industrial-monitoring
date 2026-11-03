

module ecc_gen (
    input wire       I_clk,
    input wire       I_rst,

    input wire[23:0] I_ecc_data_in,
    output reg[7:0]  O_ecc_data_out
);

   
   wire [7:0] S_ecc_cal;   

   always @ (posedge I_clk or posedge I_rst) 
   begin
      if (I_rst) 
         O_ecc_data_out <= 0;
      else 
         O_ecc_data_out <= S_ecc_cal;
   end

   assign S_ecc_cal[0] = I_ecc_data_in[16] ^ I_ecc_data_in[17] ^ I_ecc_data_in[18] ^ I_ecc_data_in[20] ^ I_ecc_data_in[21] ^ I_ecc_data_in[23] ^ I_ecc_data_in[10] ^ I_ecc_data_in[11] ^ I_ecc_data_in[13] ^ I_ecc_data_in[0] ^ I_ecc_data_in[4] ^ I_ecc_data_in[5] ^ I_ecc_data_in[6] ^ I_ecc_data_in[7];
   assign S_ecc_cal[1] = I_ecc_data_in[16] ^ I_ecc_data_in[17] ^ I_ecc_data_in[19] ^ I_ecc_data_in[20] ^ I_ecc_data_in[22] ^ I_ecc_data_in[8] ^ I_ecc_data_in[10] ^ I_ecc_data_in[12] ^ I_ecc_data_in[14] ^ I_ecc_data_in[1] ^ I_ecc_data_in[4] ^ I_ecc_data_in[5] ^ I_ecc_data_in[6] ^ I_ecc_data_in[7];
   assign S_ecc_cal[2] = I_ecc_data_in[16] ^ I_ecc_data_in[18] ^ I_ecc_data_in[19] ^ I_ecc_data_in[21] ^ I_ecc_data_in[22] ^ I_ecc_data_in[9] ^ I_ecc_data_in[11] ^ I_ecc_data_in[12] ^ I_ecc_data_in[15] ^ I_ecc_data_in[2] ^ I_ecc_data_in[4] ^ I_ecc_data_in[5] ^ I_ecc_data_in[6];
   assign S_ecc_cal[3] = I_ecc_data_in[17] ^ I_ecc_data_in[18] ^ I_ecc_data_in[19] ^ I_ecc_data_in[23] ^ I_ecc_data_in[8]  ^ I_ecc_data_in[9] ^ I_ecc_data_in[13] ^ I_ecc_data_in[14] ^ I_ecc_data_in[15] ^ I_ecc_data_in[3] ^ I_ecc_data_in[4] ^ I_ecc_data_in[5] ^ I_ecc_data_in[7];
   assign S_ecc_cal[4] = I_ecc_data_in[20] ^ I_ecc_data_in[21] ^ I_ecc_data_in[22] ^ I_ecc_data_in[23] ^ I_ecc_data_in[8]  ^ I_ecc_data_in[9] ^ I_ecc_data_in[0] ^ I_ecc_data_in[1] ^ I_ecc_data_in[2] ^ I_ecc_data_in[3] ^ I_ecc_data_in[4] ^ I_ecc_data_in[6] ^ I_ecc_data_in[7];
   assign S_ecc_cal[5] = I_ecc_data_in[10] ^ I_ecc_data_in[11] ^ I_ecc_data_in[12] ^ I_ecc_data_in[13] ^ I_ecc_data_in[14] ^ I_ecc_data_in[15] ^ I_ecc_data_in[0] ^ I_ecc_data_in[1] ^ I_ecc_data_in[2] ^ I_ecc_data_in[3] ^ I_ecc_data_in[5] ^ I_ecc_data_in[6] ^ I_ecc_data_in[7];
   assign S_ecc_cal[6] = 0;              
   assign S_ecc_cal[7] = 0;     
    
endmodule