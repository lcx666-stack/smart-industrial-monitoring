`timescale 1ns/1ps

// Two AXI4 write-only masters to the existing 64-bit PS HP0 port.
// Master 0 is the motor waveform DMA; master 1 is the CS500 frame writer.
// A grant lasts for exactly one AW/W/B transaction, not for a whole capture.
// Thus both clients can remain active while bursts are interleaved fairly.
module axi_write_burst_arbiter (
    input  wire         clk,
    input  wire         resetn,
    input  wire [1:0]   m_awvalid,
    output wire [1:0]   m_awready,
    input  wire [11:0]  m_awid,
    input  wire [65:0]  m_awaddr,
    input  wire [7:0]   m_awlen,
    input  wire [3:0]   m_awsize,
    input  wire [3:0]   m_awburst,
    input  wire [1:0]   m_awlock,
    input  wire [7:0]   m_awcache,
    input  wire [5:0]   m_awprot,
    input  wire [7:0]   m_awqos,
    input  wire [1:0]   m_wvalid,
    output wire [1:0]   m_wready,
    input  wire [127:0] m_wdata,
    input  wire [15:0]  m_wstrb,
    input  wire [1:0]   m_wlast,
    output wire [1:0]   m_bvalid,
    input  wire [1:0]   m_bready,
    output wire [11:0]  m_bid,
    output wire [3:0]   m_bresp,
    output wire [5:0]   s_awid,
    output wire [32:0]  s_awaddr,
    output wire [3:0]   s_awlen,
    output wire [1:0]   s_awsize,
    output wire [1:0]   s_awburst,
    output wire         s_awlock,
    output wire [3:0]   s_awcache,
    output wire [2:0]   s_awprot,
    output wire [3:0]   s_awqos,
    output wire         s_awvalid,
    input  wire         s_awready,
    output wire [63:0]  s_wdata,
    output wire [7:0]   s_wstrb,
    output wire         s_wlast,
    output wire         s_wvalid,
    input  wire         s_wready,
    input  wire [5:0]   s_bid,
    input  wire [1:0]   s_bresp,
    input  wire         s_bvalid,
    output wire         s_bready,
    output reg          protocol_error,
    output wire         busy
);
    localparam [1:0] IDLE = 0, SEND_AW = 1, SEND_W = 2, SEND_B = 3;
    reg [1:0] state;
    reg owner;
    reg last_owner;
    reg [5:0] outstanding_id;
    wire select_motor = m_awvalid[0] && (!m_awvalid[1] || last_owner);
    assign busy = state != IDLE;

    assign s_awid    = owner ? m_awid[11:6] : m_awid[5:0];
    assign s_awaddr  = owner ? m_awaddr[65:33] : m_awaddr[32:0];
    assign s_awlen   = owner ? m_awlen[7:4] : m_awlen[3:0];
    assign s_awsize  = owner ? m_awsize[3:2] : m_awsize[1:0];
    assign s_awburst = owner ? m_awburst[3:2] : m_awburst[1:0];
    assign s_awlock  = m_awlock[owner];
    assign s_awcache = owner ? m_awcache[7:4] : m_awcache[3:0];
    assign s_awprot  = owner ? m_awprot[5:3] : m_awprot[2:0];
    assign s_awqos   = owner ? m_awqos[7:4] : m_awqos[3:0];
    assign s_awvalid = state == SEND_AW && m_awvalid[owner];
    assign m_awready = state == SEND_AW && s_awready ?
                       (owner ? 2'b10 : 2'b01) : 2'b00;

    assign s_wdata  = owner ? m_wdata[127:64] : m_wdata[63:0];
    assign s_wstrb  = owner ? m_wstrb[15:8] : m_wstrb[7:0];
    assign s_wlast  = m_wlast[owner];
    assign s_wvalid = state == SEND_W && m_wvalid[owner];
    assign m_wready = state == SEND_W && s_wready ?
                      (owner ? 2'b10 : 2'b01) : 2'b00;

    assign s_bready = state == SEND_B && m_bready[owner];
    assign m_bvalid = state == SEND_B && s_bvalid ?
                      (owner ? 2'b10 : 2'b01) : 2'b00;
    assign m_bid = {s_bid, s_bid};
    assign m_bresp = {s_bresp, s_bresp};

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            state <= IDLE;
            owner <= 0;
            last_owner <= 1;
            outstanding_id <= 0;
            protocol_error <= 0;
        end else begin
            if (s_bvalid && state != SEND_B) protocol_error <= 1;
            case (state)
                IDLE: if (|m_awvalid) begin
                    owner <= !select_motor;
                    state <= SEND_AW;
                end
                SEND_AW: if (s_awvalid && s_awready) begin
                    outstanding_id <= s_awid;
                    state <= SEND_W;
                end
                SEND_W: if (s_wvalid && s_wready && s_wlast)
                    state <= SEND_B;
                SEND_B: if (s_bvalid && s_bready) begin
                    if (s_bid != outstanding_id) protocol_error <= 1;
                    last_owner <= owner;
                    state <= IDLE;
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
