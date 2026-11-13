`timescale 1ns/1ps

// Top-level test: directed + random matrices, back-to-back jobs, reset mid-job.
// Fails on any mismatch. Also checks start->done latency.
module tb_accelerator_top;
    localparam EXPECTED_LAT = 10;   // posedges from start sample to done visible

    reg clk = 0, reset = 1, start = 0;
    reg [71:0] a_flat = 0, b_flat = 0;
    wire done;
    wire [287:0] c_flat;

    integer errors = 0, jobs = 0, cycles, i, j, k, n, seed = 1;
    reg signed [31:0] exp_c, got_c;

    systolic_accelerator_top uut (
        .clk(clk), .reset(reset), .start(start),
        .a_flat(a_flat), .b_flat(b_flat),
        .done(done), .c_flat(c_flat)
    );

    always #5 clk = ~clk;

    // Start a job; leaves inputs held. Returns after done is seen (cycles = latency).
    task start_job(input [71:0] a, input [71:0] b);
        begin
            @(negedge clk);
            a_flat = a; b_flat = b; start = 1;
            cycles = 0;
            @(posedge clk); cycles = 1;
            @(negedge clk) start = 0;
        end
    endtask

    task wait_done;
        begin
            while (!done && cycles < 50) begin
                @(posedge clk); cycles = cycles + 1; #1;
            end
        end
    endtask

    // Run one job and compare all 9 outputs to a behavioral reference.
    task run_job(input [71:0] a, input [71:0] b, input [255:0] name);
        begin
            start_job(a, b);
            wait_done;
            jobs = jobs + 1;
            if (cycles != EXPECTED_LAT) begin
                errors = errors + 1;
                $display("FAIL %0s: latency %0d, expected %0d", name, cycles, EXPECTED_LAT);
            end
            for (i = 0; i < 3; i = i + 1)
                for (j = 0; j < 3; j = j + 1) begin
                    exp_c = 0;
                    for (k = 0; k < 3; k = k + 1)
                        exp_c = exp_c + $signed(a[(i*3+k)*8 +: 8]) * $signed(b[(k*3+j)*8 +: 8]);
                    got_c = c_flat[(i*3+j)*32 +: 32];
                    if (got_c !== exp_c) begin
                        errors = errors + 1;
                        $display("FAIL %0s: C[%0d][%0d] expected %0d got %0d", name, i, j, exp_c, got_c);
                    end
                end
            @(posedge clk); #1;
            if (done) begin
                errors = errors + 1;
                $display("FAIL %0s: done stuck high", name);
            end
        end
    endtask

    function [71:0] pack9(input integer v0, v1, v2, v3, v4, v5, v6, v7, v8);
        pack9 = {v8[7:0], v7[7:0], v6[7:0], v5[7:0], v4[7:0], v3[7:0], v2[7:0], v1[7:0], v0[7:0]};
    endfunction

    reg [71:0] ra, rb;

    initial begin
        $dumpfile("sim/top_waveform.vcd");
        $dumpvars(0, tb_accelerator_top);

        repeat (3) @(posedge clk);
        #1 reset = 0;

        // 1. reference demo: expect [[30,24,18],[84,69,54],[138,114,90]]
        run_job(pack9(1,2,3,4,5,6,7,8,9), pack9(9,8,7,6,5,4,3,2,1), "demo");

        // 2. identity: A*I = A
        run_job(pack9(1,2,3,4,5,6,7,8,9), pack9(1,0,0,0,1,0,0,0,1), "A*I");
        run_job(pack9(1,0,0,0,1,0,0,0,1), pack9(1,2,3,4,5,6,7,8,9), "I*B");

        // 3. zero
        run_job(pack9(1,2,3,4,5,6,7,8,9), 72'd0, "zero");

        // 4. signed / mixed
        run_job(pack9(-1,2,-3,4,-5,6,-7,8,-9), pack9(9,-8,7,-6,5,-4,3,-2,1), "mixed");

        // 5. boundaries
        run_job(pack9(-128,-128,-128,-128,-128,-128,-128,-128,-128),
                pack9(-128,-128,-128,-128,-128,-128,-128,-128,-128), "min*min");
        run_job(pack9(127,127,127,127,127,127,127,127,127),
                pack9(127,127,127,127,127,127,127,127,127), "max*max");
        run_job(pack9(-128,-128,-128,-128,-128,-128,-128,-128,-128),
                pack9(127,127,127,127,127,127,127,127,127), "min*max");

        // 6. random, back-to-back (no reset between jobs)
        for (n = 0; n < 100; n = n + 1) begin
            for (i = 0; i < 9; i = i + 1) begin
                ra[i*8 +: 8] = $random(seed);
                rb[i*8 +: 8] = $random(seed);
            end
            run_job(ra, rb, "random");
        end

        // 7. reset mid-job, then a clean job must still be correct
        start_job(pack9(5,5,5,5,5,5,5,5,5), pack9(5,5,5,5,5,5,5,5,5));
        repeat (4) @(posedge clk);
        @(negedge clk) reset = 1;
        @(negedge clk) reset = 0;
        #1 if (done) begin errors = errors + 1; $display("FAIL: done after reset"); end
        run_job(pack9(1,2,3,4,5,6,7,8,9), pack9(9,8,7,6,5,4,3,2,1), "after reset");

        $display("jobs=%0d errors=%0d latency=%0d cycles", jobs, errors, EXPECTED_LAT);
        if (errors == 0) $display("ALL TOP TESTS PASSED");
        else $fatal(1, "TOP TESTS FAILED");
        $finish;
    end
endmodule
