`timescale 1ns/1ps
module pwm10_core_tb;
    reg clk=0, resetn=0;
    always #5 clk=~clk;
    reg [1:0] ctrl=0;
    reg [31:0] target=0;
    wire pwm, an1, an2, stby, fault;
    wire [6:0] duty;
    wire [31:0] status_word;
    reg [9:0] status_addr=10'h05b;
    integer high_count, k;

    motor_open_loop_core #(.DUTY_MIN_PERCENT(10), .RAMP_INTERVAL_CYCLES(1)) dut (
        .clk(clk), .resetn(resetn), .ctrl(ctrl), .target(target),
        .adc_data(8'd0), .adc_busy(1'b0), .adc_first_data(1'b0),
        .pwm(pwm), .AN1(an1), .AN2(an2), .STBY(stby),
        .motor_fault(fault), .debug_duty(duty)
    );
    motor_open_loop_status #(.DUTY_MIN_PERCENT(10)) metadata (
        .clk(clk), .resetn(resetn), .mem_addr(status_addr),
        .mem_web(4'hf), .mem_csb(1'b0), .applied_duty(duty),
        .mem_dout(status_word)
    );

    initial begin
        repeat (3) @(posedge clk);
        resetn=1;
        repeat (3) @(posedge clk);
        if (status_word !== 10) $fatal(1, "10 percent metadata missing");
        status_addr=10'h059;
        repeat (2) @(posedge clk);
        if (status_word !== 32'h0001_0001) $fatal(1, "PWM10 ABI missing");
        ctrl=1; target=9;
        repeat (5) @(posedge clk);
        if (!fault || stby || pwm || duty) $fatal(1, "9 percent must be rejected");
        target=10;
        repeat (20) @(posedge clk);
        if (fault || !stby || !an1 || an2 || duty != 10)
            $fatal(1, "10 percent not accepted");
        high_count=0;
        for (k=0;k<10000;k=k+1) begin
            @(negedge clk);
            if (pwm) high_count=high_count+1;
        end
        if (high_count != 1000) $fatal(1, "10 percent PWM count=%0d", high_count);
        target=61;
        repeat (3) @(posedge clk);
        if (!fault || stby || pwm || duty) $fatal(1, "61 percent must be rejected");
        target=60;
        repeat (65) @(posedge clk);
        if (fault || duty != 60) $fatal(1, "60 percent not accepted");
        ctrl=0; target=0;
        repeat (3) @(posedge clk);
        if (stby || pwm || duty) $fatal(1, "stop must disable outputs");
        $display("PASS PWM10 core metadata, range, PWM ratio, stop");
        $finish;
    end
endmodule
