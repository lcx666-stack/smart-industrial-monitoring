`timescale 1ns/1ps
// 0x3B43 diagnostic image: two spare J12 outputs drive a 50 kHz Gray cycle.
// Physical motor-control outputs are constant low regardless of AXI commands.
module motor_encoder_loopback_top (
    input wire encoder_a, encoder_b,
    input wire [7:0] adc_data,
    input wire adc_busy, adc_first_data,
    output wire adc_reset, adc_convst_a, adc_convst_b, adc_cs_n, adc_rd_n,
    output wire pwm, AN1, AN2, STBY,
    output wire loopback_a, loopback_b
);
    wire diagnostic_clk, diagnostic_resetn;
    wire unused_pwm, unused_an1, unused_an2, unused_stby;
    reg [8:0] quarter_count;
    reg [1:0] phase;

    motor_soc_top #(.IMAGE_FEATURE_FLAGS(32'h0000_3b43), .ENCODER_FILTER_CYCLES(4)) u_core (
        .encoder_a(encoder_a), .encoder_b(encoder_b), .adc_data(adc_data),
        .adc_busy(adc_busy), .adc_first_data(adc_first_data),
        .adc_reset(adc_reset), .adc_convst_a(adc_convst_a),
        .adc_convst_b(adc_convst_b), .adc_cs_n(adc_cs_n), .adc_rd_n(adc_rd_n),
        .pwm(unused_pwm), .AN1(unused_an1), .AN2(unused_an2), .STBY(unused_stby),
        .diagnostic_clk(diagnostic_clk), .diagnostic_resetn(diagnostic_resetn));

    always @(posedge diagnostic_clk) begin
        if (!diagnostic_resetn) begin
            quarter_count <= 0;
            phase <= 0;
        end else if (quarter_count == 499) begin
            quarter_count <= 0;
            phase <= phase + 1'b1;
        end else begin
            quarter_count <= quarter_count + 1'b1;
        end
    end

    // 00 -> 10 -> 11 -> 01 -> 00; one transition every 500 clocks.
    // Each A/B channel is high for 1000 clocks (10 us nominal).
    assign loopback_a = diagnostic_resetn && (phase == 1 || phase == 2);
    assign loopback_b = diagnostic_resetn && (phase == 2 || phase == 3);

    assign pwm = 1'b0;
    assign AN1 = 1'b0;
    assign AN2 = 1'b0;
    assign STBY = 1'b0;
endmodule
