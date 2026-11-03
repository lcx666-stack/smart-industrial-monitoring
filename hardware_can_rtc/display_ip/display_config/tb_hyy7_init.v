`timescale 1ns / 1ps

// Offline check of the current Anlogic instruction engine and HYY7 ROM.
// The ROM and LP transmitter are modeled; no D-PHY or physical panel is modeled.
module rom(output reg [7:0] doa, input [9:0] addra, input clka);
    reg [7:0] mem [0:1023];
    initial $readmemb("display_ip/al_ip/rom/config_data_hyy7.dat", mem);
    always @(posedge clka) doa <= mem[addra];
endmodule

module tb_hyy7_init;
    reg clk = 0;
    always #50 clk = ~clk; // 10 MHz LP/config clock
    reg rst = 1;
    reg start = 0;
    reg ready = 0;
    wire done, valid, last;
    wire [7:0] data;
    reg [7:0] bytes [0:255];
    integer nbytes = 0;
    integer npackets = 0;
    integer cycles = 0;
    integer sleep_out = 0;
    integer display_on = 0;

    display_config_wrapper dut (
        .I_clk(clk), .I_rst(rst), .I_config_start(start),
        .O_config_done(done), .O_lp_tx_valid(valid),
        .O_lp_tx_last(last), .O_lp_tx_data(data), .I_lp_tx_ready(ready)
    );

    // Model a transmitter that acknowledges one cycle after each full packet.
    always @(negedge clk) begin
        ready = 0;
        if (!rst) begin
            cycles = cycles + 1;
            if (valid) begin
                if (nbytes >= 256) $fatal(1, "packet too large");
                bytes[nbytes] = data;
                nbytes = nbytes + 1;
                if (last) begin
                    npackets = npackets + 1;
                    if (bytes[0] != 8'h05 && bytes[0] != 8'h15 && bytes[0] != 8'h39)
                        $fatal(1, "invalid DSI data type in packet %0d: %02x", npackets, bytes[0]);
                    if (bytes[0] == 8'h05 && bytes[1] == 8'h11) sleep_out = npackets;
                    if (bytes[0] == 8'h05 && bytes[1] == 8'h29) display_on = npackets;
                    $display("PACKET %0d dt=%02x bytes=%0d cmd=%02x", npackets,
                             bytes[0], nbytes, bytes[0] == 8'h39 ? bytes[4] : bytes[1]);
                    nbytes = 0;
                    ready = 1;
                end
            end
            if (done) begin
                $display("DONE packets=%0d sleep_out=%0d display_on=%0d cycles=%0d",
                         npackets, sleep_out, display_on, cycles);
                // Vendor Anlogic ROM convention appends one DCS NOP before END.
                if (npackets != 51 || sleep_out != 49 || display_on != 50 ||
                    bytes[0] != 8'h05 || bytes[1] != 8'h00)
                    $fatal(1, "HYY7 initialization sequence mismatch");
                $finish;
            end
        end
    end

    initial begin
        repeat (5) @(negedge clk);
        rst = 0;
        repeat (5) @(negedge clk);
        start = 1;
        repeat (5) @(negedge clk);
        start = 0;
        repeat (3000000) @(negedge clk);
        $fatal(1, "initialization timed out after %0d packets", npackets);
    end
endmodule
