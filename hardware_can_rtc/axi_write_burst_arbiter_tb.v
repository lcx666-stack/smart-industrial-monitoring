`timescale 1ns/1ps
module axi_write_burst_arbiter_tb;
    reg clk = 0;
    always #5 clk = ~clk;
    reg resetn = 0;
    reg [1:0] m_awvalid = 0, m_wvalid = 0, m_wlast = 0;
    reg [11:0] m_awid = {6'd1, 6'd0};
    reg [65:0] m_awaddr = {33'h0_1900_0000, 33'h0_1800_0000};
    reg [7:0] m_awlen = {4'd3, 4'd1};
    reg [3:0] m_awsize = {2'd3, 2'd3};
    reg [3:0] m_awburst = {2'd1, 2'd1};
    reg [1:0] m_awlock = 0;
    reg [7:0] m_awcache = 0, m_awqos = 0;
    reg [5:0] m_awprot = 0;
    reg [127:0] m_wdata = {64'hcafe_cafe_cafe_cafe, 64'hbeef_beef_beef_beef};
    reg [15:0] m_wstrb = 16'hffff;
    reg [1:0] m_bready = 2'b11;
    wire [1:0] m_awready, m_wready, m_bvalid;
    wire [11:0] m_bid;
    wire [3:0] m_bresp;
    wire [5:0] s_awid, s_bid;
    wire [32:0] s_awaddr;
    wire [3:0] s_awlen, s_awcache, s_awqos;
    wire [1:0] s_awsize, s_awburst;
    wire s_awlock, s_awvalid, s_wlast, s_wvalid, s_bready;
    wire [2:0] s_awprot;
    wire [63:0] s_wdata;
    wire [7:0] s_wstrb;
    reg s_awready = 0, s_wready = 0, s_bvalid = 0;
    reg [5:0] s_bid_reg = 0;
    reg [1:0] s_bresp = 0;
    wire protocol_error, busy;
    integer motor_aws = 0, camera_aws = 0, motor_bs = 0, camera_bs = 0;
    integer slave_beats = 0;
    integer expected_beats = 0;
    integer cycle = 0;
    reg [1:0] slave_state = 0;

    assign s_bid = s_bid_reg;
    axi_write_burst_arbiter dut (
        .clk(clk), .resetn(resetn),
        .m_awvalid(m_awvalid), .m_awready(m_awready), .m_awid(m_awid),
        .m_awaddr(m_awaddr), .m_awlen(m_awlen), .m_awsize(m_awsize),
        .m_awburst(m_awburst), .m_awlock(m_awlock), .m_awcache(m_awcache),
        .m_awprot(m_awprot), .m_awqos(m_awqos),
        .m_wvalid(m_wvalid), .m_wready(m_wready), .m_wdata(m_wdata),
        .m_wstrb(m_wstrb), .m_wlast(m_wlast),
        .m_bvalid(m_bvalid), .m_bready(m_bready), .m_bid(m_bid),
        .m_bresp(m_bresp),
        .s_awid(s_awid), .s_awaddr(s_awaddr), .s_awlen(s_awlen),
        .s_awsize(s_awsize), .s_awburst(s_awburst), .s_awlock(s_awlock),
        .s_awcache(s_awcache), .s_awprot(s_awprot), .s_awqos(s_awqos),
        .s_awvalid(s_awvalid), .s_awready(s_awready),
        .s_wdata(s_wdata), .s_wstrb(s_wstrb), .s_wlast(s_wlast),
        .s_wvalid(s_wvalid), .s_wready(s_wready),
        .s_bid(s_bid), .s_bresp(s_bresp), .s_bvalid(s_bvalid),
        .s_bready(s_bready), .protocol_error(protocol_error), .busy(busy)
    );

    // A delayed slave with alternating AW and W backpressure.
    always @(negedge clk) begin
        cycle = cycle + 1;
        s_awready = slave_state == 0 && cycle[0];
        s_wready = slave_state == 1 && cycle[1];
    end
    always @(posedge clk) begin
        if (!resetn) begin
            slave_state <= 0;
            s_bvalid <= 0;
            slave_beats <= 0;
        end else begin
            case (slave_state)
                0: if (s_awvalid && s_awready) begin
                    if (s_awid == 0) begin
                        if (s_awaddr != 33'h0_1800_0000 || s_awlen != 1)
                            $fatal(1, "motor AW corrupted");
                        motor_aws <= motor_aws + 1;
                    end else if (s_awid == 1) begin
                        if (s_awaddr != 33'h0_1900_0000 || s_awlen != 3)
                            $fatal(1, "camera AW corrupted");
                        camera_aws <= camera_aws + 1;
                    end else $fatal(1, "unknown AXI ID");
                    s_bid_reg <= s_awid;
                    expected_beats <= s_awlen + 1;
                    slave_beats <= 0;
                    slave_state <= 1;
                end
                1: if (s_wvalid && s_wready) begin
                    slave_beats <= slave_beats + 1;
                    if (s_wlast) begin
                        if (slave_beats + 1 != expected_beats)
                            $fatal(1, "burst length corrupted");
                        s_bvalid <= 1;
                        slave_state <= 2;
                    end
                end
                2: if (s_bvalid && s_bready) begin
                    s_bvalid <= 0;
                    slave_state <= 0;
                end
            endcase
            if (m_bvalid[0] && m_bready[0]) begin
                if (m_bid[5:0] != 0) $fatal(1, "wrong motor response ID");
                motor_bs <= motor_bs + 1;
            end
            if (m_bvalid[1] && m_bready[1]) begin
                if (m_bid[11:6] != 1) $fatal(1, "wrong camera response ID");
                camera_bs <= camera_bs + 1;
            end
        end
    end

    task automatic send_burst(input integer master, input integer beats);
        integer beat;
        begin
            @(negedge clk);
            m_awvalid[master] = 1;
            do @(posedge clk); while (!m_awready[master]);
            @(negedge clk);
            m_awvalid[master] = 0;
            for (beat = 0; beat < beats; beat = beat + 1) begin
                m_wvalid[master] = 1;
                m_wlast[master] = beat == beats - 1;
                do @(posedge clk); while (!m_wready[master]);
                @(negedge clk);
            end
            m_wvalid[master] = 0;
            m_wlast[master] = 0;
            wait (m_bvalid[master]);
            @(negedge clk);
        end
    endtask

    initial begin
        integer round;
        repeat (4) @(negedge clk);
        resetn = 1;
        for (round = 0; round < 4; round = round + 1) begin
            fork
                send_burst(0, 2);
                send_burst(1, 4);
            join
        end
        repeat (3) @(negedge clk);
        if (motor_aws != 4 || camera_aws != 4 || motor_bs != 4 || camera_bs != 4)
            $fatal(1, "bursts lost: AW=%0d/%0d B=%0d/%0d",
                   motor_aws, camera_aws, motor_bs, camera_bs);
        if (protocol_error || busy) $fatal(1, "arbiter stuck or protocol error");
        $display("PASS: motor and camera AXI bursts both completed with backpressure");
        $finish;
    end
    initial begin
        #100000;
        $fatal(1, "timeout");
    end
endmodule
