`timescale 1ns/1ps

// Diagnostic only: count CSI-derived frame starts independently of DDR capture.
// A toggle crosses the pixel->register clock domain; frame starts are much
// farther apart than either clock period, so no pulse can be missed.
module cs500_sensor_frame_counter (
    input wire pixel_clk,
    input wire register_clk,
    input wire resetn,
    input wire pixel_frame_start,
    output reg [31:0] frame_count
);
    reg frame_start_d;
    reg frame_toggle;
    (* ASYNC_REG = "TRUE" *) reg [2:0] toggle_sync;

    always @(posedge pixel_clk or negedge resetn) begin
        if (!resetn) begin
            frame_start_d <= 1'b0;
            frame_toggle <= 1'b0;
        end else begin
            frame_start_d <= pixel_frame_start;
            if (pixel_frame_start && !frame_start_d)
                frame_toggle <= ~frame_toggle;
        end
    end

    always @(posedge register_clk or negedge resetn) begin
        if (!resetn) begin
            toggle_sync <= 3'b000;
            frame_count <= 32'd0;
        end else begin
            toggle_sync <= {toggle_sync[1:0], frame_toggle};
            if (toggle_sync[2] != toggle_sync[1])
                frame_count <= frame_count + 1'b1;
        end
    end
endmodule
