`timescale 1ns/1ps

// Register bank behind AXI_ERAM_Controller_0, at PS address 0x80000000.
// mem_addr is a WORD address; mem_csb and each mem_web byte lane are active low.
// Reads are registered, matching soc_prj/uisrc/01_rtl/system_top.v.
// All status inputs MUST be in this clk domain. No motor control is changed here.
module motor_status_regs #(
    // Read-only image capability marker. Bit 0 means the attached AD7606
    // data bus is 8-bit parallel-byte mode (two RD pulses per channel).
    parameter [31:0] FEATURE_FLAGS = 32'd0
) (
    input  wire        clk,
    input  wire        resetn,
    input  wire [9:0]  mem_addr,
    input  wire [3:0]  mem_web,
    input  wire        mem_csb,
    input  wire [31:0] mem_din,
    output reg  [31:0] mem_dout,

    input  wire [31:0] speed,
    input  wire signed [31:0] current_mA,
    input  wire signed [15:0] vibration1_data,
    input  wire signed [15:0] vibration2_data,
    input  wire signed [15:0] vibration3_data,
    input  wire        data_valid,
    input  wire        adc_error,
    input  wire        motor_fault,
    input  wire [2:0]  fault_code,
    input  wire        direction,
    input  wire        motor_stby,
    input  wire        motor_an1,
    input  wire        motor_an2,
    input  wire [31:0] motor_target,
    input  wire [1:0]  motor_ctrl,
    // 0x58 is only meaningful in feature-bit-4 motor-trial images.
    input  wire [31:0] trial_status
);
    reg [31:0] sample_count, sample_age, adc_error_count;
    reg        sample_seen, adc_error_seen, adc_error_d;
    reg [63:0] ticks;
    reg [31:0] latest_current;
    reg [15:0] latest_vib1, latest_vib2, latest_vib3;

    reg        snapshot_valid;
    reg [31:0] snapshot_seq, snap_flags, snap_speed, snap_current;
    reg [31:0] snap_vib1, snap_vib2, snap_vib3;
    reg [31:0] snap_sample_count, snap_sample_age, snap_error_count;
    reg [2:0]  snap_fault_code;
    reg [31:0] snap_target;
    reg [1:0]  snap_ctrl;
    reg [63:0] snap_ticks;

    wire capture = !mem_csb && !mem_web[0] &&
                   (mem_addr == 10'h002) && mem_din[0]; // byte offset 0x08
    wire error_rise = adc_error && !adc_error_d;
    wire [31:0] count_now = sample_count + (data_valid ? 32'd1 : 32'd0);
    wire [31:0] age_now = data_valid ? 32'd0 :
                         (&sample_age ? sample_age : sample_age + 32'd1);
    wire [31:0] errors_now = (error_rise && !(&adc_error_count)) ?
                            adc_error_count + 32'd1 : adc_error_count;
    wire [31:0] flags_now = {23'd0, motor_an2, motor_an1, motor_stby,
                            direction, motor_fault, (adc_error_seen | adc_error),
                            adc_error, (sample_seen | data_valid), snapshot_valid};
    wire [15:0] vib1_now = data_valid ? vibration1_data : latest_vib1;
    wire [15:0] vib2_now = data_valid ? vibration2_data : latest_vib2;
    wire [15:0] vib3_now = data_valid ? vibration3_data : latest_vib3;

    always @(posedge clk) begin
        if (!resetn) begin
            sample_count <= 0;
            sample_age <= 32'hffff_ffff; // No successful sample yet.
            adc_error_count <= 0;
            sample_seen <= 0;
            adc_error_seen <= 0;
            adc_error_d <= 0;
            ticks <= 0;
            latest_current <= 0;
            latest_vib1 <= 0;
            latest_vib2 <= 0;
            latest_vib3 <= 0;
            snapshot_valid <= 0;
            snapshot_seq <= 0;
            snap_flags <= 0;
            snap_speed <= 0;
            snap_current <= 0;
            snap_vib1 <= 0;
            snap_vib2 <= 0;
            snap_vib3 <= 0;
            snap_sample_count <= 0;
            snap_sample_age <= 0;
            snap_error_count <= 0;
            snap_fault_code <= 0;
            snap_target <= 0;
            snap_ctrl <= 0;
            snap_ticks <= 0;
        end else begin
            ticks <= ticks + 64'd1;
            sample_count <= count_now;
            sample_age <= age_now;
            adc_error_count <= errors_now;
            adc_error_d <= adc_error;
            adc_error_seen <= adc_error_seen | adc_error;
            if (data_valid) begin
                sample_seen <= 1;
                latest_current <= current_mA;
                latest_vib1 <= vibration1_data;
                latest_vib2 <= vibration2_data;
                latest_vib3 <= vibration3_data;
            end

            if (capture) begin
                snapshot_valid <= 1;
                snapshot_seq <= snapshot_seq + 32'd1;
                snap_flags <= flags_now | 32'd1;
                snap_speed <= speed;
                // A frame arriving on the capture edge belongs to this snapshot.
                snap_current <= data_valid ? current_mA : latest_current;
                snap_vib1 <= {{16{vib1_now[15]}}, vib1_now};
                snap_vib2 <= {{16{vib2_now[15]}}, vib2_now};
                snap_vib3 <= {{16{vib3_now[15]}}, vib3_now};
                snap_sample_count <= count_now;
                snap_sample_age <= age_now;
                snap_error_count <= errors_now;
                snap_fault_code <= fault_code;
                snap_target <= motor_target;
                snap_ctrl <= motor_ctrl;
                snap_ticks <= ticks;
            end
        end
    end

    // A read request produces its data after this rising edge. Hold otherwise.
    // Writes to RO/reserved registers are ignored; the AXI bridge returns OKAY.
    always @(posedge clk) begin
        if (!resetn)
            mem_dout <= 0;
        else if (!mem_csb && (&mem_web)) begin
            case (mem_addr)
                10'h000: mem_dout <= 32'h4d53_5431; // "MST1"
                10'h001: mem_dout <= 32'h0001_0000; // ABI 1.0
                10'h002: mem_dout <= 0;            // Snapshot command (WO)
                10'h003: mem_dout <= snapshot_seq;
                10'h004: mem_dout <= snap_flags;
                10'h005: mem_dout <= snap_speed;
                10'h006: mem_dout <= snap_current;
                10'h007: mem_dout <= snap_vib1;
                10'h008: mem_dout <= snap_vib2;
                10'h009: mem_dout <= snap_vib3;
                10'h00a: mem_dout <= snap_sample_count;
                10'h00b: mem_dout <= snap_sample_age;
                10'h00c: mem_dout <= {29'd0, snap_fault_code};
                10'h00d: mem_dout <= snap_target;
                10'h00e: mem_dout <= {30'd0, snap_ctrl};
                10'h00f: mem_dout <= snap_error_count;
                10'h010: mem_dout <= snap_ticks[31:0];
                10'h011: mem_dout <= snap_ticks[63:32];
                10'h012: mem_dout <= flags_now;     // Live, not frozen
                10'h013: mem_dout <= count_now;     // Live, not frozen
                10'h014: mem_dout <= {29'd0, fault_code}; // Live
                10'h015: mem_dout <= FEATURE_FLAGS; // 0x54, image capabilities
                10'h016: mem_dout <= trial_status; // 0x58, trial interlock
                10'h017: mem_dout <= errors_now; // 0x5c, live ADC error count
                default: mem_dout <= 0;
            endcase
        end
    end
endmodule
