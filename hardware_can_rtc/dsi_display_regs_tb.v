`timescale 1ns/1ps
module dsi_display_regs_tb;
    reg clk=0;
    always #5 clk=~clk;
    reg resetn=0, mem_csb=1;
    reg [9:0] mem_addr=0;
    reg [3:0] mem_web=4'hf;
    reg [31:0] mem_din=0;
    wire [31:0] mem_dout, requested_frame_base;
    reg panel_ready=0, read_busy=0, reader_armed=0, read_error=0;
    reg vsync_pulse=0;
    reg [31:0] active_frame_base=0;
    reg [31:0] read_error_detail=32'h12345678, first_araddr=32'h18000400;
    wire display_enable, rejected_enable;
    dsi_display_regs dut (
        .clk(clk), .resetn(resetn), .mem_addr(mem_addr),
        .mem_web(mem_web), .mem_csb(mem_csb), .mem_din(mem_din),
        .mem_dout(mem_dout), .panel_ready(panel_ready),
        .read_busy(read_busy), .reader_armed(reader_armed),
        .read_error(read_error), .read_error_detail(read_error_detail),
        .first_araddr(first_araddr), .active_frame_base(active_frame_base),
        .vsync_pulse(vsync_pulse),
        .requested_frame_base(requested_frame_base),
        .display_enable(display_enable),
        .rejected_enable(rejected_enable)
    );
    task write_reg(input [9:0] addr, input [31:0] value);
        begin
            @(negedge clk); mem_addr=addr; mem_din=value;
            mem_web=0; mem_csb=0;
            @(posedge clk); #1;
            @(negedge clk); mem_web=4'hf; mem_csb=1;
        end
    endtask
    initial begin
        repeat(3) @(negedge clk);
        resetn=1;
        write_reg(10'h323,32'h1800_0000);
        write_reg(10'h322,1);
        if(display_enable || !rejected_enable)
            $fatal(1,"started without initialized panel");
        panel_ready=1;
        write_reg(10'h322,1);
        if(!display_enable || rejected_enable)
            $fatal(1,"valid static-frame display rejected");
        write_reg(10'h323,32'h1900_0000);
        if(requested_frame_base!=32'h1800_0000)
            $fatal(1,"changed a live display buffer");
        reader_armed=1; read_busy=1;
        write_reg(10'h322,2);
        if(display_enable) $fatal(1,"failed to disable display");
        write_reg(10'h323,32'h1900_0000);
        if(requested_frame_base!=32'h1800_0000)
            $fatal(1,"changed buffer while read DMA busy");
        reader_armed=0; read_busy=0;
        write_reg(10'h323,32'hffff_ffc0);
        write_reg(10'h322,1);
        if(display_enable || !rejected_enable)
            $fatal(1,"enabled out-of-range DMA buffer");
        @(negedge clk); mem_addr=10'h328; mem_web=4'hf; mem_csb=0;
        @(posedge clk); #1;
        if(mem_dout!=read_error_detail)
            $fatal(1,"DSI error-detail register mismatch");
        @(negedge clk); mem_addr=10'h329;
        @(posedge clk); #1;
        if(mem_dout!=first_araddr)
            $fatal(1,"DSI first-read-address register mismatch");
        $display("PASS: DSI base, enable and drain interlocks");
        $finish;
    end
endmodule
