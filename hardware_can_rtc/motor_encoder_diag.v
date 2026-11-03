`timescale 1ns/1ps

// Read-only encoder diagnostics. CAPTURE at 0x08 freezes this register group
// alongside the motor/ADC snapshot. No writes can affect motor commands.
module motor_encoder_diag #(parameter integer INPUT_IS_QUALIFIED = 0) (
    input wire clk, resetn, encoder_a, encoder_b,
    input wire qualified_ready,
    input wire [9:0] mem_addr,
    input wire [3:0] mem_web,
    input wire mem_csb,
    input wire [31:0] mem_din,
    output reg [31:0] mem_dout
);
    (* ASYNC_REG = "TRUE" *) reg [1:0] a_sync, b_sync;
    reg [1:0] ready, old_state;
    wire [1:0] state_now = INPUT_IS_QUALIFIED ? {encoder_a,encoder_b} : {a_sync[1],b_sync[1]};
    wire [3:0] transition = {old_state, state_now};
    wire forward = transition == 4'b0010 || transition == 4'b1011 ||
                   transition == 4'b1101 || transition == 4'b0100;
    wire reverse = transition == 4'b0001 || transition == 4'b0111 ||
                   transition == 4'b1110 || transition == 4'b1000;
    reg [31:0] a_rises, b_rises, steps, invalid, forward_steps, reverse_steps;
    reg [31:0] snap_levels, snap_a, snap_b, snap_steps, snap_invalid, snap_forward, snap_reverse;
    wire capture = !mem_csb && !mem_web[0] && mem_addr == 10'h002 && mem_din[0];
    always @(posedge clk) begin
        if (!resetn) begin
            a_sync<=0; b_sync<=0; ready<=0; old_state<=0;
            a_rises<=0; b_rises<=0; steps<=0; invalid<=0;
            forward_steps<=0; reverse_steps<=0;
            snap_levels<=0; snap_a<=0; snap_b<=0; snap_steps<=0;
            snap_invalid<=0; snap_forward<=0; snap_reverse<=0;
        end else begin
            a_sync <= {a_sync[0], encoder_a};
            b_sync <= {b_sync[0], encoder_b};
            old_state <= state_now;
            if (INPUT_IS_QUALIFIED && !qualified_ready) ready<=0;
            else if (ready != 3) ready <= INPUT_IS_QUALIFIED ? 2'd3 : ready + 1'b1;
            else begin
                if (state_now[1] && !old_state[1]) a_rises <= a_rises + 1'b1;
                if (state_now[0] && !old_state[0]) b_rises <= b_rises + 1'b1;
                if (forward || reverse) steps <= steps + 1'b1;
                if (forward) forward_steps <= forward_steps + 1'b1;
                if (reverse) reverse_steps <= reverse_steps + 1'b1;
                if (state_now != old_state && !forward && !reverse) invalid <= invalid + 1'b1;
            end
            if (capture) begin
                snap_levels <= {29'd0, ready == 3, state_now[0], state_now[1]};
                snap_a <= a_rises; snap_b <= b_rises; snap_steps <= steps;
                snap_invalid <= invalid;
                snap_forward <= forward_steps; snap_reverse <= reverse_steps;
            end
        end
    end
    always @(posedge clk) begin
        if (!resetn) mem_dout <= 0;
        else if (!mem_csb && (&mem_web)) begin
            case(mem_addr)
                10'h058: mem_dout <= 32'h454e_4331; // ENC1, byte offset 0x160
                10'h059: mem_dout <= 32'h0001_0000;
                10'h05a: mem_dout <= snap_levels;
                10'h05b: mem_dout <= snap_a;
                10'h05c: mem_dout <= snap_b;
                10'h05d: mem_dout <= snap_steps;
                10'h05e: mem_dout <= snap_invalid;
                10'h05f: mem_dout <= snap_forward;
                10'h060: mem_dout <= snap_reverse;
                default: mem_dout <= 0;
            endcase
        end
    end
endmodule
