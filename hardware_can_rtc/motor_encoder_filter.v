`timescale 1ns/1ps

// Shared CDC/whole-vector qualification for the opt-in filtered image.
// Never qualify A and B independently: that could invent legal intermediate
// states when a sustained diagonal transition must remain an invalid event.
module motor_encoder_filter #(
    parameter integer STABLE_CYCLES = 16
) (
    input wire clk, resetn, encoder_a, encoder_b,
    output wire [1:0] raw_ab, // {A,B}, after two synchronizer stages
    output wire raw_ready, raw_activity,
    output reg [1:0] qualified_ab,
    output reg qualified_ready,
    output reg [31:0] rejected_candidates
);
    localparam integer COUNT_BITS = (STABLE_CYCLES < 2) ? 1 : $clog2(STABLE_CYCLES+1);
    (* ASYNC_REG = "TRUE" *) reg [1:0] a_sync, b_sync;
    reg [1:0] sync_ready, previous_raw, candidate;
    reg [COUNT_BITS-1:0] stable_count;
    assign raw_ab = {a_sync[1],b_sync[1]};
    assign raw_ready = sync_ready == 3;
    assign raw_activity = raw_ready && (raw_ab != previous_raw);

    always @(posedge clk) begin
        if (!resetn) begin
            a_sync<=0; b_sync<=0; sync_ready<=0; previous_raw<=0;
            candidate<=0; stable_count<=0; qualified_ab<=0;
            qualified_ready<=0; rejected_candidates<=0;
        end else begin
            a_sync <= {a_sync[0],encoder_a};
            b_sync <= {b_sync[0],encoder_b};
            previous_raw <= raw_ab;
            if (!raw_ready) begin
                sync_ready <= sync_ready+1'b1;
                candidate <= raw_ab;
                stable_count <= 0;
            end else if (raw_ab != candidate || stable_count == 0) begin
                if (qualified_ready && candidate != qualified_ab &&
                    stable_count != 0 && stable_count < STABLE_CYCLES &&
                    !(&rejected_candidates))
                    rejected_candidates <= rejected_candidates+1'b1;
                candidate <= raw_ab;
                stable_count <= 1;
                if (STABLE_CYCLES == 1) begin
                    qualified_ab <= raw_ab;
                    qualified_ready <= 1;
                end
            end else if (stable_count < STABLE_CYCLES) begin
                stable_count <= stable_count+1'b1;
                if (stable_count == STABLE_CYCLES-1) begin
                    qualified_ab <= candidate;
                    qualified_ready <= 1;
                end
            end
        end
    end
    // synthesis translate_off
    initial begin
        if (STABLE_CYCLES < 1 || STABLE_CYCLES > 65536)
            $fatal(1,"motor_encoder_filter: STABLE_CYCLES must be 1..65536");
    end
    // synthesis translate_on
endmodule
