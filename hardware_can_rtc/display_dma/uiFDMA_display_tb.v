`timescale 1ns/1ps

// Backpressured AXI model for the vendor display FDMA: 256 64-bit beats are
// exactly the size of one half of a 1024x32bpp display line in our design.
module uiFDMA_display_tb;
    parameter integer TEST_BEATS = 256;
    reg clk = 0;
    always #5 clk = ~clk;
    reg resetn = 0;
    reg req = 0;
    wire busy;
    wire [5:0] arid;
    wire [32:0] araddr;
    wire [7:0] arlen;
    wire [2:0] arsize;
    wire arvalid, arready;
    wire [5:0] rid;
    wire [63:0] rdata;
    wire [1:0] rresp;
    wire rlast, rvalid, rready;
    reg active = 0;
    reg [8:0] remaining = 0;
    integer bursts = 0;
    integer beats_requested = 0;
    integer beats_returned = 0;
    reg [32:0] next_address = 33'h17ec2700;

    assign arready = !active;
    assign rid = 6'd2;
    assign rdata = 64'h12345678abcdef01;
    assign rresp = 2'd0;
    assign rvalid = active;
    assign rlast = active && remaining == 1;

    uiFDMA_display #(
        .M_AXI_B2B_SET(1), .M_AXI_ID_WIDTH(6), .M_AXI_ID(2),
        .M_AXI_ADDR_WIDTH(33), .M_AXI_DATA_WIDTH(64),
        .M_AXI_MAX_BURST_LEN(16)
    ) dut (
        .I_fdma_waddr(33'd0), .I_fdma_wareq(1'b0), .I_fdma_wsize(16'd0),
        .O_fdma_wbusy(), .I_fdma_wdata(64'd0), .O_fdma_wvalid(),
        .I_fdma_wready(1'b0),
        .I_fdma_raddr(33'h17ec2700), .I_fdma_rareq(req),
        .I_fdma_rsize(TEST_BEATS[15:0]), .O_fdma_rbusy(busy),
        .O_fdma_rdata(), .O_fdma_rvalid(), .I_fdma_rready(1'b1),
        .M_AXI_ACLK(clk), .M_AXI_ARESETN(resetn),
        .M_AXI_AWID(), .M_AXI_AWADDR(), .M_AXI_AWLEN(),
        .M_AXI_AWSIZE(), .M_AXI_AWBURST(), .M_AXI_AWLOCK(),
        .M_AXI_AWCACHE(), .M_AXI_AWPROT(), .M_AXI_AWQOS(),
        .M_AXI_AWVALID(), .M_AXI_AWREADY(1'b0),
        .M_AXI_WID(), .M_AXI_WDATA(), .M_AXI_WSTRB(),
        .M_AXI_WLAST(), .M_AXI_WVALID(), .M_AXI_WREADY(1'b0),
        .M_AXI_BID(6'd0), .M_AXI_BRESP(2'd0),
        .M_AXI_BVALID(1'b0), .M_AXI_BREADY(),
        .M_AXI_ARID(arid), .M_AXI_ARADDR(araddr),
        .M_AXI_ARLEN(arlen), .M_AXI_ARSIZE(arsize),
        .M_AXI_ARBURST(), .M_AXI_ARLOCK(), .M_AXI_ARCACHE(),
        .M_AXI_ARPROT(), .M_AXI_ARQOS(), .M_AXI_ARVALID(arvalid),
        .M_AXI_ARREADY(arready),
        .M_AXI_RID(rid), .M_AXI_RDATA(rdata), .M_AXI_RRESP(rresp),
        .M_AXI_RLAST(rlast), .M_AXI_RVALID(rvalid), .M_AXI_RREADY(rready)
    );

    always @(posedge clk) begin
        if (!resetn) begin
            active <= 0;
            remaining <= 0;
        end else begin
            if (arvalid && arready) begin
                if (arlen > 15 || arsize != 3 || arid != 2)
                    $fatal(1, "illegal AXI read request: len=%0d size=%0d id=%0d",
                           arlen, arsize, arid);
                if (araddr != next_address)
                    $fatal(1, "nonsequential AXI address: got=%h expected=%h",
                           araddr, next_address);
                active <= 1;
                remaining <= arlen + 1'b1;
                bursts = bursts + 1;
                beats_requested = beats_requested + arlen + 1;
                next_address = next_address + (arlen + 1) * 8;
                if (beats_requested > TEST_BEATS)
                    $fatal(1, "FDMA requested more than %0d beats", TEST_BEATS);
            end else if (rvalid && rready) begin
                beats_returned = beats_returned + 1;
                if (remaining == 1) active <= 0;
                remaining <= remaining - 1'b1;
            end
        end
    end

    initial begin
        repeat (5) @(negedge clk);
        resetn = 1;
        @(negedge clk); req = 1;
        @(negedge clk); req = 0;
        wait (beats_returned == TEST_BEATS);
        repeat (10) @(negedge clk);
        if (beats_requested != TEST_BEATS || busy || arvalid)
            $fatal(1, "incomplete FDMA: requested=%0d returned=%0d busy=%b arvalid=%b",
                   beats_requested, beats_returned, busy, arvalid);
        $display("PASS: vendor DSI FDMA read %0d beats in %0d valid bursts",
                 TEST_BEATS, bursts);
        $finish;
    end
    initial begin
        #100000;
        $fatal(1, "FDMA simulation timeout; requested=%0d returned=%0d busy=%b",
               beats_requested, beats_returned, busy);
    end
endmodule
