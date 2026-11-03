`timescale 1ns/1ps

// 64 consecutive 100 MHz samples, circular until the first fault, then 16
// post-trigger clocks. Read-only and frozen until reset, NEVER a drive control.
module motor_encoder_trace #(
    parameter integer DEPTH = 64,
    parameter integer POST_SAMPLES = 16,
    parameter integer FILTER_CYCLES = 16
) (
    input wire clk, resetn,
    input wire [9:0] mem_addr,
    input wire [3:0] mem_web,
    input wire mem_csb,
    output reg [31:0] mem_dout,
    input wire [1:0] raw_ab, qualified_ab,
    input wire raw_ready, qualified_ready, raw_activity, encoder_step, encoder_invalid,
    input wire core_fault, guard_fault, drive_permit, pwm, stby, an1, an2,
    input wire [6:0] duty,
    input wire [1:0] motor_ctrl,
    input wire [31:0] rejected_candidates
);
    localparam integer POINTER_BITS = $clog2(DEPTH);
    reg [31:0] samples [0:DEPTH-1];
    reg [POINTER_BITS-1:0] write_index, trigger_index;
    reg [POINTER_BITS:0] sample_count, post_remaining;
    reg triggered, frozen, old_core_fault, old_guard_fault;
    reg [2:0] reason;
    reg [63:0] ticks, last_tick, trigger_tick;
    reg [31:0] rejected_at_freeze;
    wire [2:0] new_reason = {guard_fault && !old_guard_fault,
                            core_fault && !old_core_fault,encoder_invalid};
    wire [63:0] first_tick = last_tick + 64'd1 - sample_count;
    wire [31:0] sample_word = {7'd0,motor_ctrl,duty,an2,an1,stby,pwm,
                              drive_permit,guard_fault,core_fault,encoder_invalid,
                              encoder_step,raw_activity,qualified_ready,raw_ready,
                              qualified_ab[0],qualified_ab[1],raw_ab[0],raw_ab[1]};
    always @(posedge clk) begin
        if (!resetn) begin
            write_index<=0; trigger_index<=0; sample_count<=0; post_remaining<=0;
            triggered<=0; frozen<=0; old_core_fault<=0; old_guard_fault<=0;
            reason<=0; ticks<=0; last_tick<=0; trigger_tick<=0; rejected_at_freeze<=0;
        end else begin
            ticks <= ticks+1'b1;
            old_core_fault <= core_fault;
            old_guard_fault <= guard_fault;
            if (!frozen) begin
                samples[write_index] <= sample_word;
                write_index <= write_index+1'b1;
                last_tick <= ticks;
                if (sample_count < DEPTH) sample_count <= sample_count+1'b1;
                if (!triggered && (|new_reason)) begin
                    triggered <= 1;
                    reason <= new_reason;
                    trigger_index <= write_index;
                    trigger_tick <= ticks;
                    post_remaining <= POST_SAMPLES;
                end else if (triggered) begin
                    post_remaining <= post_remaining-1'b1;
                    if (post_remaining == 1) begin
                        frozen <= 1;
                        rejected_at_freeze <= rejected_candidates;
                    end
                end
            end
        end
    end
    always @(posedge clk) begin
        if (!resetn) mem_dout<=0;
        else if (!mem_csb && (&mem_web)) begin
            case (mem_addr)
                'h080: mem_dout<=32'h4554_5231; // 0x200 ETR1
                'h081: mem_dout<=32'h0001_0000;
                'h082: mem_dout<={28'd0,qualified_ready,raw_ready,frozen,triggered};
                'h083: mem_dout<=sample_count;
                'h084: mem_dout<=write_index; // oldest index when full
                'h085: mem_dout<=trigger_index;
                'h086: mem_dout<=trigger_tick[31:0];
                'h087: mem_dout<=trigger_tick[63:32];
                'h088: mem_dout<=first_tick[31:0];
                'h089: mem_dout<=first_tick[63:32];
                'h08a: mem_dout<=FILTER_CYCLES;
                'h08b: mem_dout<=DEPTH;
                'h08c: mem_dout<=POST_SAMPLES;
                'h08d: mem_dout<={29'd0,reason};
                'h08e: mem_dout<=frozen ? rejected_at_freeze : rejected_candidates;
                default: begin
                    if (mem_addr >= 'h0a0 && mem_addr < 'h0a0+DEPTH &&
                        ((sample_count == DEPTH) || (mem_addr-'h0a0 < sample_count)))
                        mem_dout <= samples[mem_addr-'h0a0]; // 0x280..0x37c
                    else mem_dout<=0;
                end
            endcase
        end
    end
    // synthesis translate_off
    initial begin
        if (DEPTH < 4 || DEPTH > 128 || (DEPTH & (DEPTH-1)) != 0 ||
            POST_SAMPLES < 1 || POST_SAMPLES > DEPTH-2)
            $fatal(1,"motor_encoder_trace: invalid depth/post-trigger parameters");
    end
    // synthesis translate_on
endmodule
