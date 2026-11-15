`timescale 1ns/1ps

// SysMAC: Systolic Array Matrix Multiplication Accelerator
// Testbench: tb_processing_element
// Author: Abhishek

module tb_processing_element;
    parameter DATA_WIDTH = 8;
    parameter ACC_WIDTH  = 32;

    reg                          clk         = 0;
    reg                          reset       = 1;
    reg                          clear       = 0;
    reg  signed [DATA_WIDTH-1:0] a_in        = 0;
    reg  signed [DATA_WIDTH-1:0] b_in        = 0;
    reg                          valid_a_in  = 0;
    reg                          valid_b_in  = 0;

    wire signed [DATA_WIDTH-1:0] a_out;
    wire signed [DATA_WIDTH-1:0] b_out;
    wire                         valid_a_out;
    wire                         valid_b_out;
    wire signed [ACC_WIDTH-1:0]  acc;

    integer errors = 0;
    integer tests  = 0;

    processing_element #(
        .DATA_WIDTH(DATA_WIDTH),
        .ACC_WIDTH (ACC_WIDTH)
    ) uut (
        .clk        (clk),
        .reset      (reset),
        .clear      (clear),
        .a_in       (a_in),
        .b_in       (b_in),
        .valid_a_in (valid_a_in),
        .valid_b_in (valid_b_in),
        .a_out      (a_out),
        .b_out      (b_out),
        .valid_a_out(valid_a_out),
        .valid_b_out(valid_b_out),
        .acc        (acc)
    );

    always #5 clk = ~clk;

    task check(input cond, input [255:0] msg);
        begin
            tests = tests + 1;
            if (!cond) begin
                errors = errors + 1;
                $display("FAIL: %0s at %0t", msg, $time);
            end
        end
    endtask

    // Behavioral reference model tracking expected state
    reg signed [DATA_WIDTH-1:0] exp_a_out;
    reg signed [DATA_WIDTH-1:0] exp_b_out;
    reg                         exp_va_out;
    reg                         exp_vb_out;
    reg signed [ACC_WIDTH-1:0]  exp_acc;

    task apply_and_step(
        input signed [DATA_WIDTH-1:0] in_a,
        input signed [DATA_WIDTH-1:0] in_b,
        input                         in_va,
        input                         in_vb,
        input                         in_clear,
        input [255:0]                 tag
    );
        begin
            @(negedge clk);
            a_in       = in_a;
            b_in       = in_b;
            valid_a_in = in_va;
            valid_b_in = in_vb;
            clear      = in_clear;

            if (reset || in_clear) begin
                exp_a_out  = 0;
                exp_b_out  = 0;
                exp_va_out = 0;
                exp_vb_out = 0;
                exp_acc    = 0;
            end else begin
                exp_a_out  = in_a;
                exp_b_out  = in_b;
                exp_va_out = in_va;
                exp_vb_out = in_vb;
                if (in_va && in_vb) begin
                    exp_acc = exp_acc + (in_a * in_b);
                end
            end

            @(posedge clk);
            #1;
            check(a_out === exp_a_out, {tag, " [a_out]"});
            check(b_out === exp_b_out, {tag, " [b_out]"});
            check(valid_a_out === exp_va_out, {tag, " [valid_a_out]"});
            check(valid_b_out === exp_vb_out, {tag, " [valid_b_out]"});
            check(acc === exp_acc, {tag, " [acc]"});
        end
    endtask

    integer seed = 12345;
    integer step_i;
    reg signed [DATA_WIDTH-1:0] rand_a, rand_b;
    reg rand_va, rand_vb;

    initial begin
        $dumpfile("sim/pe_waveform.vcd");
        $dumpvars(0, tb_processing_element);

        // 1. Initial Reset Check
        exp_a_out  = 0;
        exp_b_out  = 0;
        exp_va_out = 0;
        exp_vb_out = 0;
        exp_acc    = 0;

        repeat (3) @(posedge clk);
        #1;
        check(a_out === 0 && b_out === 0 && valid_a_out === 0 && valid_b_out === 0 && acc === 0,
              "all outputs zero during reset");

        // Release reset
        @(negedge clk);
        reset = 0;
        clear = 0;

        // 2. Forwarding without accumulation (valid_a_in=0, valid_b_in=0)
        apply_and_step(8'sd10, 8'sd20, 1'b0, 1'b0, 1'b0, "forwarding with both valids low");
        check(acc === 32'sd0, "acc unchanged when valids are low");

        // 3. Partial valids: valid_a_in=1, valid_b_in=0
        apply_and_step(8'sd15, 8'sd25, 1'b1, 1'b0, 1'b0, "forwarding valid_a only");
        check(acc === 32'sd0, "acc unchanged when only valid_a is high");

        // 4. Partial valids: valid_a_in=0, valid_b_in=1
        apply_and_step(8'sd30, 8'sd40, 1'b0, 1'b1, 1'b0, "forwarding valid_b only");
        check(acc === 32'sd0, "acc unchanged when only valid_b is high");

        // 5. Active accumulation: both valids high
        apply_and_step(8'sd3, 8'sd4, 1'b1, 1'b1, 1'b0, "acc: 3 * 4 = 12");
        check(acc === 32'sd12, "acc = 12");

        apply_and_step(8'sd5, 8'sd6, 1'b1, 1'b1, 1'b0, "acc: + 5 * 6 = 42");
        check(acc === 32'sd42, "acc = 42");

        // 6. Signed values and negatives
        apply_and_step(-8'sd7, 8'sd2, 1'b1, 1'b1, 1'b0, "acc: + (-7 * 2) = 28");
        check(acc === 32'sd28, "acc = 28");

        apply_and_step(-8'sd4, -8'sd5, 1'b1, 1'b1, 1'b0, "acc: + (-4 * -5) = 48");
        check(acc === 32'sd48, "acc = 48");

        // 7. Clear assertion during operation
        apply_and_step(8'sd10, 8'sd10, 1'b1, 1'b1, 1'b1, "clear asserted during valid cycle");
        check(a_out === 0 && b_out === 0 && valid_a_out === 0 && valid_b_out === 0 && acc === 0,
              "clear synchronous flush");

        // Resume after clear without reset
        apply_and_step(8'sd2, 8'sd3, 1'b1, 1'b1, 1'b0, "post-clear accumulate: 2 * 3 = 6");
        check(acc === 32'sd6, "acc restarted correctly after clear");

        // 8. Extreme corner cases
        apply_and_step(-8'sd128, -8'sd128, 1'b1, 1'b1, 1'b0, "extreme min*min: (-128)*(-128)");
        apply_and_step(-8'sd128,  8'sd127, 1'b1, 1'b1, 1'b0, "extreme min*max: (-128)*(127)");
        apply_and_step( 8'sd127,  8'sd127, 1'b1, 1'b1, 1'b0, "extreme max*max: (127)*(127)");

        // 9. Randomized testing stream
        for (step_i = 0; step_i < 200; step_i = step_i + 1) begin
            rand_a  = $dist_uniform(seed, -128, 127);
            rand_b  = $dist_uniform(seed, -128, 127);
            rand_va = (step_i % 4 != 0); // 75% valid A
            rand_vb = (step_i % 3 != 0); // ~67% valid B
            // Occasional clear pulse every ~50 steps
            apply_and_step(rand_a, rand_b, rand_va, rand_vb, (step_i == 75 || step_i == 150), "random step");
        end

        // Final result reporting
        if (errors == 0) begin
            $display("PROCESSING_ELEMENT TEST PASSED: errors=0, tests=%0d", tests);
        end else begin
            $display("PROCESSING_ELEMENT TEST FAILED: %0d errors out of %0d tests", errors, tests);
        end
        $finish;
    end

endmodule
