`timescale 1ns/1ps

// AB 正交编码器四倍频测速：输出轴转速为无符号 Q16.16，单位为转/秒。
// 每一秒更新一次速度；判停必须满足一段完整的 AB 无变化时间。
module rotate_speed #(
    parameter integer CLOCK_HZ    = 100_000_000, // 系统时钟频率，必须大于零
    parameter integer GEAR_RATIO  = 20,          // 减速比，必须大于零
    parameter integer ENCODER_PPR = 500,         // 电机轴每转单相脉冲数
    parameter integer STOP_TIMEOUT_CYCLES = (CLOCK_HZ < 10) ? 1 : CLOCK_HZ / 10,
    parameter integer INPUT_IS_QUALIFIED = 0
) (
    input  wire        clk,             // 与 motor 相同的系统时钟
    input  wire        rst_n,           // 与 motor 一致：低有效、上升沿同步复位
    input  wire        encoder_a,       // 编码器 A 相异步输入
    input  wire        encoder_b,       // 编码器 B 相异步输入
    input  wire        qualified_ready, raw_activity, // only when INPUT_IS_QUALIFIED=1
    output reg  [31:0] speed,           // 速度绝对值，Q16.16 转/秒；溢出时饱和
    output reg         direction,       // 1：A 超前 B；0：B 超前 A
    output reg         speed_valid,     // 每次整秒测速结果更新时拉高一拍
    output reg         encoder_stopped, // 完整静默时间已满足；本拍变化还需看 activity
    output wire        encoder_activity,// 同步后的 AB 本拍有任意变化，包括非法变化
    output wire        encoder_step,    // 本拍有合法四倍频边沿，供安全监测直接使用
    output wire        encoder_invalid  // 本拍 AB 变化但不是合法的单比特 Gray 跳变
);

    // 从第一个乘数起使用 64 位，避免合法的大参数在 32 位乘法中回绕。
    // 默认输出轴每转计数：20 * 500 * 4 = 40,000。
    localparam [63:0] COUNTS_PER_REV = 64'd4 * GEAR_RATIO * ENCODER_PPR;
    // 非法零参数由下面的检查拒绝；保护表达式也避免展开时发生除零。
    localparam [63:0] SPEED_DIVISOR =
        (COUNTS_PER_REV == 64'd0) ? 64'd1 : COUNTS_PER_REV;
    // Split each encoder step into a constant Q16.16 quotient and remainder.
    // The running sum avoids a wide combinational divider at 100 MHz.
    localparam [31:0] STEP_QUOTIENT = 64'd65536 / SPEED_DIVISOR;
    localparam [63:0] STEP_REMAINDER = 64'd65536 % SPEED_DIVISOR;
    localparam integer REM_BITS =
        (SPEED_DIVISOR <= 64'd1) ? 1 : $clog2(SPEED_DIVISOR);
    localparam FORWARD = 1'b1;
    localparam REVERSE = 1'b0;

    (* ASYNC_REG = "TRUE" *) reg [1:0] a_sync;
    (* ASYNC_REG = "TRUE" *) reg [1:0] b_sync;
    reg [1:0]  encoder_state_d;
    reg [1:0]  sync_ready;
    reg [31:0] second_count;
    reg [31:0] edge_count;
    reg [31:0] no_edge_count;
    reg [31:0] speed_accumulator;
    reg [REM_BITS-1:0] speed_remainder;
    reg speed_overflow;

    wire [1:0] encoder_state = INPUT_IS_QUALIFIED ?
                              {encoder_a,encoder_b} : {a_sync[1],b_sync[1]};
    wire [3:0] state_change  = {encoder_state_d, encoder_state};

    // 合法的四倍频 Gray 跳变；两位同时变化时无法可靠确定方向，不能计数。
    wire forward_step = (state_change == 4'b0010) || // 00 -> 10
                        (state_change == 4'b1011) || // 10 -> 11
                        (state_change == 4'b1101) || // 11 -> 01
                        (state_change == 4'b0100);   // 01 -> 00
    wire reverse_step = (state_change == 4'b0001) || // 00 -> 01
                        (state_change == 4'b0111) || // 01 -> 11
                        (state_change == 4'b1110) || // 11 -> 10
                        (state_change == 4'b1000);   // 10 -> 00
    wire valid_step = forward_step || reverse_step;

    // 直接提供本拍事件，避免顶层仅看到上一拍 stopped 而错误放行换向。
    // 同步器填充期间先建立初始 AB 状态，不把上电非 00 状态当作运动或故障。
    wire qualified_activity = (sync_ready == 2'd3) &&
                              (encoder_state != encoder_state_d);
    // Raw transitions still inhibit stopped/reversal qualification, even if
    // too short to count. Rejected pulses must not fake stationary feedback.
    assign encoder_activity = qualified_activity ||
                              (INPUT_IS_QUALIFIED && raw_activity);
    assign encoder_step     = (sync_ready == 2'd3) && valid_step;
    assign encoder_invalid  = qualified_activity && !valid_step;

    wire [REM_BITS:0] remainder_sum =
        {1'b0, speed_remainder} + STEP_REMAINDER;
    wire remainder_carry = remainder_sum >= SPEED_DIVISOR;
    wire [REM_BITS:0] next_remainder = remainder_carry ?
        remainder_sum - SPEED_DIVISOR : remainder_sum;
    wire [32:0] next_speed_accumulator =
        {1'b0, speed_accumulator} + STEP_QUOTIENT + remainder_carry;

// synthesis translate_off
    initial begin
        if (CLOCK_HZ <= 0)
            $fatal(1, "rotate_speed: CLOCK_HZ must be > 0");
        if (GEAR_RATIO <= 0)
            $fatal(1, "rotate_speed: GEAR_RATIO must be > 0");
        if (ENCODER_PPR <= 0)
            $fatal(1, "rotate_speed: ENCODER_PPR must be > 0");
        if (STOP_TIMEOUT_CYCLES <= 0)
            $fatal(1, "rotate_speed: STOP_TIMEOUT_CYCLES must be > 0");
    end
// synthesis translate_on

    always @(posedge clk) begin
        if (!rst_n) begin
            a_sync          <= 2'b00;
            b_sync          <= 2'b00;
            encoder_state_d <= 2'b00;
            sync_ready      <= 2'b00;
            second_count    <= 32'd0;
            edge_count      <= 32'd0;
            no_edge_count   <= 32'd0;
            speed_accumulator <= 32'd0;
            speed_remainder <= {REM_BITS{1'b0}};
            speed_overflow <= 1'b0;
            speed           <= 32'd0;
            direction       <= FORWARD;
            speed_valid     <= 1'b0;
            encoder_stopped <= 1'b0;
        end
        else begin
            // 两级同步异步输入；编码器相邻状态仍必须满足可采样的稳定时间。
            a_sync      <= {a_sync[0], encoder_a};
            b_sync      <= {b_sync[0], encoder_b};
            speed_valid <= 1'b0;

            if (INPUT_IS_QUALIFIED && !qualified_ready) begin
                sync_ready <= 0;
                encoder_state_d <= encoder_state;
                encoder_stopped <= 0;
                no_edge_count <= 0;
            end else if (sync_ready != 2'd3) begin
                sync_ready      <= INPUT_IS_QUALIFIED ? 2'd3 : sync_ready + 1'b1;
                encoder_state_d <= encoder_state;
            end
            else begin
                encoder_state_d <= encoder_state;

                if (forward_step)
                    direction <= FORWARD;
                else if (reverse_step)
                    direction <= REVERSE;

                // 非法 AB 跳变不参与测速，但同样说明信号并非静止，必须重新计时。
                // 顶层判停放行条件为 encoder_stopped && !encoder_activity。
                if (encoder_activity) begin
                    no_edge_count   <= 32'd0;
                    encoder_stopped <= 1'b0;
                end
                else if (no_edge_count >= STOP_TIMEOUT_CYCLES - 1) begin
                    // 计数器到期后保持，防止长时间静止发生回绕。
                    encoder_stopped <= 1'b1;
                end
                else begin
                    no_edge_count <= no_edge_count + 1'b1;
                end

                if (second_count == CLOCK_HZ - 1) begin
                    // 窗口最后一拍的边沿计入本帧；超过 Q16.16 范围时饱和不回绕。
                    // The boundary edge belongs to this frame, not the next.
                    speed <= (speed_overflow ||
                              (encoder_step && next_speed_accumulator[32])) ?
                             32'hffff_ffff :
                             (encoder_step ? next_speed_accumulator[31:0] :
                                             speed_accumulator);
                    speed_valid  <= 1'b1;
                    second_count <= 32'd0;
                    edge_count   <= 32'd0;
                    speed_accumulator <= 32'd0;
                    speed_remainder <= {REM_BITS{1'b0}};
                    speed_overflow <= 1'b0;
                end
                else begin
                    second_count <= second_count + 1'b1;
                    if (encoder_step) begin
                        edge_count <= edge_count + 1'b1;
                        speed_accumulator <= next_speed_accumulator[31:0];
                        speed_remainder <= next_remainder[REM_BITS-1:0];
                        speed_overflow <= speed_overflow ||
                                          next_speed_accumulator[32];
                    end
                end
            end
        end
    end
endmodule
