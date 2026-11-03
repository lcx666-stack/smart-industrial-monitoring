`timescale 1ns/1ps

// One-shot, short-duration bench trial interlock. It cannot compensate for
// miswired current sensing, an over-voltage motor supply, or 5 V FPGA inputs.
module motor_trial_guard #(
    parameter integer CLOCK_HZ = 100_000_000,
    parameter integer TRIAL_CYCLES = 50_000_000, // 0.5 s, one trial per boot
    parameter integer SAMPLE_TIMEOUT_CYCLES = 10_000, // 100 us
    parameter integer PWM_PERIOD_CYCLES = 100_000, // 1 ms
    parameter integer PWM_ON_CYCLES = 20_000, // at most 20% of each 1 ms
    parameter integer CURRENT_SENSE_ENABLED = 1,
    parameter integer OVERCURRENT_MA = 1_500,
    parameter integer ARM_ZERO_MA = 250
) (
    input  wire clk,
    input  wire resetn,
    input  wire [9:0] mem_addr,
    input  wire [3:0] mem_web,
    input  wire mem_csb,
    input  wire [31:0] mem_din,
    input  wire [31:0] motor_target,
    input  wire [1:0] motor_ctrl,
    input  wire signed [31:0] current_mA,
    input  wire data_valid,
    input  wire adc_error,
    input  wire core_fault,
    input  wire core_ain1,
    input  wire core_ain2,
    input  wire core_stby,
    output wire motor_pwma,
    output wire motor_ain1,
    output wire motor_ain2,
    output wire motor_stby,
    output wire [31:0] status_word
);
    localparam [31:0] ARM_MAGIC = 32'h5341_4645; // "SAFE"
    localparam [31:0] MAX_TARGET_Q16 = 32'd655_360; // 10 rev/s

    reg armed;
    reg used;
    reg [3:0] faults;
    reg [31:0] trial_count;
    reg [31:0] sample_age;
    reg [16:0] pwm_phase;
    reg [6:0] good_frames;

    wire arm_write = !mem_csb && !mem_web[0] && mem_addr == 10'h016 &&
                     mem_din == ARM_MAGIC;
    wire stop_write = !mem_csb && !mem_web[0] && mem_addr == 10'h016 &&
                      mem_din == 32'd0;
    // The open-loop bench image has IN5 in the encoder 5 V lead, not in the
    // motor lead. Never use that reading as a motor-current interlock.
    wire overcurrent = CURRENT_SENSE_ENABLED &&
                       ((current_mA >= OVERCURRENT_MA) ||
                        (current_mA <= -OVERCURRENT_MA));
    wire near_zero = !CURRENT_SENSE_ENABLED ||
                     ((current_mA < ARM_ZERO_MA) &&
                      (current_mA > -ARM_ZERO_MA));
    wire target_ok = motor_target != 32'd0 &&
                     motor_target <= MAX_TARGET_Q16;
    wire command_ok = (motor_ctrl == 2'b01 || motor_ctrl == 2'b10) && target_ok;
    wire sample_stale = sample_age >= SAMPLE_TIMEOUT_CYCLES;
    wire trip_now = overcurrent || adc_error || sample_stale || core_fault ||
                    !command_ok || (trial_count >= TRIAL_CYCLES);
    wire drive_allowed = resetn && armed && !trip_now;
    wire directional_drive = core_stby && (core_ain1 ^ core_ain2);

    // Fixed low-duty open-loop pulse for the short trial. The normal speed
    // controller waits one second for its first speed window, so its PWM
    // cannot be used for a half-second bench pulse.
    assign motor_stby = drive_allowed && directional_drive;
    assign motor_ain1 = drive_allowed && directional_drive && core_ain1;
    assign motor_ain2 = drive_allowed && directional_drive && core_ain2;
    assign motor_pwma = drive_allowed && directional_drive &&
                        (pwm_phase < PWM_ON_CYCLES);
    // bit0 armed, bit1 one-shot used; bits2..5 latch overcurrent, ADC/stale,
    // core fault, and command/timeout faults. No software write clears faults.
    assign status_word = {26'd0, faults, used, armed};

    always @(posedge clk) begin
        if (!resetn) begin
            armed <= 1'b0;
            used <= 1'b0;
            faults <= 4'b0000;
            trial_count <= 32'd0;
            sample_age <= SAMPLE_TIMEOUT_CYCLES;
            pwm_phase <= 17'd0;
            good_frames <= 7'd0;
        end else begin
            if (data_valid)
                sample_age <= 32'd0;
            else if (sample_age < SAMPLE_TIMEOUT_CYCLES)
                sample_age <= sample_age + 32'd1;

            if (adc_error)
                good_frames <= 7'd0;
            else if (data_valid && good_frames < 7'd100)
                good_frames <= good_frames + 7'd1;

            if (stop_write)
                armed <= 1'b0;

            if (armed) begin
                if (pwm_phase == PWM_PERIOD_CYCLES - 1)
                    pwm_phase <= 17'd0;
                else
                    pwm_phase <= pwm_phase + 17'd1;
                if (trial_count < TRIAL_CYCLES)
                    trial_count <= trial_count + 32'd1;
                if (trip_now) begin
                    armed <= 1'b0;
                    faults[0] <= faults[0] || overcurrent;
                    faults[1] <= faults[1] || adc_error || sample_stale;
                    faults[2] <= faults[2] || core_fault;
                    faults[3] <= faults[3] || !command_ok ||
                                 (trial_count >= TRIAL_CYCLES);
                end
            end else if (arm_write && !used && faults == 4'b0000 &&
                         good_frames >= 7'd100 && !adc_error &&
                         !sample_stale && near_zero && !core_fault &&
                         command_ok) begin
                armed <= 1'b1;
                used <= 1'b1;
                trial_count <= 32'd0;
                pwm_phase <= 17'd0;
            end
        end
    end

    // synthesis translate_off
    initial begin
        if (CLOCK_HZ <= 0 || TRIAL_CYCLES <= 0 ||
            SAMPLE_TIMEOUT_CYCLES <= 0 ||
            PWM_PERIOD_CYCLES <= 0 || PWM_ON_CYCLES <= 0 ||
            PWM_ON_CYCLES > PWM_PERIOD_CYCLES ||
            PWM_PERIOD_CYCLES > 131_072 ||
            OVERCURRENT_MA <= ARM_ZERO_MA || ARM_ZERO_MA <= 0 ||
            (CURRENT_SENSE_ENABLED != 0 && CURRENT_SENSE_ENABLED != 1))
            $fatal(1, "motor_trial_guard: invalid safety parameter");
    end
    // synthesis translate_on
endmodule
