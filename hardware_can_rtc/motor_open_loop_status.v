`timescale 1ns/1ps

// Read-only identity/actuation metadata in the old encoder-diagnostic window.
// These registers exist only in the distinct 0x4143 open-loop image.
module motor_open_loop_status #(
    parameter integer DUTY_MIN_PERCENT = 10
) (
    input wire clk, resetn,
    input wire [9:0] mem_addr,
    input wire [3:0] mem_web,
    input wire mem_csb,
    input wire [6:0] applied_duty,
    output reg [31:0] mem_dout
);
    always @(posedge clk) begin
        if (!resetn) mem_dout <= 0;
        else if (!mem_csb && (&mem_web)) begin
            case (mem_addr)
                10'h058: mem_dout <= 32'h4f4c_5031; // OLP1
                10'h059: mem_dout <= 32'h0001_0001; // distinct PWM10 metadata ABI
                10'h05a: mem_dout <= {25'd0, applied_duty};
                10'h05b: mem_dout <= DUTY_MIN_PERCENT;
                10'h05c: mem_dout <= 32'd60;       // hard maximum percent
                10'h05d: mem_dout <= 32'd10_000;   // PWM Hz at 100 MHz
                10'h05e: mem_dout <= 32'd10;       // 1% slew interval ms
                default: mem_dout <= 0;
            endcase
        end
    end
endmodule
