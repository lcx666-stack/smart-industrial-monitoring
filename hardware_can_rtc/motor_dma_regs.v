`timescale 1ns/1ps

// DMA control/status in the unused half of the existing 4-KiB ERAM window.
// Word addresses 0x20..0x2b correspond to byte offsets 0x80..0xac.
// Read output is zero on any read outside this block so it can be ORed with
// motor_status_regs.mem_dout after the common registered read edge.
module motor_dma_regs (
    input  wire clk,
    input  wire resetn,
    input  wire [9:0] mem_addr,
    input  wire [3:0] mem_web,
    input  wire mem_csb,
    input  wire [31:0] mem_din,
    output reg  [31:0] mem_dout,
    output reg  [32:0] dma_base,
    output reg  [31:0] dma_size,
    output reg  [31:0] consumed_bytes,
    output reg  start_pulse,
    output reg  stop_pulse,
    input  wire [31:0] produced_bytes,
    input  wire [31:0] dropped_frames,
    input  wire [31:0] frame_seq,
    input  wire overflow_sticky,
    input  wire dma_error,
    input  wire [1:0] last_bresp,
    input  wire active,
    input  wire busy,
    input  wire [4:0] fifo_used
);
    function [31:0] merge_bytes;
        input [31:0] previous;
        input [31:0] incoming;
        input [3:0] web;
        integer lane;
        begin
            merge_bytes = previous;
            for (lane = 0; lane < 4; lane = lane + 1)
                if (!web[lane])
                    merge_bytes[lane*8 +: 8] = incoming[lane*8 +: 8];
        end
    endfunction

    always @(posedge clk) begin
        if (!resetn) begin
            dma_base <= 0;
            dma_size <= 0;
            consumed_bytes <= 0;
            start_pulse <= 0;
            stop_pulse <= 0;
            mem_dout <= 0;
        end else begin
            start_pulse <= 0;
            stop_pulse <= 0;
            if (!mem_csb && !(&mem_web)) begin
                case (mem_addr)
                    10'h022: if (!mem_web[0]) begin
                        if (mem_din[1]) stop_pulse <= 1;
                        else if (mem_din[0] && !active && !busy)
                            start_pulse <= 1;
                    end
                    10'h023: if (!active && !busy)
                        dma_base[31:0] <= merge_bytes(dma_base[31:0],
                                                       mem_din, mem_web);
                    10'h024: if (!active && !busy && !mem_web[0])
                        dma_base[32] <= mem_din[0];
                    10'h025: if (!active && !busy)
                        dma_size <= merge_bytes(dma_size, mem_din, mem_web);
                    10'h026: consumed_bytes <=
                        merge_bytes(consumed_bytes, mem_din, mem_web);
                    default: begin end
                endcase
            end
            if (!mem_csb && (&mem_web)) begin
                case (mem_addr)
                    10'h020: mem_dout <= 32'h444d_4131; // DMA1
                    10'h021: mem_dout <= 32'h0001_0000;
                    10'h022: mem_dout <= 0;
                    10'h023: mem_dout <= dma_base[31:0];
                    10'h024: mem_dout <= {31'd0, dma_base[32]};
                    10'h025: mem_dout <= dma_size;
                    10'h026: mem_dout <= consumed_bytes;
                    10'h027: mem_dout <= produced_bytes;
                    10'h028: mem_dout <= dropped_frames;
                    10'h029: mem_dout <= frame_seq;
                    10'h02a: mem_dout <= {26'd0, last_bresp,
                                          dma_error, overflow_sticky,
                                          busy, active};
                    10'h02b: mem_dout <= {27'd0, fifo_used};
                    default: mem_dout <= 0;
                endcase
            end
        end
    end
endmodule
