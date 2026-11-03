`timescale 1ns/1ps

module PWM (
    clk,
    reset,
    duty,
    pwm
);
    input wire [6:0] duty; // 整数百分比；大于 100 的输入按 100% 饱和
    input wire clk;        // 默认 100 MHz 系统时钟
    input wire reset;      // 低有效、时钟上升沿同步复位，与 motor 一致
    output reg pwm;        // PWM 输出；复位时拉低

    // 计数范围 0..T，周期为 T+1 拍；默认 100 MHz/(9999+1)=10 kHz。
    // T=0 为合法的单拍周期；16 位计数器最大支持 T=65535。
    parameter integer T = 9999;
    reg [15:0] cnt;
    localparam [16:0] PERIOD_CYCLES = T + 17'd1;
    wire [6:0] bounded_duty = (duty > 7'd100) ? 7'd100 : duty;
    // 阈值必须用 17 位：最长周期在 100% 时为 65536，不能截断成 0。
    wire [16:0] counter;
    generate
        if ((PERIOD_CYCLES % 17'd100) == 0) begin : g_exact_percent_scale
            localparam [16:0] CYCLES_PER_PERCENT =
                PERIOD_CYCLES / 17'd100;
            assign counter = CYCLES_PER_PERCENT * bounded_duty;
        end else begin : g_fractional_percent_scale
            wire [23:0] scaled_period =
                PERIOD_CYCLES * {17'd0, bounded_duty};
            assign counter = scaled_period / 24'd100;
        end
    endgenerate

`ifndef SYNTHESIS
    initial begin
        if ((T < 0) || (T > 65535))
            $fatal(1, "PWM: T must be in the range 0..65535");
    end
`endif

    always @(posedge clk) begin
        if (!reset)
            cnt <= 16'd0;
        else if (cnt == T)
            cnt <= 16'd0;
        else
            cnt <= cnt + 1'b1;
    end

    // 不锁存整周期 duty，保留输入归零后的下一拍关闭能力。
    always @(posedge clk) begin
        if (!reset)
            pwm <= 1'b0;
        else if ({1'b0, cnt} < counter)
            pwm <= 1'b1;
        else
            pwm <= 1'b0;
    end
endmodule
