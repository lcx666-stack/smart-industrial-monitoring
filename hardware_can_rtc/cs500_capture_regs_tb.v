`timescale 1ns/1ps
module cs500_capture_regs_tb;
    reg clk = 0;
    always #5 clk = ~clk;
    reg resetn = 0;
    reg [9:0] mem_addr = 0;
    reg [3:0] mem_web = 4'b1111;
    reg mem_csb = 1;
    reg [31:0] mem_din = 0;
    wire [31:0] mem_dout;
    reg motor_running = 1;
    reg waveform_dma_active = 1;
    reg sensor_configured = 0;
    reg sensor_i2c_error = 0;
    reg sensor_cfg_done_raw = 0;
    reg sensor_wait_done = 0;
    reg [12:0] link_diag_seen = 0;
    reg [9:0] packet_type_seen = 0;
    reg [8:0] first_nonshort_header = 0;
    reg [31:0] sensor_frame_count = 0;
    reg pll_locked = 1;
    reg frame_done = 0;
    reg frame_writer_busy = 0;
    reg fifo_full = 0;
    reg response_error = 0;
    wire [31:0] frame_base;
    wire capture_mode, start_pulse, clear_pulse, rejected_start;

    cs500_capture_regs dut (
        .clk(clk), .resetn(resetn), .mem_addr(mem_addr),
        .mem_web(mem_web), .mem_csb(mem_csb), .mem_din(mem_din),
        .mem_dout(mem_dout), .motor_running(motor_running),
        .waveform_dma_active(waveform_dma_active),
        .sensor_configured(sensor_configured),
        .sensor_i2c_error(sensor_i2c_error), .pll_locked(pll_locked),
        .sensor_cfg_done_raw(sensor_cfg_done_raw),
        .sensor_wait_done(sensor_wait_done),
        .link_diag_seen(link_diag_seen),
        .packet_type_seen(packet_type_seen),
        .first_nonshort_header(first_nonshort_header),
        .sensor_frame_count(sensor_frame_count),
        .frame_done(frame_done), .frame_writer_busy(frame_writer_busy),
        .fifo_full(fifo_full), .response_error(response_error),
        .frame_base(frame_base), .capture_mode(capture_mode),
        .start_pulse(start_pulse), .clear_pulse(clear_pulse),
        .rejected_start(rejected_start)
    );

    task write_reg(input [9:0] addr, input [31:0] value);
        begin
            @(negedge clk);
            mem_addr = addr; mem_din = value; mem_web = 0; mem_csb = 0;
            @(posedge clk); #1;
            @(negedge clk);
            mem_web = 4'b1111; mem_csb = 1;
        end
    endtask

    initial begin
        repeat (3) @(negedge clk);
        resetn = 1;
        sensor_cfg_done_raw = 1;
        sensor_wait_done = 1;
        @(negedge clk);
        mem_addr = 10'h305; mem_web = 4'b1111; mem_csb = 0;
        @(posedge clk); #1;
        if (mem_dout[13:12] != 2'b11)
            $fatal(1, "camera power-up/config diagnostics missing");
        @(negedge clk);
        mem_csb = 1;
        packet_type_seen = 10'h3cf;
        @(negedge clk);
        mem_addr = 10'h309; mem_web = 4'b1111; mem_csb = 0;
        @(posedge clk); #1;
        if (mem_dout[9:0] != 10'h3cf)
            $fatal(1, "packet-type diagnostics missing");
        @(negedge clk);
        mem_csb = 1;
        first_nonshort_header = 9'h12b;
        @(negedge clk);
        mem_addr = 10'h30a; mem_web = 4'b1111; mem_csb = 0;
        @(posedge clk); #1;
        if (mem_dout[8:0] != 9'h12b)
            $fatal(1, "first long/embedded packet header missing");
        @(negedge clk);
        mem_csb = 1;
        link_diag_seen = 13'h1fff;
        @(negedge clk);
        mem_addr = 10'h308; mem_web = 4'b1111; mem_csb = 0;
        @(posedge clk); #1;
        if (mem_dout[12:0] != 13'h1fff)
            $fatal(1, "link stage diagnostics missing");
        @(negedge clk);
        mem_csb = 1;
        sensor_frame_count = 32'h1234_5678;
        @(negedge clk);
        mem_addr = 10'h30b; mem_web = 4'b1111; mem_csb = 0;
        @(posedge clk); #1;
        if (mem_dout !== 32'h1234_5678)
            $fatal(1, "independent sensor frame counter not readable");
        @(negedge clk);
        mem_csb = 1;
        write_reg(10'h302, 32'h1);
        if (capture_mode || !rejected_start) $fatal(1, "unconfigured start accepted");
        write_reg(10'h303, 32'h1800_0000);
        write_reg(10'h304, 32'd8_294_400);
        sensor_configured = 1;
        write_reg(10'h302, 32'h1);
        if (!capture_mode || rejected_start) $fatal(1, "running-motor capture rejected");
        if (frame_base != 32'h1800_0000) $fatal(1, "wrong frame base");
        frame_done = 1;
        repeat (2) @(negedge clk);
        frame_writer_busy = 1;
        write_reg(10'h302, 32'h2);
        if (!capture_mode) $fatal(1, "cleared while camera writer busy");
        frame_writer_busy = 0;
        write_reg(10'h302, 32'h2);
        if (capture_mode) $fatal(1, "finished frame failed to clear");
        frame_done = 0;
        sensor_i2c_error = 1;
        write_reg(10'h302, 32'h1);
        if (capture_mode || !rejected_start) $fatal(1, "I2C-error start accepted");
        sensor_i2c_error = 0;
        write_reg(10'h303, 32'hffff_ffc0);
        write_reg(10'h302, 32'h1);
        if (capture_mode || !rejected_start) $fatal(1, "overflowing buffer accepted");
        $display("PASS: capture starts with motor and waveform DMA active; buffer and busy checks remain");
        $finish;
    end
endmodule
