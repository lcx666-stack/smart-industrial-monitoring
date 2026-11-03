`timescale 1ns/1ps

// 无需 PID 系数的步进调速；正常调速随测速更新，换向独立降占空比。
module speed_control #(
    parameter integer DUTY_MIN  = 15,  // 正常运行的最小占空比，单位为整数百分比
    parameter integer DUTY_MAX  = 95,  // 正常运行的最大占空比，不得超过 100
    parameter integer DUTY_STEP = 2,   // 每次调整的百分点；允许大步长，结果饱和限幅
    parameter [31:0] SPEED_TOLERANCE = 32'd0, // Q16.16 转/秒的速度死区
    parameter integer RAMP_INTERVAL_CYCLES = 1_000_000, // 100 MHz 下为 10 ms
    parameter integer IMMEDIATE_START = 0 // opt-in image: only initial duty ignores speed_valid
) (
    input  wire        clk,             // 电机控制系统时钟
    input  wire        rst_n,           // 低有效、时钟上升沿同步复位，与 motor 一致
    input  wire        speed_valid,     // 速度更新有效脉冲；正常调速仅在该拍执行
    input  wire [1:0]  ctrl,            // 00 自由停，01 正转，10 反转，11 制动
    input  wire [31:0] target_speed,    // 目标速度，无符号 Q16.16，单位转/秒
    input  wire [31:0] actual_speed,    // 实测速度，无符号 Q16.16，单位转/秒
    input  wire        drive_enable,    // 桥驱动许可；撤销后下一时钟沿清零 duty
    input  wire        drive_direction, // 当前桥驱动方向，1 正转、0 反转
    output reg  [6:0]  duty             // 整数百分比；停车/故障为 0，运行按上下限饱和
);

    localparam [1:0] CTRL_FREE    = 2'b00;
    localparam [1:0] CTRL_FORWARD = 2'b01;
    localparam [1:0] CTRL_REVERSE = 2'b10;
    localparam [1:0] CTRL_BRAKE   = 2'b11;
    localparam       FORWARD      = 1'b1;
    localparam       REVERSE      = 1'b0;

    localparam [31:0] DUTY_MIN_U  = DUTY_MIN;
    localparam [31:0] DUTY_MAX_U  = DUTY_MAX;
    localparam [31:0] DUTY_STEP_U = DUTY_STEP;
    reg [31:0] ramp_counter;

    // 加宽后再运算，避免 7 位加法回绕；先比较可减余量，再执行减法。
    wire [31:0] duty_extended = {25'd0, duty};
    wire [32:0] duty_increased = {1'b0, duty_extended} + {1'b0, DUTY_STEP_U};
    wire [31:0] decrease_margin = (duty_extended > DUTY_MIN_U) ?
                                 duty_extended - DUTY_MIN_U : 32'd0;

    // 使用实际施加到桥上的方向，不使用停车后仍保留旧值的编码器方向。
    wire direction_change_pending = ((ctrl == CTRL_FORWARD) &&
                                     (drive_direction != FORWARD)) ||
                                    ((ctrl == CTRL_REVERSE) &&
                                     (drive_direction != REVERSE));

`ifndef SYNTHESIS
    // 非法参数应在仿真开始即报错，不能静默产生回绕或超长等待。
    initial begin
        if ((DUTY_MIN <= 0) || (DUTY_MIN > DUTY_MAX) || (DUTY_MAX > 100))
            $fatal(1, "speed_control: require 0 < DUTY_MIN <= DUTY_MAX <= 100");
        if (DUTY_STEP <= 0)
            $fatal(1, "speed_control: DUTY_STEP must be positive");
        if (RAMP_INTERVAL_CYCLES <= 0)
            $fatal(1, "speed_control: RAMP_INTERVAL_CYCLES must be positive");
    end
`endif

    always @(posedge clk) begin
        if (!rst_n) begin
            duty         <= 7'd0;
            ramp_counter <= 32'd0;
        end
        // 停车、零目标、驱动禁用优先于调速，不等待一秒测速窗口。
        else if ((ctrl == CTRL_FREE) || (ctrl == CTRL_BRAKE) ||
                 (target_speed == 32'd0) || !drive_enable) begin
            duty         <= 7'd0;
            ramp_counter <= 32'd0;
        end
        // 换向降速采用独立节拍；允许降至最小运行占空比以下，最终归零。
        else if (direction_change_pending) begin
            if (ramp_counter == RAMP_INTERVAL_CYCLES - 1) begin
                ramp_counter <= 32'd0;
                if (duty_extended <= DUTY_STEP_U)
                    duty <= 7'd0;
                else
                    duty <= duty_extended - DUTY_STEP_U;
            end
            else begin
                ramp_counter <= ramp_counter + 1'b1;
            end
        end
        else begin
            ramp_counter <= 32'd0;
            if (IMMEDIATE_START && duty_extended == 0) begin
                duty <= DUTY_MIN_U;
            end else if (speed_valid) begin
                if (duty_extended < DUTY_MIN_U) begin
                    duty <= DUTY_MIN_U;
                end
                else if ((actual_speed < target_speed) &&
                         ((target_speed - actual_speed) > SPEED_TOLERANCE)) begin
                    if (duty_increased >= {1'b0, DUTY_MAX_U})
                        duty <= DUTY_MAX_U;
                    else
                        duty <= duty_increased[6:0];
                end
                else if ((actual_speed > target_speed) &&
                         ((actual_speed - target_speed) > SPEED_TOLERANCE)) begin
                    if (DUTY_STEP_U >= decrease_margin)
                        duty <= DUTY_MIN_U;
                    else
                        duty <= duty_extended - DUTY_STEP_U;
                end
                // 速度误差在容差内时保持 duty 不变。
            end
        end
    end
endmodule
