`timescale 1ns/1ps

module tb_systolic_controller;
    reg clk = 0, reset = 1, start = 0;
    wire load, clear, run, capture, done;
    wire [2:0] t;
    integer i, errors = 0;

    systolic_controller uut (.clk(clk), .reset(reset), .start(start),
        .load(load), .clear(clear), .run(run), .capture(capture),
        .done(done), .t(t));

    always #5 clk = ~clk;

    task check(input cond, input [255:0] msg);
        if (!cond) begin
            errors = errors + 1;
            $display("FAIL: %0s at %0t", msg, $time);
        end
    endtask

    initial begin
        $dumpfile("sim/ctrl_waveform.vcd");
        $dumpvars(0, tb_systolic_controller);

        repeat (2) @(posedge clk);
        #1 reset = 0;
        check(!load && !run && !done, "idle outputs low");

        // pulse start for one cycle
        @(negedge clk) start = 1;
        @(negedge clk) start = 0;

        // LOAD: one cycle
        check(load && clear && !run, "load state");
        // COMPUTE: 7 cycles, t = 0..6
        for (i = 0; i < 7; i = i + 1) begin
            @(negedge clk);
            check(run && !load && t == i, "compute t");
        end
        @(negedge clk) check(capture && !run, "capture state");
        @(negedge clk) check(done && !capture, "done state");
        @(negedge clk) check(!done && !run, "back to idle");

        if (errors == 0) $display("CONTROLLER TEST PASSED");
        else $display("CONTROLLER TEST FAILED: %0d errors", errors);
        $finish;
    end
endmodule
