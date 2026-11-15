`timescale 1ns/1ps

// SysMAC: Systolic Array Matrix Multiplication Accelerator
// Testbench: tb_input_scheduler
// Author: Piyush
//
// Self-checking. input_scheduler is combinational, so each check sets the
// inputs, waits #1 and compares all four outputs.
//   1. Demo matrices A=[[1,2,3],[4,5,6],[7,8,9]], B=[[9,8,7],[6,5,4],[3,2,1]],
//      run=1, t=0..6 against the hand-written table from the spec.
//   2. run=0 at every t (0..7): all outputs 0.
//   3. t=7 (outside the compute window) with run=1: all outputs 0.
//   4. Random signed matrices, t=0..7, run=0/1, against a model written
//      straight from the port_spec formulas.
// Prints PASSED or FAILED at the end.

module tb_input_scheduler;

    reg         run   = 0;
    reg  [2:0]  t     = 0;
    reg  [71:0] a_mat = 0;
    reg  [71:0] b_mat = 0;
    wire [23:0] a_in_flat, b_in_flat;
    wire [2:0]  valid_a_in, valid_b_in;

    integer errors = 0;
    integer tests  = 0;

    input_scheduler uut (
        .run       (run),
        .t         (t),
        .a_mat     (a_mat),
        .b_mat     (b_mat),
        .a_in_flat (a_in_flat),
        .b_in_flat (b_in_flat),
        .valid_a_in(valid_a_in),
        .valid_b_in(valid_b_in)
    );

    // Pack a 3x3 matrix given row-major as 9 bytes m00..m22.
    function [71:0] pack;
        input [7:0] m00, m01, m02, m10, m11, m12, m20, m21, m22;
        pack = {m22, m21, m20, m12, m11, m10, m02, m01, m00};
    endfunction

    // Compare outputs to expected values. e_a*/e_b* are the edge bytes for
    // row/col 0,1,2; a position with valid=0 must also carry data 0.
    task check;
        input [2:0] e_va;
        input [7:0] e_a0, e_a1, e_a2;
        input [2:0] e_vb;
        input [7:0] e_b0, e_b1, e_b2;
        input [255:0] tag;
        reg   [23:0] e_af, e_bf;
        begin
            e_af = {e_a2, e_a1, e_a0};
            e_bf = {e_b2, e_b1, e_b0};
            #1;
            tests = tests + 1;
            if (valid_a_in !== e_va || a_in_flat !== e_af ||
                valid_b_in !== e_vb || b_in_flat !== e_bf) begin
                errors = errors + 1;
                $display("FAIL: %0s (run=%0d t=%0d)", tag, run, t);
                $display("      A valid=%b data=%h  expected valid=%b data=%h",
                         valid_a_in, a_in_flat, e_va, e_af);
                $display("      B valid=%b data=%h  expected valid=%b data=%h",
                         valid_b_in, b_in_flat, e_vb, e_bf);
            end
        end
    endtask

    // Reference model built from the spec formulas.
    reg [23:0] m_af, m_bf;
    reg [2:0]  m_va, m_vb;
    integer    mi, mk;
    task model;
        begin
            m_af = 0; m_bf = 0; m_va = 0; m_vb = 0;
            for (mi = 0; mi < 3; mi = mi + 1) begin
                mk = t - mi;
                if (run && mk >= 0 && mk <= 2) begin
                    m_va[mi] = 1'b1;
                    m_af[mi*8 +: 8] = a_mat[(mi*3 + mk)*8 +: 8];
                    m_vb[mi] = 1'b1;
                    m_bf[mi*8 +: 8] = b_mat[(mk*3 + mi)*8 +: 8];
                end
            end
        end
    endtask

    integer seed = 12;
    integer job, step, b;

    initial begin
        $dumpfile("sim/input_scheduler_waveform.vcd");
        $dumpvars(0, tb_input_scheduler);

        a_mat = pack(8'd1, 8'd2, 8'd3, 8'd4, 8'd5, 8'd6, 8'd7, 8'd8, 8'd9);
        b_mat = pack(8'd9, 8'd8, 8'd7, 8'd6, 8'd5, 8'd4, 8'd3, 8'd2, 8'd1);

        // 1. Demo table, run=1.          A valid, rows 0..2     B valid, cols 0..2
        run = 1;
        t = 0; check(3'b001, 8'd1, 8'd0, 8'd0,  3'b001, 8'd9, 8'd0, 8'd0, "demo t=0");
        t = 1; check(3'b011, 8'd2, 8'd4, 8'd0,  3'b011, 8'd6, 8'd8, 8'd0, "demo t=1");
        t = 2; check(3'b111, 8'd3, 8'd5, 8'd7,  3'b111, 8'd3, 8'd5, 8'd7, "demo t=2");
        t = 3; check(3'b110, 8'd0, 8'd6, 8'd8,  3'b110, 8'd0, 8'd2, 8'd4, "demo t=3");
        t = 4; check(3'b100, 8'd0, 8'd0, 8'd9,  3'b100, 8'd0, 8'd0, 8'd1, "demo t=4");
        t = 5; check(3'b000, 8'd0, 8'd0, 8'd0,  3'b000, 8'd0, 8'd0, 8'd0, "demo t=5");
        t = 6; check(3'b000, 8'd0, 8'd0, 8'd0,  3'b000, 8'd0, 8'd0, 8'd0, "demo t=6");

        // 3. t=7 is outside the window even with run=1.
        t = 7; check(3'b000, 8'd0, 8'd0, 8'd0,  3'b000, 8'd0, 8'd0, 8'd0, "demo t=7");

        // 2. run=0 blanks everything at every t.
        run = 0;
        for (step = 0; step < 8; step = step + 1) begin
            t = step;
            check(3'b000, 8'd0, 8'd0, 8'd0,  3'b000, 8'd0, 8'd0, 8'd0, "run=0");
        end

        // 4. Random signed matrices against the model.
        for (job = 0; job < 200; job = job + 1) begin
            for (b = 0; b < 9; b = b + 1) begin
                a_mat[b*8 +: 8] = $dist_uniform(seed, -128, 127);
                b_mat[b*8 +: 8] = $dist_uniform(seed, -128, 127);
            end
            for (step = 0; step < 16; step = step + 1) begin
                run = step[3];
                t   = step[2:0];
                model;
                check(m_va, m_af[7:0], m_af[15:8], m_af[23:16],
                      m_vb, m_bf[7:0], m_bf[15:8], m_bf[23:16], "random");
            end
        end

        $display("tb_input_scheduler: %0d checks, errors=%0d", tests, errors);
        if (errors == 0)
            $display("PASSED");
        else
            $display("FAILED");
        $finish;
    end

endmodule
