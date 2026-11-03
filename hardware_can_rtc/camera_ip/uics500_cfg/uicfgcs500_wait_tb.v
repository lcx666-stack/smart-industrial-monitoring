`timescale 1ns/1ps
module uicfgcs500_wait_tb;
    reg clk = 0;
    always #5 clk = ~clk;
    reg resetn = 0;
    wire scl, sda, cfg_done, ae_done, iic_error, wait_done;
    pullup(sda);
    uicfgcs500 #(.CLK_DIV(16'd15), .POWERUP_WAIT_CYCLES(5)) dut (
        .I_clk(clk), .I_rst_n(resetn), .I_ae_req(1'b0),
        .I_ae(16'd3000), .I_ag(16'd60),
        .O_cam_scl(scl), .IO_cam_sda(sda),
        .O_cfg_done(cfg_done), .O_ae_cfg_done(ae_done),
        .O_iic_error(iic_error), .O_wait_done(wait_done)
    );
    initial begin
        repeat (3) @(negedge clk);
        resetn = 1;
        repeat (4) @(negedge clk);
        if (wait_done || dut.rst_cnt != 0)
            $fatal(1, "I2C configuration started before sensor settle period");
        repeat (2) @(negedge clk);
        if (!wait_done)
            $fatal(1, "sensor settle timer failed to expire");
        repeat (135) @(negedge clk);
        if (!dut.rst_cnt[7])
            $fatal(1, "vendor configuration reset did not release after settle");
        $display("PASS: CS500 I2C configuration waits after reset release");
        $finish;
    end
endmodule
