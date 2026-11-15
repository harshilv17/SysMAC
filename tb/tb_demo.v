`timescale 1ns/1ps

// Demo run for waveform/video: one job on the reference matrices.
// Expected C = [[30,24,18],[84,69,54],[138,114,90]]
module tb_demo;
    reg clk = 0, reset = 1, start = 0;
    reg [71:0] a_flat, b_flat;
    wire done;
    wire [287:0] c_flat;
    integer i, j, errors = 0, cycles = 0;
    reg signed [31:0] expected [0:8];

    systolic_accelerator_top uut (
        .clk(clk), .reset(reset), .start(start),
        .a_flat(a_flat), .b_flat(b_flat), .done(done), .c_flat(c_flat)
    );

    always #5 clk = ~clk;

    initial begin
        // A = 1..9, B = 9..1, row-major, element 0 in the low byte
        a_flat = {8'd9, 8'd8, 8'd7, 8'd6, 8'd5, 8'd4, 8'd3, 8'd2, 8'd1};
        b_flat = {8'd1, 8'd2, 8'd3, 8'd4, 8'd5, 8'd6, 8'd7, 8'd8, 8'd9};
        expected[0] = 30;  expected[1] = 24;  expected[2] = 18;
        expected[3] = 84;  expected[4] = 69;  expected[5] = 54;
        expected[6] = 138; expected[7] = 114; expected[8] = 90;

        $dumpfile("sim/waveforms/demo.vcd");
        $dumpvars(0, tb_demo);

        repeat (3) @(posedge clk);
        #1 reset = 0;
        repeat (2) @(posedge clk);

        @(negedge clk) start = 1;
        @(posedge clk); cycles = 1;
        @(negedge clk) start = 0;
        while (!done && cycles < 50) begin
            @(posedge clk); cycles = cycles + 1; #1;
        end

        for (i = 0; i < 3; i = i + 1) begin
            $display("C[%0d] = %0d %0d %0d", i,
                $signed(c_flat[(i*3+0)*32 +: 32]),
                $signed(c_flat[(i*3+1)*32 +: 32]),
                $signed(c_flat[(i*3+2)*32 +: 32]));
            for (j = 0; j < 3; j = j + 1)
                if ($signed(c_flat[(i*3+j)*32 +: 32]) !== expected[i*3+j]) errors = errors + 1;
        end
        $display("start->done = %0d cycles, errors=%0d", cycles, errors);
        repeat (3) @(posedge clk);
        if (errors == 0) $display("DEMO PASSED");
        else $display("DEMO FAILED");
        $finish;
    end
endmodule
