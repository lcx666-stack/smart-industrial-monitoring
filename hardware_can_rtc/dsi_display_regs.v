`timescale 1ns/1ps

// PS-controlled static snapshot display at word 0x320..0x327 (byte 0xC80).
// The PS must retain ownership of the CMA buffer until disable is acknowledged
// and read_busy has returned low. This block never controls the motor.
module dsi_display_regs (
    input  wire        clk,
    input  wire        resetn,
    input  wire [9:0]  mem_addr,
    input  wire [3:0]  mem_web,
    input  wire        mem_csb,
    input  wire [31:0] mem_din,
    output reg  [31:0] mem_dout,
    input  wire        panel_ready,
    input  wire        read_busy,
    input  wire        reader_armed,
    input  wire        read_error,
    input  wire [31:0] read_error_detail,
    input  wire [31:0] first_araddr,
    input  wire [31:0] active_frame_base,
    input  wire        vsync_pulse,
    output reg  [31:0] requested_frame_base,
    output reg         display_enable,
    output reg         rejected_enable
);
    localparam [32:0] FRAME_BYTES = 33'd8_294_400;
    wire full_write = !mem_csb && mem_web == 4'b0000;
    wire valid_base = requested_frame_base != 0 &&
                      requested_frame_base[5:0] == 0 &&
                      ({1'b0, requested_frame_base} + FRAME_BYTES - 1) <=
                      33'h0_ffff_ffff;
    reg [31:0] vsync_count;
    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            requested_frame_base <= 0;
            display_enable <= 0;
            rejected_enable <= 0;
            vsync_count <= 0;
        end else begin
            if (vsync_pulse) vsync_count <= vsync_count + 1'b1;
            if (full_write) begin
                case (mem_addr)
                    10'h322: begin
                        if (mem_din[1]) display_enable <= 0;
                        else if (mem_din[0]) begin
                            if (valid_base && panel_ready && !read_busy &&
                                !reader_armed && !read_error) begin
                                display_enable <= 1;
                                rejected_enable <= 0;
                            end else rejected_enable <= 1;
                        end
                        if (mem_din[2] && !display_enable)
                            rejected_enable <= 0;
                    end
                    10'h323: if (!display_enable && !read_busy)
                                 requested_frame_base <= mem_din;
                    default: ;
                endcase
            end
        end
    end
    always @(posedge clk or negedge resetn) begin
        if (!resetn) mem_dout <= 0;
        else if (!mem_csb && mem_web == 4'b1111) begin
            case (mem_addr)
                10'h320: mem_dout <= 32'h4453_4931; // DSI1
                10'h321: mem_dout <= 32'h0001_0000;
                10'h322: mem_dout <= 0;
                10'h323: mem_dout <= requested_frame_base;
                10'h324: mem_dout <= {26'd0, rejected_enable, read_error,
                                      panel_ready, read_busy, reader_armed,
                                      display_enable};
                10'h325: mem_dout <= active_frame_base;
                10'h326: mem_dout <= vsync_count;
                10'h327: mem_dout <= {16'd1024, 16'd600};
                10'h328: mem_dout <= read_error_detail;
                10'h329: mem_dout <= first_araddr;
                default: mem_dout <= 0;
            endcase
        end else mem_dout <= 0;
    end
endmodule
