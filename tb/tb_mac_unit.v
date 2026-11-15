`timescale 1ns/1ps

// SysMAC: Systolic Array Matrix Multiplication Accelerator
// Testbench: tb_mac_unit
// Author: Abhishek

module tb_mac_unit;
    parameter DATA_WIDTH = 8;
    parameter ACC_WIDTH  = 32;

    reg                          clk   = 0;
    reg                          reset = 1;
    reg  signed [DATA_WIDTH-1:0] a     = 0;
    reg  signed [DATA_WIDTH-1:0] b     = 0;
    wire signed [ACC_WIDTH-1:0]  acc;

    integer errors = 0;
    integer tests  = 0;
    reg signed [ACC_WIDTH-1:0] expected_acc = 0;

    mac_unit #(
        .DATA_WIDTH(DATA_WIDTH),
        .ACC_WIDTH (ACC_WIDTH)
    ) uut (
        .clk  (clk),
        .reset(reset),
        .a    (a),
        .b    (b),
        .acc  (acc)
    );

    always #5 clk = ~clk;

    task check(input cond, input [255:0] msg);
        begin
            tests = tests + 1;
            if (!cond) begin
                errors = errors + 1;
                $display("FAIL: %0s at %0t | acc=%0d, expected=%0d", msg, $time, acc, expected_acc);
            end
        end
    endtask

    // Step one clock cycle with new inputs and verify output
    task step_mac(input signed [DATA_WIDTH-1:0] in_a, input signed [DATA_WIDTH-1:0] in_b, input [255:0] tag);
        begin
            @(negedge clk);
            a = in_a;
            b = in_b;
            expected_acc = expected_acc + (in_a * in_b);
            @(posedge clk);
            #1;
            check(acc === expected_acc, tag);
        end
    endtask

    integer seed = 42;
    integer k;
    reg signed [DATA_WIDTH-1:0] rand_a, rand_b;

    initial begin
        $dumpfile("sim/mac_waveform.vcd");
        $dumpvars(0, tb_mac_unit);

        // 1. Initial reset check
        repeat (3) @(posedge clk);
        #1;
        check(acc === 32'sd0, "acc is 0 during reset");

        // Release reset
        @(negedge clk);
        reset = 0;
        expected_acc = 0;
        @(posedge clk);
        #1;
        check(acc === 32'sd0, "acc is 0 right after reset deassertion");

        // 2. Simple positive accumulation
        step_mac(8'sd2, 8'sd3, "2 * 3 = 6");
        step_mac(8'sd4, 8'sd5, "accumulate 4 * 5 = 20 (total 26)");
        step_mac(8'sd10, 8'sd10, "accumulate 10 * 10 = 100 (total 126)");

        // 3. Signed arithmetic: negative operands
        step_mac(-8'sd5, 8'sd4, "accumulate -5 * 4 = -20 (total 106)");
        step_mac(8'sd6, -8'sd7, "accumulate 6 * -7 = -42 (total 64)");
        step_mac(-8'sd8, -8'sd9, "accumulate -8 * -9 = +72 (total 136)");

        // 4. Multiplying by 0
        step_mac(8'sd0, 8'sd50, "accumulate 0 * 50 = 0 (total 136)");
        step_mac(-8'sd50, 8'sd0, "accumulate -50 * 0 = 0 (total 136)");

        // 5. Extreme corner cases (8-bit signed range: -128 to +127)
        step_mac(8'sd127, 8'sd127, "max positive: 127 * 127 = 16129");
        step_mac(-8'sd128, -8'sd128, "max negative * max negative: -128 * -128 = 16384");
        step_mac(-8'sd128, 8'sd127, "min negative * max positive: -128 * 127 = -16256");

        // 6. Reset mid-stream test
        @(negedge clk);
        reset = 1;
        a     = 0;
        b     = 0;
        expected_acc = 0;
        @(posedge clk);
        #1;
        check(acc === 32'sd0, "reset clears non-zero accumulator to 0");

        @(negedge clk);
        reset = 0;
        @(posedge clk);
        #1;
        check(acc === 32'sd0, "post-reset holds 0 when inputs are 0");

        // 7. Randomized testing across full 8-bit dynamic range
        for (k = 0; k < 100; k = k + 1) begin
            rand_a = $dist_uniform(seed, -128, 127);
            rand_b = $dist_uniform(seed, -128, 127);
            step_mac(rand_a, rand_b, "random test vector");
        end

        // Final result reporting
        if (errors == 0) begin
            $display("MAC_UNIT TEST PASSED: errors=0, tests=%0d", tests);
        end else begin
            $display("MAC_UNIT TEST FAILED: %0d errors out of %0d tests", errors, tests);
        end
        $finish;
    end

endmodule
