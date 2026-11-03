`timescale 1ns/1ps

// AD7606：8 位字节并口、关闭过采样、每通道两次 RD 拼回 16 位。
// 电流来源由 CURRENT_CHANNEL 选择（默认 IN1）；IN2/IN3/IN4 为三路振动。
// 与 motor 一致：reset 低电平有效，仅在 clk 上升沿执行同步复位。
module data_collect #(
    parameter integer CLOCK_HZ = 100_000_000, // FPGA 输入时钟，单位 Hz
    parameter integer SAMPLE_HZ = 50_000,    // 每通道采样率；默认 50 kSPS
    parameter integer POWERUP_CYCLES = (CLOCK_HZ + 19) / 20, // 上电等待 50 ms
    parameter integer BUSY_TIMEOUT_CYCLES = (CLOCK_HZ + 9_999) / 10_000, // 超时 100 us
    parameter RANGE_10V = 1'b0,             // 0：±5 V；1：±10 V，运行期间固定
    parameter integer CURRENT_ZERO_CODE = RANGE_10V ? 8_192 : 16_384,
    parameter integer CURRENT_SENSITIVITY_MV_PER_A = 185, // ACS712-5A 标称灵敏度
    parameter integer CURRENT_CHANNEL = 0 // 0=IN1, 4=IN5; ADC-only probe overrides to 4
) (
    input  wire clk,                         // FPGA 系统时钟
    input  wire reset,                       // 同步复位，低电平有效，与 motor 相同
    input  wire [7:0] adc_data,               // AD7606 DB7～DB0 字节并口输入
    input  wire adc_busy,                    // BUSY：高表示转换中，异步输入
    input  wire adc_first_data,              // FDA/FRSTDATA：读取第一个通道时为高
    output reg  adc_reset,                   // 接 ADC RST：芯片硬件复位，高电平有效
    output wire adc_convst_a,                // 接 CA：上升沿同时采样 IN1～IN4
    output wire adc_convst_b,                // 接 CB：上升沿同时采样 IN5～IN8
    output reg  adc_cs_n,                    // 接 CS：片选，低电平有效
    output reg  adc_rd_n,                    // 接 RD：读使能，低电平有效
    output wire [2:0] adc_os,                 // 接 OS2～OS0：固定 000，关闭过采样
    output wire adc_range,                   // 接 RANGE：选择双极性输入量程
    output wire adc_serial,                  // 接 SER：固定 1；DB15=1 时选择字节并口
    output wire adc_stby,                    // 接 ADC STBY：固定 1，正常工作
    output reg signed [31:0] current_mA,     // 所选通道换算电流，整数毫安；负值表示反向电流
    output reg signed [15:0] current_raw_code,// 所选通道原始 16 位码，与 current_mA 同帧发布
    output reg signed [15:0] vibration1_data,// IN2 振动 1 原始码，不是加速度物理量
    output reg signed [15:0] vibration2_data,// IN3 振动 2 原始码
    output reg signed [15:0] vibration3_data,// IN4 振动 3 原始码
    output reg data_valid,                   // 高 1 拍：四路输出同时更新，可整组取走
    output reg [63:0] sample_ticks,          // 与 CA/CB CONVST 同拍的时钟计数
    output reg adc_error                     // 超时/通道错位置 1，下一组正确数据清 0
);

    // 纳秒换算为时钟拍数：向上取整、64 位中间乘积，并保证至少等待 1 拍。
    function integer ns_cycles;
        input integer ns;
        reg [63:0] product;
        begin
            product = 64'd1 * CLOCK_HZ * ns;
            ns_cycles = (product + 64'd999_999_999) / 64'd1_000_000_000;
            if (ns_cycles < 1) ns_cycles = 1;
        end
    endfunction

    localparam integer IO_CYCLES = ns_cycles(100); // 复位/转换脉宽、RD 高低时间 100 ns
    localparam integer RESET_WAIT_CYCLES = ns_cycles(1000); // ADC 复位释放后等待 1 us
    localparam integer STARTUP_CYCLES = (POWERUP_CYCLES < 1) ? 1 : POWERUP_CYCLES;
    localparam integer TIMEOUT_CYCLES = (BUSY_TIMEOUT_CYCLES < 1) ? 1 : BUSY_TIMEOUT_CYCLES;
    localparam integer SAFE_SAMPLE_HZ = (SAMPLE_HZ < 1) ? 1 : SAMPLE_HZ;
    localparam integer PERIOD_CYCLES = (CLOCK_HZ / SAFE_SAMPLE_HZ) +
                                      ((CLOCK_HZ % SAFE_SAMPLE_HZ) != 0);
    // 保守周期下限：包含最长转换时间、同步开销、16 次读操作和采集恢复时间。
    // 该实现不重叠读操作与下一次转换，不能直接配置到芯片的极限 200 kSPS。
    localparam integer MIN_PERIOD_CYCLES = ns_cycles(4200) +
                                           34 * IO_CYCLES + 12 + ns_cycles(1000);
    // 电流[mA] = (ADC码 - 零电流码) × 量程[V] × 10^6 /
    //            (32768 × ACS712灵敏度[mV/A])。
    // 乘积和舍入保持 64 位精度，再逐拍整除，避免小电流归零和单拍长路径。
    localparam signed [63:0] CURRENT_MA_NUMERATOR =
        RANGE_10V ? 64'sd10_000_000 : 64'sd5_000_000;
    localparam integer SAFE_SENSITIVITY =
        (CURRENT_SENSITIVITY_MV_PER_A > 0) ? CURRENT_SENSITIVITY_MV_PER_A : 1;
    localparam signed [63:0] CURRENT_MA_DENOMINATOR =
        64'sd32_768 * SAFE_SENSITIVITY;
    localparam integer DIVIDEND_BITS = 48;
    localparam integer REM_BITS = $clog2(CURRENT_MA_DENOMINATOR);
    localparam [2:0] CONVERT_IDLE = 0, CONVERT_MULTIPLY = 1,
                     CONVERT_ROUND = 2, CONVERT_DIVIDE = 3,
                     CONVERT_DONE = 4;

    localparam [3:0] POWERUP = 0, RESET_HOLD = 1, RESET_WAIT = 2,
                     IDLE = 3, CONV_HIGH = 4, WAIT_BUSY_HIGH = 5,
                     WAIT_BUSY_LOW = 6, CS_SETUP = 7, READ_LOW = 8,
                     READ_HIGH = 9, PUBLISH = 10, FAULT = 11;
    reg [3:0] state;
    reg [31:0] timer;         // 当前状态的等待/超时计数器
    reg [31:0] period_count;  // 两次 CONVST 上升沿之间的采样周期计数器
    reg [2:0] channel;        // 当前读取的通道索引 0～7，对应 IN1～IN8
    reg byte_phase;           // 0=当前通道高字节，1=当前通道低字节（HBEN=1）
    reg [7:0] sample_msb;    // 上一次 RD 取得的高字节
    reg convst;              // 两组转换触发使用同一个寄存器，保证同时采样
    reg [63:0] tick_counter;
    reg busy_seen;           // 记录是否确实见过 BUSY=1，避免误判空闲为完成
    reg frame_bad;           // 当前帧的 FRSTDATA 是否异常
    reg signed [15:0] sample0, sample1, sample2, sample3; // 暂存，整帧成功后再输出
    reg [2:0] convert_phase;
    reg signed [16:0] current_delta_reg;
    reg signed [63:0] current_scaled_reg;
    reg [DIVIDEND_BITS-1:0] current_dividend_shift;
    reg [DIVIDEND_BITS-1:0] current_quotient_shift;
    reg [REM_BITS-1:0] current_remainder;
    reg [5:0] current_divide_count;
    reg current_negative;
    reg current_ready;
    reg signed [31:0] current_result;
    reg signed [15:0] current_raw_pending;
    wire [15:0] assembled_word = {sample_msb, adc_data};
    wire capture_current = (state == READ_LOW) && byte_phase &&
                           (timer >= IO_CYCLES - 1) &&
                           (channel == CURRENT_CHANNEL);
    wire [63:0] current_magnitude = current_scaled_reg[63] ?
        -current_scaled_reg : current_scaled_reg;
    wire [63:0] current_rounded_magnitude =
        current_magnitude + CURRENT_MA_DENOMINATOR / 2;
    wire [REM_BITS:0] current_rem_shift =
        {current_remainder, current_dividend_shift[DIVIDEND_BITS-1]};
    wire current_divide_bit =
        current_rem_shift >= CURRENT_MA_DENOMINATOR;
    wire [REM_BITS:0] current_rem_next = current_divide_bit ?
        current_rem_shift - CURRENT_MA_DENOMINATOR : current_rem_shift;
    (* ASYNC_REG = "TRUE" *) reg busy_meta, busy_sync;

    assign adc_convst_a = convst;
    assign adc_convst_b = convst;
    assign adc_os = 3'b000;
    assign adc_range = RANGE_10V;
    assign adc_serial = 1'b1;
    assign adc_stby = 1'b1; // ADC 持续工作，不受电机驱动器 STBY 的启停影响。

    // The first ADC word arrives well before the complete eight-word frame.
    // Perform exact signed rounding and one quotient bit per clock while the
    // remaining words are read. A short PUBLISH wait handles small IO_CYCLES.
    always @(posedge clk) begin
        if (!reset) begin
            convert_phase <= CONVERT_IDLE;
            current_delta_reg <= 17'sd0;
            current_scaled_reg <= 64'sd0;
            current_dividend_shift <= {DIVIDEND_BITS{1'b0}};
            current_quotient_shift <= {DIVIDEND_BITS{1'b0}};
            current_remainder <= {REM_BITS{1'b0}};
            current_divide_count <= 6'd0;
            current_negative <= 1'b0;
            current_ready <= 1'b0;
            current_result <= 32'sd0;
            current_raw_pending <= 16'sd0;
        end else if (capture_current) begin
            current_delta_reg <= $signed(assembled_word) - CURRENT_ZERO_CODE;
            current_raw_pending <= assembled_word;
            convert_phase <= CONVERT_MULTIPLY;
            current_ready <= 1'b0;
        end else begin
            case (convert_phase)
                CONVERT_MULTIPLY: begin
                    current_scaled_reg <=
                        current_delta_reg * CURRENT_MA_NUMERATOR;
                    convert_phase <= CONVERT_ROUND;
                end
                CONVERT_ROUND: begin
                    current_negative <= current_scaled_reg[63];
                    current_dividend_shift <=
                        current_rounded_magnitude[DIVIDEND_BITS-1:0];
                    current_quotient_shift <= {DIVIDEND_BITS{1'b0}};
                    current_remainder <= {REM_BITS{1'b0}};
                    current_divide_count <= DIVIDEND_BITS;
                    convert_phase <= CONVERT_DIVIDE;
                end
                CONVERT_DIVIDE: begin
                    current_remainder <= current_rem_next[REM_BITS-1:0];
                    current_dividend_shift <=
                        {current_dividend_shift[DIVIDEND_BITS-2:0], 1'b0};
                    current_quotient_shift <=
                        {current_quotient_shift[DIVIDEND_BITS-2:0],
                         current_divide_bit};
                    current_divide_count <= current_divide_count - 1'b1;
                    if (current_divide_count == 6'd1) begin
                        current_result <= current_negative ?
                            -$signed({current_quotient_shift[30:0],
                                      current_divide_bit}) :
                             $signed({current_quotient_shift[30:0],
                                      current_divide_bit});
                        current_ready <= 1'b1;
                        convert_phase <= CONVERT_DONE;
                    end
                end
                default: begin end
            endcase
        end
    end

    // BUSY 跨时钟域输入先经过两级触发器同步；同步链也采用低有效同步复位。
    always @(posedge clk) begin
        if (!reset) begin
            busy_meta <= 1'b0;
            busy_sync <= 1'b0;
        end else begin
            busy_meta <= adc_busy;
            busy_sync <= busy_meta;
        end
    end

    always @(posedge clk) begin
        if (!reset) begin
            state <= POWERUP;
            timer <= 0;
            period_count <= 0;
            channel <= 0;
            byte_phase <= 0;
            sample_msb <= 0;
            convst <= 0;
            tick_counter <= 0;
            sample_ticks <= 0;
            adc_reset <= 0;
            adc_cs_n <= 1;
            adc_rd_n <= 1;
            busy_seen <= 0;
            frame_bad <= 0;
            sample0 <= 0;
            sample1 <= 0;
            sample2 <= 0;
            sample3 <= 0;
            current_mA <= 0;
            current_raw_code <= 0;
            vibration1_data <= 0;
            vibration2_data <= 0;
            vibration3_data <= 0;
            data_valid <= 0; // 默认拉低，仅成功发布一帧时置高一个时钟周期。
            adc_error <= 0;
        end else begin
            tick_counter <= tick_counter + 64'd1;
            data_valid <= 0;
            if (period_count != 0) period_count <= period_count - 1'b1;

            case (state)
                POWERUP: begin // 等待供电与参考电压稳定；RST 保持低，之后再产生上升沿。
                    if (timer >= STARTUP_CYCLES - 1) begin
                        adc_reset <= 1;
                        timer <= 0;
                        state <= RESET_HOLD;
                    end else timer <= timer + 1'b1;
                end
                RESET_HOLD: begin // 上电或故障恢复时，保证 ADC 高有效复位脉宽。
                    if (timer >= IO_CYCLES - 1) begin
                        adc_reset <= 0;
                        timer <= 0;
                        state <= RESET_WAIT;
                    end else timer <= timer + 1'b1;
                end
                RESET_WAIT: begin // ADC 复位释放后等待，禁止立即启动转换。
                    if (timer >= RESET_WAIT_CYCLES - 1) begin
                        timer <= 0;
                        state <= IDLE;
                    end else timer <= timer + 1'b1;
                end
                IDLE: begin // 到达周期且 BUSY 空闲后，同时触发全部 8 个通道。
                    if (period_count == 0) begin
                        if (!busy_sync) begin
                            convst <= 1;
                            sample_ticks <= tick_counter;
                            period_count <= PERIOD_CYCLES - 1;
                            timer <= 0;
                            channel <= 0;
                            byte_phase <= 0;
                            busy_seen <= 0;
                            frame_bad <= 0;
                            state <= CONV_HIGH;
                        end else if (timer >= TIMEOUT_CYCLES - 1) begin
                            state <= FAULT;
                        end else timer <= timer + 1'b1;
                    end
                end
                CONV_HIGH: begin // 保持 CONVST 高电平，满足最小触发脉宽。
                    if (busy_sync) busy_seen <= 1;
                    if (timer >= IO_CYCLES - 1) begin
                        convst <= 0;
                        timer <= 0;
                        state <= WAIT_BUSY_HIGH;
                    end else timer <= timer + 1'b1;
                end
                WAIT_BUSY_HIGH: begin
                    // 必须先观察到 BUSY 拉高，不能把转换前的低电平当成完成。
                    if (busy_sync || busy_seen) begin
                        timer <= 0;
                        state <= WAIT_BUSY_LOW;
                    end else if (timer >= TIMEOUT_CYCLES - 1) begin
                        state <= FAULT;
                    end else timer <= timer + 1'b1;
                end
                WAIT_BUSY_LOW: begin // BUSY 回到低电平后，数据才能开始读出。
                    if (!busy_sync) begin
                        adc_cs_n <= 0;
                        timer <= 0;
                        state <= CS_SETUP;
                    end else if (timer >= TIMEOUT_CYCLES - 1) begin
                        state <= FAULT;
                    end else timer <= timer + 1'b1;
                end
                CS_SETUP: begin // CS 提前拉低，随后给出第一个 RD 下降沿。
                    if (timer >= IO_CYCLES - 1) begin
                        adc_rd_n <= 0;
                        timer <= 0;
                        state <= READ_LOW;
                    end else timer <= timer + 1'b1;
                end
                READ_LOW: begin
                    if (timer >= IO_CYCLES - 1) begin
                        // 在 RD 已低电平 100 ns、总线稳定后取数，然后才释放 RD。
                        // 并行数据不能逐位加同步器，否则可能把不同采样字拼在一起。
                        if (!byte_phase) sample_msb <= adc_data;
                        else begin
                            case (channel)
                                0: sample0 <= assembled_word;
                                1: sample1 <= assembled_word;
                                2: sample2 <= assembled_word;
                                3: sample3 <= assembled_word;
                                default: begin end // IN5～IN8 依次读完；所选电流通道另行换算。
                            endcase
                        end
                        if ((channel == 0 && !adc_first_data) ||
                            (channel != 0 && adc_first_data)) frame_bad <= 1;
                        adc_rd_n <= 1;
                        timer <= 0;
                        state <= READ_HIGH;
                    end else timer <= timer + 1'b1;
                end
                READ_HIGH: begin // 高/低字节各读一次，再切换至下一通道。
                    if (timer >= IO_CYCLES - 1) begin
                        timer <= 0;
                        if (!byte_phase) begin
                            byte_phase <= 1;
                            adc_rd_n <= 0;
                            state <= READ_LOW;
                        end else if (channel == 7) begin
                            adc_cs_n <= 1;
                            state <= PUBLISH;
                        end else begin
                            byte_phase <= 0;
                            channel <= channel + 1'b1;
                            adc_rd_n <= 0;
                            state <= READ_LOW;
                        end
                    end else timer <= timer + 1'b1;
                end
                PUBLISH: begin // 全部 8 通道读取且校验成功后，原子更新四路输出。
                    if (frame_bad) begin
                        state <= FAULT;
                    end else if (current_ready) begin
                        current_mA <= current_result;
                        current_raw_code <= current_raw_pending;
                        vibration1_data <= sample1;
                        vibration2_data <= sample2;
                        vibration3_data <= sample3;
                        data_valid <= 1;
                        adc_error <= 0;
                        state <= IDLE;
                    end
                end
                FAULT: begin
                    // 丢弃错误帧，保留上一次正确输出；复位 ADC 后自动重新采集。
                    // adc_error 持续为高，直到下一组完整正确数据发布或系统复位。
                    adc_error <= 1;
                    adc_reset <= 1;
                    adc_cs_n <= 1;
                    adc_rd_n <= 1;
                    convst <= 0;
                    timer <= 0;
                    period_count <= 0;
                    byte_phase <= 0;
                    state <= RESET_HOLD;
                end
                default: state <= FAULT;
            endcase
        end
    end

    // 仿真时拒绝不满足时序的参数组合，避免零周期/采样周期过短等隐蔽问题。
    // synthesis translate_off
    initial begin
        if (CLOCK_HZ <= 0 || SAMPLE_HZ <= 0 || SAMPLE_HZ > 200_000)
            $fatal(1, "data_collect: invalid CLOCK_HZ/SAMPLE_HZ");
        if (PERIOD_CYCLES < MIN_PERIOD_CYCLES)
            $fatal(1, "data_collect: sample period too short for read-after-conversion");
        if (TIMEOUT_CYCLES < ns_cycles(4200) + 4)
            $fatal(1, "data_collect: BUSY timeout must allow the full conversion");
        if (RANGE_10V != 0 && RANGE_10V != 1)
            $fatal(1, "data_collect: RANGE_10V must be 0 or 1");
        if (CURRENT_ZERO_CODE < -32768 || CURRENT_ZERO_CODE > 32767)
            $fatal(1, "data_collect: CURRENT_ZERO_CODE outside signed ADC range");
        if (CURRENT_SENSITIVITY_MV_PER_A <= 0)
            $fatal(1, "data_collect: current sensitivity must be positive");
        if (CURRENT_CHANNEL < 0 || CURRENT_CHANNEL > 7)
            $fatal(1, "data_collect: CURRENT_CHANNEL must be 0..7");
    end
    // synthesis translate_on
endmodule
