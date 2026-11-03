`timescale 1ns/1ps

// Passive 100 MHz event logger. No output connects to a drive-control input.
// Last 64 PRE events, fault event plus up to 63 POST events; freeze 2 ms later.
// Excess POST events are counted, never allowed to overwrite the first fault.
module motor_encoder_observe #(
    parameter integer POST_CYCLES = 200000
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
    input wire [1:0] motor_ctrl
);
    reg [31:0] event_lo[0:127], event_hi[0:127], event_state[0:127], event_delta[0:127];
    reg [63:0] ticks, start_tick, trigger_tick, freeze_tick;
    reg [31:0] previous_word, elapsed, dropped;
    reg [5:0] pre_next;
    reg [6:0] pre_count, post_count;
    reg observing, triggered, frozen, old_core, old_guard, saturated;
    reg [2:0] reason;
    reg [1:0] previous_levels, edge_seen;
    reg [63:0] edge_tick[0:1];
    reg [31:0] rises[0:1], falls[0:1], high_count[0:1], low_count[0:1];
    reg [63:0] high_min[0:1], high_max[0:1], low_min[0:1], low_max[0:1];
    reg [31:0] width_bins[0:31], proximity[0:9];
    reg pwm_seen, previous_pwm;
    reg [63:0] pwm_tick;
    reg [31:0] pwm_rises, pwm_falls;
    wire [2:0] new_reason = {guard_fault && !old_guard, core_fault && !old_core, encoder_invalid};
    // Same bit layout as ETR1; bit 0=A, bit 1=B after two-stage CDC.
    wire [31:0] sample_word = {7'd0,motor_ctrl,duty,an2,an1,stby,pwm,
        drive_permit,guard_fault,core_fault,encoder_invalid,encoder_step,
        raw_activity,qualified_ready,raw_ready,qualified_ab[0],qualified_ab[1],raw_ab[0],raw_ab[1]};
    wire [1:0] levels = {raw_ab[0],raw_ab[1]};
    wire fault_now = !triggered && (|new_reason);
    wire event_now = sample_word != previous_word || fault_now || (!observing && raw_ready);
    wire pwm_edge = observing && pwm != previous_pwm;
    wire [63:0] pwm_age = pwm_edge ? 64'd0 : ticks-pwm_tick;
    wire [6:0] write_index = fault_now ? 7'd64 :
        (triggered ? (7'd64+post_count[5:0]) : {1'b0,pre_next});
    function [31:0] inc_sat(input [31:0] value);
        begin inc_sat = (&value) ? value : value+1'b1; end
    endfunction
    function [2:0] width_bin(input [63:0] width);
        begin
            if(width < 4) width_bin=0; else if(width < 16) width_bin=1;
            else if(width < 100) width_bin=2; else if(width < 1000) width_bin=3;
            else if(width < 10000) width_bin=4; else if(width < 100000) width_bin=5;
            else if(width < 1000000) width_bin=6; else width_bin=7;
        end
    endfunction
    function [2:0] pwm_bin(input [63:0] age, input seen);
        begin
            if(!seen) pwm_bin=4; else if(age < 10) pwm_bin=0;
            else if(age < 100) pwm_bin=1; else if(age < 1000) pwm_bin=2;
            else pwm_bin=3;
        end
    endfunction
    integer c, j, bin_index, near_index;
    reg [63:0] width_value;
    always @(posedge clk) begin
        if(!resetn) begin
            ticks<=0; start_tick<=0; trigger_tick<=0; freeze_tick<=0;
            previous_word<=0; elapsed<=0; dropped<=0; pre_next<=0;
            pre_count<=0; post_count<=0; observing<=0; triggered<=0; frozen<=0;
            old_core<=0; old_guard<=0; saturated<=0; reason<=0;
            previous_levels<=0; edge_seen<=0; pwm_seen<=0; previous_pwm<=0;
            pwm_tick<=0; pwm_rises<=0; pwm_falls<=0;
            for(c=0;c<2;c=c+1) begin
                edge_tick[c]<=0; rises[c]<=0; falls[c]<=0; high_count[c]<=0; low_count[c]<=0;
                high_min[c]<=64'hffffffffffffffff; high_max[c]<=0;
                low_min[c]<=64'hffffffffffffffff; low_max[c]<=0;
            end
            for(j=0;j<32;j=j+1) width_bins[j]<=0;
            for(j=0;j<10;j=j+1) proximity[j]<=0;
        end else if(!frozen) begin
            ticks<=ticks+1'b1;
            old_core<=core_fault; old_guard<=guard_fault;
            previous_word<=sample_word;
            if(!observing && raw_ready) begin
                observing<=1; start_tick<=ticks; previous_levels<=levels; previous_pwm<=pwm;
            end else if(observing) begin
                previous_levels<=levels; previous_pwm<=pwm;
                if(pwm_edge) begin
                    pwm_seen<=1; pwm_tick<=ticks;
                    if(pwm) begin pwm_rises<=inc_sat(pwm_rises); if(&pwm_rises) saturated<=1; end
                    else begin pwm_falls<=inc_sat(pwm_falls); if(&pwm_falls) saturated<=1; end
                end
                for(c=0;c<2;c=c+1) begin
                    if(levels[c] != previous_levels[c]) begin
                        if(levels[c]) begin rises[c]<=inc_sat(rises[c]); if(&rises[c]) saturated<=1; end
                        else begin falls[c]<=inc_sat(falls[c]); if(&falls[c]) saturated<=1; end
                        near_index=c*5+pwm_bin(pwm_age,pwm_seen || pwm_edge);
                        proximity[near_index]<=inc_sat(proximity[near_index]);
                        if(&proximity[near_index]) saturated<=1;
                        // Exclude the initial, left-censored level segment.
                        if(edge_seen[c]) begin
                            width_value=ticks-edge_tick[c];
                            bin_index=c*16+(previous_levels[c] ? 0 : 8)+width_bin(width_value);
                            width_bins[bin_index]<=inc_sat(width_bins[bin_index]);
                            if(&width_bins[bin_index]) saturated<=1;
                            if(previous_levels[c]) begin
                                high_count[c]<=inc_sat(high_count[c]); if(&high_count[c]) saturated<=1;
                                if(width_value < high_min[c]) high_min[c]<=width_value;
                                if(width_value > high_max[c]) high_max[c]<=width_value;
                            end else begin
                                low_count[c]<=inc_sat(low_count[c]); if(&low_count[c]) saturated<=1;
                                if(width_value < low_min[c]) low_min[c]<=width_value;
                                if(width_value > low_max[c]) low_max[c]<=width_value;
                            end
                        end
                        edge_tick[c]<=ticks; edge_seen[c]<=1;
                    end
                end
            end
            if(event_now) begin
                if(!triggered || post_count < 64) begin
                    event_lo[write_index]<=ticks[31:0]; event_hi[write_index]<=ticks[63:32];
                    event_state[write_index]<=sample_word;
                    event_delta[write_index]<=sample_word ^ previous_word;
                    if(fault_now) post_count<=1;
                    else if(triggered) post_count<=post_count+1'b1;
                    else begin
                        pre_next<=pre_next+1'b1;
                        if(pre_count < 64) pre_count<=pre_count+1'b1;
                    end
                end else begin dropped<=inc_sat(dropped); if(&dropped) saturated<=1; end
            end
            if(fault_now) begin
                triggered<=1; reason<=new_reason; trigger_tick<=ticks; elapsed<=0;
            end else if(triggered) begin
                if(elapsed == POST_CYCLES-1) begin frozen<=1; freeze_tick<=ticks; end
                else elapsed<=elapsed+1'b1;
            end
        end
    end

    integer read_channel, read_hist, read_near;
    always @(posedge clk) begin
        if(!resetn) mem_dout<=0;
        else if(!mem_csb && (&mem_web)) begin
            case(mem_addr)
                'h100: mem_dout<=32'h454c4731; // ELG1 at 0x400
                'h101: mem_dout<=32'h00010000;
                'h102: mem_dout<={26'd0,saturated,(dropped!=0),qualified_ready,raw_ready,frozen,triggered};
                'h103: mem_dout<=100000000;
                'h104: mem_dout<=64; 'h105: mem_dout<=64;
                'h106: mem_dout<=pre_count; 'h107: mem_dout<=pre_next;
                'h108: mem_dout<=post_count; 'h109: mem_dout<={29'd0,reason};
                'h10a: mem_dout<=trigger_tick[31:0]; 'h10b: mem_dout<=trigger_tick[63:32];
                'h10c: mem_dout<=freeze_tick[31:0]; 'h10d: mem_dout<=freeze_tick[63:32];
                'h10e: mem_dout<=POST_CYCLES; 'h10f: mem_dout<=dropped;
                'h110: mem_dout<=start_tick[31:0]; 'h111: mem_dout<=start_tick[63:32];
                'h112: mem_dout<=4; 'h113: mem_dout<=128;
                'h114: mem_dout<=32'h800;
                'h115: mem_dout<={29'd0,observing,previous_levels};
                'h118: mem_dout<=pwm_rises; 'h119: mem_dout<=pwm_falls;
                'h11a: mem_dout<=pwm_tick[31:0]; 'h11b: mem_dout<=pwm_tick[63:32];
                'h11c: mem_dout<={31'd0,pwm_seen};
                default: begin
                    if(mem_addr >= 'h200) begin
                        case(mem_addr[1:0])
                            0: mem_dout<=event_lo[mem_addr[8:2]];
                            1: mem_dout<=event_hi[mem_addr[8:2]];
                            2: mem_dout<=event_state[mem_addr[8:2]];
                            3: mem_dout<=event_delta[mem_addr[8:2]];
                        endcase
                    end else if(mem_addr >= 'h140 && mem_addr < 'h1c0) begin
                        read_channel=mem_addr[7];
                        case(mem_addr[5:0])
                            'h00: mem_dout<=rises[read_channel]; 'h01: mem_dout<=falls[read_channel];
                            'h02: mem_dout<=high_count[read_channel]; 'h03: mem_dout<=low_count[read_channel];
                            'h04: mem_dout<=high_min[read_channel][31:0]; 'h05: mem_dout<=high_min[read_channel][63:32];
                            'h06: mem_dout<=high_max[read_channel][31:0]; 'h07: mem_dout<=high_max[read_channel][63:32];
                            'h08: mem_dout<=low_min[read_channel][31:0]; 'h09: mem_dout<=low_min[read_channel][63:32];
                            'h0a: mem_dout<=low_max[read_channel][31:0]; 'h0b: mem_dout<=low_max[read_channel][63:32];
                            'h0c: mem_dout<=edge_tick[read_channel][31:0]; 'h0d: mem_dout<=edge_tick[read_channel][63:32];
                            'h0e: mem_dout<={31'd0,edge_seen[read_channel]};
                            'h0f: mem_dout<={31'd0,previous_levels[read_channel]};
                            default: begin
                                if(mem_addr[5:0] >= 'h10 && mem_addr[5:0] < 'h20) begin
                                    read_hist=read_channel*16+mem_addr[3:0]; mem_dout<=width_bins[read_hist];
                                end else if(mem_addr[5:0] >= 'h20 && mem_addr[5:0] <= 'h24) begin
                                    read_near=read_channel*5+mem_addr[2:0]; mem_dout<=proximity[read_near];
                                end else mem_dout<=0;
                            end
                        endcase
                    end else mem_dout<=0;
                end
            endcase
        end
    end
    // synthesis translate_off
    initial if(POST_CYCLES < 1 || POST_CYCLES > 100000000)
        $fatal(1,"motor_encoder_observe: invalid post-fault observation interval");
    // synthesis translate_on
endmodule
