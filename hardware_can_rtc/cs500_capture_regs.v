`timescale 1ns/1ps

// Candidate CS500 register window at word 0x300..0x30A (byte 0xC00).
// A camera capture may start while the motor and waveform DMA are running.
// DDR arbitration, not motor exclusion, is responsible for concurrent writes.
module cs500_capture_regs (
    input  wire        clk,
    input  wire        resetn,
    input  wire [9:0]  mem_addr,
    input  wire [3:0]  mem_web,
    input  wire        mem_csb,
    input  wire [31:0] mem_din,
    output reg  [31:0] mem_dout,
    input  wire        motor_running,
    input  wire        waveform_dma_active,
    input  wire        sensor_configured,
    input  wire        sensor_i2c_error,
    input  wire        sensor_cfg_done_raw,
    input  wire        sensor_wait_done,
    input  wire [12:0] link_diag_seen,
    input  wire [9:0] packet_type_seen,
    input  wire [8:0] first_nonshort_header,
    input  wire [31:0] sensor_frame_count,
    input  wire        pll_locked,
    input  wire        frame_done,
    input  wire        frame_writer_busy,
    input  wire        fifo_full,
    input  wire        response_error,
    output reg  [31:0] frame_base,
    output reg         capture_mode,
    output reg         start_pulse,
    output reg         clear_pulse,
    output reg         rejected_start
);
    localparam [31:0] FRAME_BYTES = 32'd8_294_400;
    reg [31:0] buffer_bytes;
    reg [31:0] frame_seq;
    reg frame_done_d;
    reg done_sticky;
    wire full_write = !mem_csb && mem_web == 4'b0000;
    wire buffer_valid = frame_base != 0 && frame_base[5:0] == 0 &&
                        buffer_bytes == FRAME_BYTES &&
                        ({1'b0, frame_base} + {1'b0, FRAME_BYTES} - 33'd1) <=
                        33'h0_ffff_ffff;
    wire ready_to_start = sensor_configured && !sensor_i2c_error && pll_locked &&
                          !capture_mode && !frame_writer_busy &&
                          !fifo_full && !response_error && buffer_valid;

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            frame_base <= 0;
            buffer_bytes <= 0;
            capture_mode <= 0;
            start_pulse <= 0;
            clear_pulse <= 0;
            rejected_start <= 0;
            frame_seq <= 0;
            frame_done_d <= 0;
            done_sticky <= 0;
        end else begin
            start_pulse <= 0;
            clear_pulse <= 0;
            frame_done_d <= frame_done;
            if (frame_done && !frame_done_d && capture_mode) begin
                frame_seq <= frame_seq + 1'b1;
                done_sticky <= 1;
            end
            if (full_write) begin
                case (mem_addr)
                    10'h302: begin
                        if (mem_din[0]) begin
                            if (ready_to_start) begin
                                capture_mode <= 1;
                                start_pulse <= 1;
                                rejected_start <= 0;
                                done_sticky <= 0;
                            end else rejected_start <= 1;
                        end
                        if (mem_din[1] && capture_mode && done_sticky &&
                            !frame_writer_busy) begin
                            clear_pulse <= 1;
                            capture_mode <= 0;
                            done_sticky <= 0;
                        end
                        if (mem_din[2] && !capture_mode)
                            rejected_start <= 0;
                    end
                    10'h303: if (!capture_mode) frame_base <= mem_din;
                    10'h304: if (!capture_mode) buffer_bytes <= mem_din;
                    default: ;
                endcase
            end
        end
    end

    always @(posedge clk or negedge resetn) begin
        if (!resetn) mem_dout <= 0;
        else if (!mem_csb && mem_web == 4'b1111) begin
            case (mem_addr)
                10'h300: mem_dout <= 32'h4341_4d32; // CAM2
                10'h301: mem_dout <= 32'h0002_0000;
                10'h302: mem_dout <= 0;
                10'h303: mem_dout <= frame_base;
                10'h304: mem_dout <= buffer_bytes;
                10'h305: mem_dout <= {18'd0, sensor_wait_done,
                                      sensor_cfg_done_raw, sensor_i2c_error, rejected_start,
                                      motor_running, waveform_dma_active,
                                      pll_locked, sensor_configured,
                                      fifo_full, response_error,
                                      frame_writer_busy, frame_done,
                                      done_sticky, capture_mode};
                10'h306: mem_dout <= frame_seq;
                10'h307: mem_dout <= FRAME_BYTES;
                10'h308: mem_dout <= {19'd0, link_diag_seen};
                10'h309: mem_dout <= {22'd0, packet_type_seen};
                10'h30a: mem_dout <= {23'd0, first_nonshort_header};
                10'h30b: mem_dout <= sensor_frame_count;
                default: mem_dout <= 0;
            endcase
        end else mem_dout <= 0;
    end
endmodule
