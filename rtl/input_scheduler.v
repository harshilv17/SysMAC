`timescale 1ns/1ps

// SysMAC: Systolic Array Matrix Multiplication Accelerator
// Module: input_scheduler
// Author: Piyush
//
// Description:
//   Purely combinational. Produces the skewed edge inputs of the 3x3 array
//   for compute cycle t (0..6). The controller only supplies t; the skew
//   lives here.
//     Row i: k = t - i, valid if run && 0 <= k <= 2, data A[i][k]
//     Col j: k = t - j, valid if run && 0 <= k <= 2, data B[k][j]
//   When run=0 or k is out of range, data is 0 and valid is 0.
//   A[i][k] = a_mat[(i*3+k)*8 +: 8], B[k][j] = b_mat[(k*3+j)*8 +: 8]
//   Row i edge input = a_in_flat[i*8 +: 8], col j = b_in_flat[j*8 +: 8].

module input_scheduler (
    input  wire        run,
    input  wire [2:0]  t,
    input  wire [71:0] a_mat,
    input  wire [71:0] b_mat,
    output reg  [23:0] a_in_flat,
    output reg  [23:0] b_in_flat,
    output reg  [2:0]  valid_a_in,
    output reg  [2:0]  valid_b_in
);

    integer n;   // row index i for A, column index j for B
    integer k;   // signed: t - n can be negative

    always @(*) begin
        a_in_flat  = 24'd0;
        b_in_flat  = 24'd0;
        valid_a_in = 3'b000;
        valid_b_in = 3'b000;
        for (n = 0; n < 3; n = n + 1) begin
            k = t - n;
            if (run && k >= 0 && k <= 2) begin
                valid_a_in[n]       = 1'b1;
                a_in_flat[n*8 +: 8] = a_mat[(n*3 + k)*8 +: 8];   // A[n][k]
                valid_b_in[n]       = 1'b1;
                b_in_flat[n*8 +: 8] = b_mat[(k*3 + n)*8 +: 8];   // B[k][n]
            end
        end
    end

endmodule
