`timescale 1ns/1ps

// One complete 32-byte ADC frame per AXI4 write transaction. The producer
// and AXI port share clk; no asynchronous FIFO is implied by this module.
// A frame becomes visible to software only after its successful B response.
module motor_sample_dma #(
    parameter integer FIFO_ADDR_BITS = 4,
    parameter integer AXI_ADDR_WIDTH = 33,
    parameter integer AXI_ID_WIDTH = 6
) (
    input  wire clk,
    input  wire reset,                 // active-low synchronous reset
    input  wire start_pulse,
    input  wire stop_pulse,
    input  wire [AXI_ADDR_WIDTH-1:0] dma_base,
    input  wire [31:0] dma_size,      // byte size, multiple of 32
    input  wire [31:0] consumed_bytes,// monotonic byte count from PS
    input  wire data_valid,
    input  wire signed [15:0] current_raw_code,
    input  wire signed [15:0] vibration1_data,
    input  wire signed [15:0] vibration2_data,
    input  wire signed [15:0] vibration3_data,
    input  wire signed [31:0] current_mA,
    input  wire [63:0] sample_ticks, // latched at the common CONVST edge
    input  wire [31:0] frame_flags,
    output reg  [31:0] produced_bytes,
    output reg  [31:0] dropped_frames,
    output reg  [31:0] frame_seq,
    output reg  overflow_sticky,
    output reg  dma_error,
    output reg  [1:0] last_bresp,
    output reg  active,
    output wire busy,
    output reg  irq_pulse,
    output reg  [FIFO_ADDR_BITS:0] fifo_used,
    output wire [AXI_ID_WIDTH-1:0] m_axi_awid,
    output reg  [AXI_ADDR_WIDTH-1:0] m_axi_awaddr,
    output wire [3:0] m_axi_awlen,
    output wire [1:0] m_axi_awsize,
    output wire [1:0] m_axi_awburst,
    output wire m_axi_awlock,
    output wire [3:0] m_axi_awcache,
    output wire [2:0] m_axi_awprot,
    output wire [3:0] m_axi_awqos,
    output wire m_axi_awvalid,
    input  wire m_axi_awready,
    output reg  [63:0] m_axi_wdata,
    output wire [7:0] m_axi_wstrb,
    output wire m_axi_wlast,
    output wire m_axi_wvalid,
    input  wire m_axi_wready,
    input  wire [AXI_ID_WIDTH-1:0] m_axi_bid,
    input  wire [1:0] m_axi_bresp,
    input  wire m_axi_bvalid,
    output wire m_axi_bready
);
    localparam integer FIFO_DEPTH = (1 << FIFO_ADDR_BITS);
    localparam [1:0] IDLE = 0, SEND_AW = 1, SEND_W = 2, WAIT_B = 3;
    localparam [31:0] FRAME_MAGIC = 32'h314d5246; // "FRM1" little-endian

    reg [255:0] fifo [0:FIFO_DEPTH-1];
    reg [FIFO_ADDR_BITS-1:0] wr_ptr, rd_ptr;
    reg [255:0] write_frame;
    reg [1:0] beat_index, state;
    reg [31:0] ring_offset, dma_size_latched;
    reg [AXI_ADDR_WIDTH-1:0] dma_base_latched;
    wire [AXI_ADDR_WIDTH:0] end_address =
        {1'b0, dma_base} + {{(AXI_ADDR_WIDTH-31){1'b0}}, dma_size};
    wire valid_config = (dma_base[4:0] == 0) &&
                        (dma_size >= 32) && (dma_size[4:0] == 0) &&
                        !dma_size[31] && !end_address[AXI_ADDR_WIDTH];
    wire [31:0] occupied_bytes = produced_bytes - consumed_bytes;
    wire room_in_ring = (occupied_bytes <= dma_size_latched - 32);
    wire enqueue = active && data_valid && !start_pulse &&
                   !stop_pulse && !dma_error;
    wire push = enqueue && (fifo_used < FIFO_DEPTH);
    wire pop = (state == IDLE) && (fifo_used != 0) && !start_pulse &&
               !dma_error && room_in_ring;
    wire b_handshake = (state == WAIT_B) && m_axi_bvalid;
    wire b_failure = b_handshake && ((m_axi_bresp != 0) ||
                                     (m_axi_bid != {AXI_ID_WIDTH{1'b0}}));

    assign busy = (state != IDLE) || (fifo_used != 0);
    assign m_axi_awid = {AXI_ID_WIDTH{1'b0}};
    assign m_axi_awlen = 4'd3; // four 64-bit beats = one complete frame
    assign m_axi_awsize = 2'd3;
    assign m_axi_awburst = 2'b01; // INCR
    assign m_axi_awlock = 1'b0;
    assign m_axi_awcache = 4'b0011;
    assign m_axi_awprot = 3'b000;
    assign m_axi_awqos = 4'b0000;
    assign m_axi_awvalid = (state == SEND_AW);
    assign m_axi_wstrb = 8'hff;
    assign m_axi_wlast = (beat_index == 2'd3);
    assign m_axi_wvalid = (state == SEND_W);
    assign m_axi_bready = (state == WAIT_B);

    always @* begin
        case (beat_index)
            2'd0: m_axi_wdata = write_frame[63:0];
            2'd1: m_axi_wdata = write_frame[127:64];
            2'd2: m_axi_wdata = write_frame[191:128];
            default: m_axi_wdata = write_frame[255:192];
        endcase
    end

    always @(posedge clk) begin
        if (!reset) begin
            wr_ptr <= 0;
            rd_ptr <= 0;
            fifo_used <= 0;
            write_frame <= 0;
            beat_index <= 0;
            state <= IDLE;
            dma_base_latched <= 0;
            dma_size_latched <= 0;
            ring_offset <= 0;
            m_axi_awaddr <= 0;
            produced_bytes <= 0;
            dropped_frames <= 0;
            frame_seq <= 0;
            overflow_sticky <= 0;
            dma_error <= 0;
            last_bresp <= 0;
            active <= 0;
            irq_pulse <= 0;
        end else begin
            irq_pulse <= 0;
            if (start_pulse && !stop_pulse && (state == IDLE)) begin
                wr_ptr <= 0;
                rd_ptr <= 0;
                fifo_used <= 0;
                ring_offset <= 0;
                produced_bytes <= 0;
                dropped_frames <= 0;
                frame_seq <= 0;
                overflow_sticky <= 0;
                dma_error <= !valid_config;
                last_bresp <= 0;
                active <= valid_config;
                dma_base_latched <= dma_base;
                dma_size_latched <= dma_size;
            end else begin
                if (stop_pulse) active <= 0;
                if (enqueue) begin
                    frame_seq <= frame_seq + 32'd1;
                    if (push) begin
                        // 4 raw codes, sequence/flags, CONVST time, current/magic.
                        fifo[wr_ptr] <= {FRAME_MAGIC, current_mA,
                                         sample_ticks, frame_flags, frame_seq,
                                         vibration3_data, vibration2_data,
                                         vibration1_data, current_raw_code};
                        wr_ptr <= wr_ptr + 1'b1;
                    end else begin
                        dropped_frames <= dropped_frames + 32'd1;
                        overflow_sticky <= 1;
                    end
                end
                case ({push, pop})
                    2'b10: fifo_used <= fifo_used + 1'b1;
                    2'b01: fifo_used <= fifo_used - 1'b1;
                    default: begin end
                endcase
                case (state)
                    IDLE: if (pop) begin
                        write_frame <= fifo[rd_ptr];
                        rd_ptr <= rd_ptr + 1'b1;
                        m_axi_awaddr <= dma_base_latched + ring_offset;
                        beat_index <= 0;
                        state <= SEND_AW;
                    end
                    SEND_AW: if (m_axi_awready) state <= SEND_W;
                    SEND_W: if (m_axi_wready) begin
                        if (beat_index == 2'd3) state <= WAIT_B;
                        else beat_index <= beat_index + 1'b1;
                    end
                    WAIT_B: if (m_axi_bvalid) begin
                        last_bresp <= m_axi_bresp;
                        state <= IDLE;
                        if (!b_failure) begin
                            produced_bytes <= produced_bytes + 32'd32;
                            ring_offset <= (ring_offset == dma_size_latched - 32) ?
                                           32'd0 : ring_offset + 32'd32;
                            irq_pulse <= 1;
                        end
                    end
                endcase
                if (b_failure) begin
                    // The failed frame and all queued frames are unusable.
                    dma_error <= 1;
                    active <= 0;
                    overflow_sticky <= 1;
                    dropped_frames <= dropped_frames + fifo_used + 32'd1 +
                                      (enqueue ? 32'd1 : 32'd0);
                    fifo_used <= 0;
                    wr_ptr <= 0;
                    rd_ptr <= 0;
                end
            end
        end
    end
endmodule
