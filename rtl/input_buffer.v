`timescale 1ns/1ps

// SysMAC: Systolic Array Matrix Multiplication Accelerator
// Module: input_buffer
// Author: Piyush
//
// Description:
//   Holds the two input matrices for one job.
//   On a posedge with load=1, a_flat and b_flat are latched into a_mat and
//   b_mat. The outputs then hold until the next load.
//   Synchronous active-high reset clears both to 0.
//   Packing is row-major (docs/port_spec.md):
//     A[i][k] = a_mat[(i*3+k)*8 +: 8], B[k][j] = b_mat[(k*3+j)*8 +: 8]

module input_buffer (
    input  wire        clk,
    input  wire        reset,
    input  wire        load,
    input  wire [71:0] a_flat,
    input  wire [71:0] b_flat,
    output reg  [71:0] a_mat,
    output reg  [71:0] b_mat
);

    always @(posedge clk) begin
        if (reset) begin
            a_mat <= 72'd0;
            b_mat <= 72'd0;
        end else if (load) begin
            a_mat <= a_flat;
            b_mat <= b_flat;
        end
    end

endmodule
