module crc16_8b (
   input  wire        clk,
   input  wire        rst,
   input  wire        init,
   input  wire [7:0]  din,
   input  wire        din_en,
   output reg  [15:0] crc
);

   wire [15:0] next_crc;
   
   always @ (posedge clk or posedge rst) begin
      if (rst) 
         crc <= 16'hffff;                                                                                              
      else if (init)                                                                                                                                                                                                    
         crc <= 16'hffff;                                                                                                  
      else if (din_en)
         crc <= next_crc;
   end

   assign next_crc[15]  = din[3] ^ din[7] ^ crc[7] ^ crc[3];                              
   assign next_crc[14]  = din[2] ^ din[6] ^ crc[6] ^ crc[2];                              
   assign next_crc[13]  = din[1] ^ din[5] ^ crc[5] ^ crc[1];                             
   assign next_crc[12]  = din[0] ^ din[4] ^ crc[4] ^ crc[0];                             
   assign next_crc[11]  = din[3] ^ crc[3];                                            
   assign next_crc[10]  = din[2] ^ din[3] ^ din[7] ^ crc[7] ^ crc[3] ^ crc[2];               
   assign next_crc[9]  = din[1] ^ din[2] ^ din[6] ^ crc[6] ^ crc[2] ^ crc[1];               
   assign next_crc[8]  = din[0] ^ din[1] ^ din[5] ^ crc[5] ^ crc[1] ^ crc[0];              
   assign next_crc[7]  = din[0] ^ din[4] ^ crc[15] ^ crc[4] ^ crc[0];                      
   assign next_crc[6]  = din[3] ^ crc[14] ^ crc[3];                                     
   assign next_crc[5] = din[2] ^ crc[13] ^ crc[2];                                     
   assign next_crc[4] = din[1] ^ crc[12] ^ crc[1];                                     
   assign next_crc[3] = din[0] ^ din[3] ^ din[7] ^ crc[11] ^ crc[7] ^ crc[3] ^ crc[0];        
   assign next_crc[2] = din[2] ^ din[6] ^ crc[10] ^ crc[6] ^ crc[2];                       
   assign next_crc[1] = din[1] ^ din[5] ^ crc[9] ^ crc[5] ^ crc[1];                      
   assign next_crc[0] = din[0] ^ din[4] ^ crc[8] ^ crc[4] ^ crc[0];                      

endmodule
