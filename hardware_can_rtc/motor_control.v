`timescale 1ns/1ps
//启动通电后 2 秒无合法反馈、运行中 0.5 秒无合法反馈时触发保护。
//故障将锁存并关闭驱动输出，需要系统复位后才能恢复，避免反馈恢复时自行重启
module motor (
    clk,
    reset,
    ctrl,
    Target,//目标转速
    encoder_a,
    encoder_b,
    direction,
    pwm,
    AN1,
    AN2,
    STBY,
    speed,
    adc_data,
    adc_busy,
    adc_first_data,
    adc_reset,
    adc_convst_a,
    adc_convst_b,
    adc_cs_n,
    adc_rd_n,
    adc_os,
    adc_range,
    adc_serial,
    adc_stby,
    current_mA,
    current_raw_code,
    vibration1_data,
    vibration2_data,
    vibration3_data,
    data_valid,
    sample_ticks,
    adc_error,
    motor_fault,
    fault_code,
    qualified_ready, raw_activity,
    encoder_step_event, encoder_invalid_event, debug_duty
);

input clk,reset,encoder_a,encoder_b;
input qualified_ready, raw_activity; // only used by opt-in qualified input path
output wire encoder_step_event, encoder_invalid_event;
output wire [6:0] debug_duty;
parameter integer ENCODER_INPUT_QUALIFIED = 0;
parameter integer IMMEDIATE_START = 0;
input [1:0] ctrl;       // 来自同一 clk 域的 AXI 寄存器：00 空转、01 正转、10 反转、11 制动
input [31:0] Target;    // 无符号 Q16.16，单位为输出轴转/秒；0 表示不再驱动
output [31:0] speed;
output direction;
output wire pwm;
output reg  AN1,AN2,STBY;
output wire motor_fault;       // 故障锁存总标志；为 1 时切断驱动，不自动重启
output reg [2:0] fault_code;   // bit0 编码器非法跳变；bit1 启动无反馈；bit2 运行失反馈

// 100 MHz 下默认启动宽限 2 s、运行反馈间隔上限 0.5 s。
// 尚未实测电机，这些参数不是已验证的热/电流安全时间，应按负载和最低转速调整。
parameter integer STARTUP_TIMEOUT_CYCLES = 200_000_000;
parameter integer FEEDBACK_TIMEOUT_CYCLES = 50_000_000;
localparam integer STARTUP_LIMIT = (STARTUP_TIMEOUT_CYCLES < 1) ? 1 : STARTUP_TIMEOUT_CYCLES;
localparam integer FEEDBACK_LIMIT = (FEEDBACK_TIMEOUT_CYCLES < 1) ? 1 : FEEDBACK_TIMEOUT_CYCLES;

// AD7606 采集接口，与上面的 TB6612 电机驱动接口独立。
// 顶层 reset 和采集模块均为低电平有效、时钟上升沿同步复位。
input [7:0] adc_data;              // 接 AD7606 DB7～DB0，字节并口输入
input adc_busy;                    // 接 BUSY，转换中为高
input adc_first_data;              // 接 FDA，第一通道数据标志
output adc_reset;                  // 接 RST，ADC 芯片要求高有效硬件复位
output adc_convst_a, adc_convst_b;  // 接 CA/CB，同步触发八通道转换
output adc_cs_n, adc_rd_n;          // 接 CS/RD，均低有效
output [2:0] adc_os;                // 接 OS2～OS0，固定 000
output adc_range;                  // 接 RANGE，默认 0：±5 V
output adc_serial;                 // 接 SER，固定 1：DB15=1 时字节并口模式
output adc_stby;                   // 接 ADC STBY，固定 1；不要与电机 STBY 混接
output signed [31:0] current_mA;    // 选定的 ADC 通道：有符号整数毫安，按 ACS712-5A 标称灵敏度换算
output signed [15:0] current_raw_code;
output signed [15:0] vibration1_data, vibration2_data, vibration3_data; // IN2～IN4
output data_valid;                 // 四路输出同时更新时拉高一个时钟周期
output [63:0] sample_ticks;
output adc_error;                  // 采集异常标志，下一组正确数据到来后清除
parameter integer ADC_CLOCK_HZ = 100_000_000; // 必须与输入 clk 的实际频率相同
parameter integer ADC_SAMPLE_HZ = 50_000;    // 默认每通道每秒采样 50000 次
parameter ADC_RANGE_10V = 1'b0;             // 0：±5 V；1：±10 V
parameter integer ADC_CURRENT_ZERO_CODE = ADC_RANGE_10V ? 8_192 : 16_384;
parameter integer ADC_CURRENT_SENSITIVITY_MV_PER_A = 185;
parameter integer ADC_CURRENT_CHANNEL = 0; // 0=IN1, 4=IN5; motor_soc_top explicitly selects IN5

parameter F = 4'b0001, B = 4'b0010, STOP = 4'b0100, FREE = 4'b1000;
reg [3:0] state,next_state ;
wire speed_valid;
wire [6:0] duty ;
wire pwm_wave;
wire encoder_stopped;
wire encoder_activity, encoder_step, encoder_invalid;
assign encoder_step_event = encoder_step;
assign encoder_invalid_event = encoder_invalid;
assign debug_duty = duty;
wire drive_enable    = ((state == F) || (state == B)) && !motor_fault;
wire drive_direction = (state == F) ? 1'b1 : 1'b0;
// 停止历史标志必须同时排除当前已同步的任意 A/B 变化，避免同拍运动仍放行。
wire safe_to_start = encoder_stopped && !encoder_activity && !motor_fault;
wire requested_direction_matches = ((ctrl == 2'b01) && (state == F)) ||
                                   ((ctrl == 2'b10) && (state == B));
wire watchdog_enable = drive_enable && requested_direction_matches &&
                       (Target != 0) && (duty != 0);
reg [31:0] feedback_counter;
reg feedback_seen;

assign motor_fault = |fault_code;
// 正常 STOP 短路制动；故障则关闭 STBY 和 PWM，避免继续给堵转电机通电。
// 故障屏蔽直接作用于输出，不等待 speed_valid 或 PWM 计数器走完一周期。
assign pwm = motor_fault ? 1'b0 : ((state == STOP) ? 1'b1 :
                                 (drive_enable ? pwm_wave : 1'b0));

always @(posedge clk) begin
    if (!reset) begin
        fault_code <= 3'b000;
        feedback_counter <= 0;
        feedback_seen <= 0;
    end else begin
        // 非法跳变也代表输入在变化：不能作为停转依据，立即锁存接口故障。
        if (encoder_invalid) fault_code[0] <= 1'b1;

        // 启动计时从非零占空比开始，而不是从 PS 提交命令开始。
        // 正常停机、目标为 0 和换向减速期间不做无反馈判故障。
        if (!watchdog_enable || motor_fault) begin
            feedback_counter <= 0;
            feedback_seen <= 0;
        end else if (encoder_step) begin
            // 当前边沿优先于超时：恰好在截止拍收到有效边沿不应误报。
            feedback_counter <= 0;
            feedback_seen <= 1;
        end else if (!feedback_seen) begin
            if (feedback_counter >= STARTUP_LIMIT - 1)
                fault_code[1] <= 1'b1;
            else
                feedback_counter <= feedback_counter + 1'b1;
        end else begin
            if (feedback_counter >= FEEDBACK_LIMIT - 1)
                fault_code[2] <= 1'b1;
            else
                feedback_counter <= feedback_counter + 1'b1;
        end
        // 无自动清除分支：故障只能由系统低有效同步复位清除。
    end
end

always @(posedge clk) begin
    if (!reset || motor_fault) begin
        state<=FREE;
    end
    else    
        state<=next_state;
end

//ctrl: 10_反转、00_空转、11_刹停、01_正转
// 安全换向：保持当前桥臂方向并逐步减小 PWM，归零后进入制动。
// 等待测速模块连续无任何 A/B 变化达到停止超时，再允许切换方向。
always @(*) begin
    next_state = state;
    case (state)
        FREE: begin
            if (ctrl == 2'b01)
                next_state = safe_to_start ? F : STOP;
            else if (ctrl == 2'b10)
                next_state = safe_to_start ? B : STOP;
            else if (ctrl == 2'b11)
                next_state = STOP;
            else
                next_state = FREE;
        end
        F: begin
            if (ctrl == 2'b00)
                next_state = FREE;
            else if (ctrl == 2'b11)
                next_state = STOP;
            else if (ctrl == 2'b10)
                next_state = (duty == 7'd0) ? STOP : F;
            else
                next_state = F;
        end
        B: begin
            if (ctrl == 2'b00)
                next_state = FREE;
            else if (ctrl == 2'b11)
                next_state = STOP;
            else if (ctrl == 2'b01)
                next_state = (duty == 7'd0) ? STOP : B;
            else
                next_state = B;
        end
        STOP: begin
            if (ctrl == 2'b00)
                next_state = FREE;
            else if ((ctrl == 2'b01) && safe_to_start)
                next_state = F;
            else if ((ctrl == 2'b10) && safe_to_start)
                next_state = B;
            else
                next_state = STOP;
        end
        default: next_state = FREE;
    endcase
end
always @(*) begin
    if (motor_fault) begin
        // 故障采用禁用输出/滑行策略，不承诺故障后立即机械停止。
        STBY=1'b0;
        AN1=1'b0;
        AN2=1'b0;
    end else case (state)
        FREE:begin//空转
            STBY=1'b0;
            AN1=1'b0;
            AN2=1'b0;
        end
        F: begin//正转
            STBY=1'b1;
            AN1=1'b1;
            AN2=1'b0;
        end
        B:begin//反转
            STBY=1'b1;
            AN1=1'b0;
            AN2=1'b1;
        end
        STOP:begin//主动刹停
            STBY=1'b1;
            AN1=1'b1;
            AN2=1'b1;
        end
        default: begin
            STBY=1'b0;
            AN1=1'b0;
            AN2=1'b0;
        end
    endcase
end

PWM PWM (
    .clk(clk),
    .reset(reset),
    .duty(duty),
    .pwm(pwm_wave)
);

rotate_speed #(.INPUT_IS_QUALIFIED(ENCODER_INPUT_QUALIFIED)) rotate_speed  (
            .clk(clk),
            .rst_n(reset),
            .encoder_a(encoder_a),
            .encoder_b(encoder_b),
            .qualified_ready(qualified_ready), .raw_activity(raw_activity),
            .speed(speed),
            .direction(direction),
            .speed_valid(speed_valid),
            .encoder_stopped(encoder_stopped),
            .encoder_activity(encoder_activity),
            .encoder_step(encoder_step),
            .encoder_invalid(encoder_invalid)
);

speed_control #(.IMMEDIATE_START(IMMEDIATE_START)) speed_control (
            .clk(clk),
            .rst_n(reset),
            .speed_valid(speed_valid),
            .target_speed(Target),
            .actual_speed(speed),
            .drive_enable(drive_enable),
            .drive_direction(drive_direction),
            .ctrl(ctrl),
            .duty(duty)
);
    
// 电流和三路振动持续采集；电机处于空转、刹停、正转或反转时均不停止采集。
data_collect #(
    .CLOCK_HZ(ADC_CLOCK_HZ),
    .SAMPLE_HZ(ADC_SAMPLE_HZ),
    .RANGE_10V(ADC_RANGE_10V),
    .CURRENT_ZERO_CODE(ADC_CURRENT_ZERO_CODE),
    .CURRENT_SENSITIVITY_MV_PER_A(ADC_CURRENT_SENSITIVITY_MV_PER_A),
    .CURRENT_CHANNEL(ADC_CURRENT_CHANNEL)
) data_collect_u (
    .clk(clk),
    .reset(reset),
    .adc_data(adc_data),
    .adc_busy(adc_busy),
    .adc_first_data(adc_first_data),
    .adc_reset(adc_reset),
    .adc_convst_a(adc_convst_a),
    .adc_convst_b(adc_convst_b),
    .adc_cs_n(adc_cs_n),
    .adc_rd_n(adc_rd_n),
    .adc_os(adc_os),
    .adc_range(adc_range),
    .adc_serial(adc_serial),
    .adc_stby(adc_stby),
    .current_mA(current_mA),
    .current_raw_code(current_raw_code),
    .vibration1_data(vibration1_data),
    .vibration2_data(vibration2_data),
    .vibration3_data(vibration3_data),
    .data_valid(data_valid),
    .sample_ticks(sample_ticks),
    .adc_error(adc_error)
);

// 仿真时拒绝非法保护阈值；不能用 0 隐式禁用安全保护。
// synthesis translate_off
initial begin
    if (STARTUP_TIMEOUT_CYCLES <= 0 || FEEDBACK_TIMEOUT_CYCLES <= 0)
        $fatal(1, "motor: protection timeouts must be positive");
end
// synthesis translate_on

endmodule
