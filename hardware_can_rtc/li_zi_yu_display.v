// 48 x 16 bitmap of U+674E, U+81EA, U+6631, from left to right.
// Connect x/y to the local pixel coordinates supplied by a display driver.
module li_zi_yu_display (
    input  wire [5:0] x,
    input  wire [3:0] y,
    output wire       pixel
);
    reg [255:0] bitmap;

    always @(*) begin
        case (x[5:4])
            2'd0: bitmap = 256'h018001807FFE07E00DB0399E7FF6103000C001807FFE01800180070002000000;
            2'd1: bitmap = 256'h030003001FF81FF8100810081FF8100810081FF8100810081FF8100800000000;
            2'd2: bitmap = 256'h00001FFC100C100C1FFC100C1FFC008001803FFC00000430042004607FFE0000;
            default: bitmap = 256'b0;
        endcase
    end

    assign pixel = bitmap[8'hFF - {y, x[3:0]}];
endmodule
