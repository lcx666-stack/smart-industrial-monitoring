`timescale 1ns/1ps
module cs500_sensor_frame_counter_tb;
    reg pixel_clk = 0;
    reg register_clk = 0;
    reg resetn = 0;
    reg pixel_frame_start = 0;
    wire [31:0] frame_count;
    always #7 pixel_clk = ~pixel_clk;
    always #5 register_clk = ~register_clk;

    cs500_sensor_frame_counter dut (
        .pixel_clk(pixel_clk), .register_clk(register_clk),
        .resetn(resetn), .pixel_frame_start(pixel_frame_start),
        .frame_count(frame_count)
    );

    task frame_start;
        begin
            @(negedge pixel_clk);
            pixel_frame_start = 1;
            repeat (3) @(negedge pixel_clk);
            pixel_frame_start = 0;
            repeat (9) @(negedge pixel_clk);
        end
    endtask

    integer i;
    initial begin
        repeat (4) @(negedge pixel_clk);
        resetn = 1;
        for (i = 0; i < 11; i = i + 1) frame_start();
        repeat (8) @(negedge register_clk);
        if (frame_count !== 32'd11)
            $fatal(1, "expected 11 sensor frames, got %0d", frame_count);
        resetn = 0;
        repeat (3) @(negedge register_clk);
        if (frame_count !== 0)
            $fatal(1, "sensor frame count failed reset");
        $display("PASS: independent pixel frame count crosses clock domains");
        $finish;
    end
endmodule
