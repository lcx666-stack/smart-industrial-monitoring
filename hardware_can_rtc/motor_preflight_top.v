`timescale 1ns/1ps

// Preflight image only: ADC and encoder inputs can be observed, but all four
// TB6612 control pins are permanently low. This module has no motor controller.
module motor_preflight_top (
    input  wire        encoder_a,
    input  wire        encoder_b,
    output wire        motor_pwma,
    output wire        motor_ain1,
    output wire        motor_ain2,
    output wire        motor_stby,
    input  wire [7:0]  adc_data,
    input  wire        adc_busy,
    input  wire        adc_first_data,
    output wire        adc_reset,
    output wire        adc_convst_a,
    output wire        adc_convst_b,
    output wire        adc_cs_n,
    output wire        adc_rd_n
);
    assign motor_pwma = 1'b0;
    assign motor_ain1 = 1'b0;
    assign motor_ain2 = 1'b0;
    assign motor_stby = 1'b0;

    wire clk;
    wire resetn;
    wire [31:0] target_unused;
    wire [1:0] ctrl_unused;
    wire [9:0] status_addr;
    wire [3:0] status_web;
    wire status_csb;
    wire [31:0] status_wdata;
    wire [31:0] status_rdata;
    wire [2:0] adc_os_unused;
    wire adc_range_unused, adc_serial_unused, adc_stby_unused;
    wire signed [31:0] current_ma;
    wire signed [15:0] current_raw;
    wire signed [15:0] vibration1, vibration2, vibration3;
    wire data_valid, adc_error;

    system u_system (
        .motor_target (target_unused),
        .motor_ctrl   (ctrl_unused),
        .motor_clk    (clk),
        .motor_resetn (resetn),
        .status_addr  (status_addr),
        .status_web   (status_web),
        .status_csb   (status_csb),
        .status_wdata (status_wdata),
        .status_rdata (status_rdata)
    );

    data_collect #(
        .CLOCK_HZ(100_000_000),
        .SAMPLE_HZ(50_000),
        .RANGE_10V(1'b0),
        .CURRENT_CHANNEL(4)
    ) u_adc (
        .clk             (clk),
        .reset           (resetn),
        .adc_data        (adc_data),
        .adc_busy        (adc_busy),
        .adc_first_data  (adc_first_data),
        .adc_reset       (adc_reset),
        .adc_convst_a    (adc_convst_a),
        .adc_convst_b    (adc_convst_b),
        .adc_cs_n        (adc_cs_n),
        .adc_rd_n        (adc_rd_n),
        .adc_os          (adc_os_unused),
        .adc_range       (adc_range_unused),
        .adc_serial      (adc_serial_unused),
        .adc_stby        (adc_stby_unused),
        .current_mA      (current_ma),
        .current_raw_code(current_raw),
        .vibration1_data (vibration1),
        .vibration2_data (vibration2),
        .vibration3_data (vibration3),
        .data_valid      (data_valid),
        .adc_error       (adc_error)
    );

    // Synchronize both asynchronous encoder lines before any status logic.
    reg [1:0] encoder_a_sync, encoder_b_sync;
    reg encoder_a_prev, encoder_b_prev;
    reg [15:0] encoder_a_rises, encoder_b_rises;
    always @(posedge clk) begin
        if (!resetn) begin
            encoder_a_sync <= 2'b00;
            encoder_b_sync <= 2'b00;
            encoder_a_prev <= 1'b0;
            encoder_b_prev <= 1'b0;
            encoder_a_rises <= 16'd0;
            encoder_b_rises <= 16'd0;
        end else begin
            encoder_a_sync <= {encoder_a_sync[0], encoder_a};
            encoder_b_sync <= {encoder_b_sync[0], encoder_b};
            encoder_a_prev <= encoder_a_sync[1];
            encoder_b_prev <= encoder_b_sync[1];
            if (encoder_a_sync[1] && !encoder_a_prev)
                encoder_a_rises <= encoder_a_rises + 16'd1;
            if (encoder_b_sync[1] && !encoder_b_prev)
                encoder_b_rises <= encoder_b_rises + 16'd1;
        end
    end

    // Feature bit 3 marks this diagnostic-only register interpretation:
    // snapshot 0x30: bit 0=A, bit 1=B; snapshot 0x34: B count:A count.
    // Snapshot 0x14 remains the signed IN5 ADC raw code.
    motor_status_regs #(.FEATURE_FLAGS(32'h0000_000f)) u_status (
        .clk             (clk),
        .resetn          (resetn),
        .mem_addr        (status_addr),
        .mem_web         (status_web),
        .mem_csb         (status_csb),
        .mem_din         (status_wdata),
        .mem_dout        (status_rdata),
        .speed           ({{16{current_raw[15]}}, current_raw}),
        .current_mA      (current_ma),
        .vibration1_data (vibration1),
        .vibration2_data (vibration2),
        .vibration3_data (vibration3),
        .data_valid      (data_valid),
        .adc_error       (adc_error),
        .motor_fault     (1'b0),
        .fault_code      ({1'b0, encoder_b_sync[1], encoder_a_sync[1]}),
        .direction       (1'b0),
        .motor_stby      (motor_stby),
        .motor_an1       (motor_ain1),
        .motor_an2       (motor_ain2),
        .motor_target    ({encoder_b_rises, encoder_a_rises}),
        .motor_ctrl      (2'b00),
        .trial_status    (32'd0)
    );
endmodule
