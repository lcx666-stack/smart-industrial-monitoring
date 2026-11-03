`timescale 1ns/1ps

// Continuous-drive arming and fail-stop block in reserved ERAM offsets 0x100+.
// No reset, heartbeat, GPIO value or fault clearance can implicitly arm it.
module motor_run_guard #(
    parameter integer CLOCK_HZ = 100_000_000,
    parameter integer MAX_ADC_AGE_CYCLES = 100_000,
    parameter integer PL_COUNTS_PER_REV = 40_000,
    parameter integer REQUIRE_ENCODER_READY = 0
) (
    input wire clk, resetn,
    input wire [9:0] mem_addr,
    input wire [3:0] mem_web,
    input wire mem_csb,
    input wire [31:0] mem_din,
    output reg [31:0] mem_dout,
    input wire data_valid, adc_error, core_fault,
    input wire encoder_ready,
    input wire signed [31:0] current_mA,
    input wire [1:0] motor_ctrl,
    input wire [31:0] motor_target,
    output wire drive_permit,
    output wire guard_fault
);
    localparam integer MS_CYCLES = CLOCK_HZ / 1000;
    localparam [31:0] ARM = 32'h4152_4d31; // ARM1
    localparam [31:0] STOP = 32'h5354_4f50;
    localparam [31:0] CLEAR = 32'h434c_5231;
    localparam [31:0] ESTOP = 32'h4553_5450;
    reg enabled, sample_seen;
    reg [3:0] configured;
    reg signed [31:0] current_zero, latest_current;
    reg [31:0] current_limit, watchdog_ms, run_limit_ms;
    reg [31:0] heartbeat_token, heartbeat_age, run_age, sample_age, ms_phase;
    reg [7:0] faults;
    wire full_write = !mem_csb && (mem_web == 4'b0000);
    wire tick_ms = (ms_phase == MS_CYCLES - 1);
    wire refresh = full_write && (mem_addr == 10'h043) &&
                   (mem_din != heartbeat_token) && (mem_din != 0);
    wire signed [31:0] current_now = data_valid ? current_mA : latest_current;
    wire signed [32:0] delta = {current_now[31], current_now} -
                               {current_zero[31], current_zero};
    wire signed [32:0] limit_signed = {1'b0, current_limit};
    wire overcurrent = (delta >= limit_signed) || (delta <= -limit_signed);
    wire [31:0] age_now = data_valid ? 32'd0 : sample_age;
    wire fresh = (sample_seen || data_valid) &&
                 (age_now < MAX_ADC_AGE_CYCLES) && !adc_error;
    wire config_ok = (&configured) && (current_limit > 0) &&
                     !current_limit[31] && (watchdog_ms >= 10) &&
                     (watchdog_ms <= 1000) && (run_limit_ms > 0) &&
                     (run_limit_ms <= 3_600_100);
    wire neutral = (motor_ctrl == 0) && (motor_target == 0);
    wire arm_ok = !enabled && (faults == 0) && neutral && config_ok &&
                  fresh && !core_fault && !overcurrent &&
                  (!REQUIRE_ENCODER_READY || encoder_ready);
    wire [7:0] trip = {1'b0, motor_ctrl == 2'b11,
                      tick_ms && (run_age >= run_limit_ms - 1),
                      tick_ms && !refresh && (heartbeat_age >= watchdog_ms - 1),
                      core_fault, overcurrent, !fresh, adc_error};
    assign drive_permit = enabled && (faults == 0) && !core_fault;
    assign guard_fault = |faults;

    // synthesis translate_off
    initial begin
        if (CLOCK_HZ < 1000 || (CLOCK_HZ % 1000) != 0)
            $fatal(1, "motor_run_guard: CLOCK_HZ must be a positive multiple of 1000");
        if (MAX_ADC_AGE_CYCLES <= 0 || PL_COUNTS_PER_REV <= 0)
            $fatal(1, "motor_run_guard: invalid ADC age or encoder scale");
    end
    // synthesis translate_on

    always @(posedge clk) begin
        if (!resetn) begin
            enabled <= 0; sample_seen <= 0; configured <= 0;
            current_zero <= 0; latest_current <= 0; current_limit <= 0;
            watchdog_ms <= 0; run_limit_ms <= 0;
            heartbeat_token <= 0; heartbeat_age <= 0; run_age <= 0;
            sample_age <= 32'hffff_ffff; ms_phase <= 0; faults <= 0;
        end else begin
            ms_phase <= tick_ms ? 0 : ms_phase + 1;
            if (data_valid) begin
                sample_seen <= 1;
                latest_current <= current_mA;
                sample_age <= 0;
            end else if (!(&sample_age)) sample_age <= sample_age + 1;
            if (enabled) begin
                if (tick_ms) begin
                    if (!(&heartbeat_age)) heartbeat_age <= heartbeat_age + 1;
                    if (!(&run_age)) run_age <= run_age + 1;
                end
                if (refresh) begin
                    heartbeat_token <= mem_din;
                    heartbeat_age <= 0;
                end
                if (|trip) begin
                    faults <= faults | trip;
                    enabled <= 0;
                end
            end
            if (full_write) begin
                case (mem_addr)
                    10'h042: begin
                        if (mem_din == ESTOP) begin
                            enabled <= 0;
                            faults <= faults | (enabled ? trip : 8'd0) | 8'h80;
                        end else if (mem_din == STOP) enabled <= 0;
                        else if (mem_din == ARM && arm_ok) begin
                            enabled <= 1;
                            heartbeat_age <= 0; run_age <= 0;
                        end else if (mem_din == CLEAR && !enabled && neutral &&
                                     fresh && !core_fault && (!config_ok || !overcurrent))
                            faults <= 0;
                    end
                    10'h044: if (!enabled) begin
                        current_zero <= mem_din; configured[0] <= 1;
                    end
                    10'h045: if (!enabled) begin
                        current_limit <= mem_din; configured[1] <= 1;
                    end
                    10'h046: if (!enabled) begin
                        watchdog_ms <= mem_din; configured[2] <= 1;
                    end
                    10'h047: if (!enabled) begin
                        run_limit_ms <= mem_din; configured[3] <= 1;
                    end
                    default: begin end
                endcase
            end
        end
    end

    always @(posedge clk) begin
        if (!resetn) mem_dout <= 0;
        else if (!mem_csb && (&mem_web)) begin
            case (mem_addr)
                10'h040: mem_dout <= 32'h4d47_5231; // MGR1
                10'h041: mem_dout <= 32'h0001_0000;
                10'h042: mem_dout <= 0;
                10'h043: mem_dout <= heartbeat_token;
                10'h044: mem_dout <= current_zero;
                10'h045: mem_dout <= current_limit;
                10'h046: mem_dout <= watchdog_ms;
                10'h047: mem_dout <= run_limit_ms;
                10'h048: mem_dout <= {25'd0, configured, fresh, guard_fault, enabled};
                10'h049: mem_dout <= {24'd0, faults};
                10'h04a: mem_dout <= age_now;
                10'h04b: mem_dout <= heartbeat_age;
                10'h04c: mem_dout <= PL_COUNTS_PER_REV;
                10'h04d: mem_dout <= CLOCK_HZ;
                10'h04e: mem_dout <= run_age;
                default: mem_dout <= 0;
            endcase
        end
    end
endmodule
