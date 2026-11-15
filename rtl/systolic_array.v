// SysMAC: Systolic Array Matrix Multiplication Accelerator
// Parameterized N x N Output-Stationary Systolic Array
//
// Author: Sushant Yadav
// Module: systolic_array
//
// Description:
//   Instantiates an N x N 2D mesh of Processing Elements (PEs) for matrix
//   multiplication C = A x B. Matrix A enters from the left edge and propagates
//   horizontally across columns. Matrix B enters from the top edge and propagates
//   vertically down rows. Each PE(i,j) locally accumulates the scalar product
//   for output element C[i][j].
//
//   Operands and valid flags are registered inside each PE at every rising
//   clock edge. Forwarding occurs unconditionally, while accumulation at each
//   PE is gated by (valid_a && valid_b).
//
//   Includes backward-compatible wrapper 'systolic_array_3x3' delegating to
//   systolic_array with N=3.

`timescale 1ns/1ps

module systolic_array #(
    parameter integer N          = 3,   // Array grid dimension (N x N)
    parameter integer DATA_WIDTH = 8,   // Signed input operand width
    parameter integer ACC_WIDTH  = 32   // Signed accumulator width
)(
    input  wire                               clk,
    input  wire                               reset,        // Synchronous active-high reset
    input  wire                               clear,        // Synchronous active-high accumulator & pipeline clear
    input  wire [N*DATA_WIDTH-1:0]            a_in_flat,    // Boundary A inputs (row i at [i*DATA_WIDTH +: DATA_WIDTH])
    input  wire [N*DATA_WIDTH-1:0]            b_in_flat,    // Boundary B inputs (col j at [j*DATA_WIDTH +: DATA_WIDTH])
    input  wire [N-1:0]                       valid_a_in,   // Boundary valid A flags (bit i for row i)
    input  wire [N-1:0]                       valid_b_in,   // Boundary valid B flags (bit j for col j)
    output wire [N*N*ACC_WIDTH-1:0]           c_flat        // Flattened accumulator outputs (PE(i,j) at [(i*N+j)*ACC_WIDTH +: ACC_WIDTH])
);

    // 2D internal interconnect grids:
    // a_data[r][c] is the A operand entering PE(r,c) horizontally from the left.
    // a_data[r][0] connects to the left boundary input a_in_flat[r].
    // a_data[r][c+1] is driven by PE(r,c) registered output a_out.
    //
    // b_data[r][c] is the B operand entering PE(r,c) vertically from the top.
    // b_data[0][c] connects to the top boundary input b_in_flat[c].
    // b_data[r+1][c] is driven by PE(r,c) registered output b_out.
    wire signed [DATA_WIDTH-1:0] a_data  [0:N-1][0:N];
    wire signed [DATA_WIDTH-1:0] b_data  [0:N][0:N-1];
    wire                         a_valid [0:N-1][0:N];
    wire                         b_valid [0:N][0:N-1];

    genvar r, c;

    // Boundary Input Assignments
    generate
        for (r = 0; r < N; r = r + 1) begin: GEN_A_BOUNDARY
            assign a_data[r][0]  = a_in_flat[r*DATA_WIDTH +: DATA_WIDTH];
            assign a_valid[r][0] = valid_a_in[r];
        end
        for (c = 0; c < N; c = c + 1) begin: GEN_B_BOUNDARY
            assign b_data[0][c]  = b_in_flat[c*DATA_WIDTH +: DATA_WIDTH];
            assign b_valid[0][c] = valid_b_in[c];
        end
    endgenerate

    // N x N Processing Element Grid
    generate
        for (r = 0; r < N; r = r + 1) begin: GEN_ROW
            for (c = 0; c < N; c = c + 1) begin: GEN_COL
                wire signed [ACC_WIDTH-1:0] pe_acc;

                processing_element #(
                    .DATA_WIDTH(DATA_WIDTH),
                    .ACC_WIDTH (ACC_WIDTH)
                ) u_pe (
                    .clk        (clk),
                    .reset      (reset),
                    .clear      (clear),
                    .a_in       (a_data[r][c]),
                    .b_in       (b_data[r][c]),
                    .valid_a_in (a_valid[r][c]),
                    .valid_b_in (b_valid[r][c]),
                    .a_out      (a_data[r][c+1]),
                    .b_out      (b_data[r+1][c]),
                    .valid_a_out(a_valid[r][c+1]),
                    .valid_b_out(b_valid[r+1][c]),
                    .acc        (pe_acc)
                );

                assign c_flat[(r*N + c)*ACC_WIDTH +: ACC_WIDTH] = pe_acc;
            end
        end
    endgenerate

endmodule


// Backward-compatible wrapper for 3x3 systolic array architecture
// Delegates directly to systolic_array #(N=3) without logic duplication.
module systolic_array_3x3 (
    input  wire         clk,
    input  wire         reset,
    input  wire         clear,
    input  wire [23:0]  a_in_flat,     // 3 rows x 8 bits
    input  wire [23:0]  b_in_flat,     // 3 cols x 8 bits
    input  wire [2:0]   valid_a_in,    // bit i = row i
    input  wire [2:0]   valid_b_in,    // bit j = col j
    output wire [287:0] c_flat         // 9 PEs x 32 bits
);

    systolic_array #(
        .N         (3),
        .DATA_WIDTH(8),
        .ACC_WIDTH (32)
    ) u_systolic_array (
        .clk        (clk),
        .reset      (reset),
        .clear      (clear),
        .a_in_flat  (a_in_flat),
        .b_in_flat  (b_in_flat),
        .valid_a_in (valid_a_in),
        .valid_b_in (valid_b_in),
        .c_flat     (c_flat)
    );

endmodule
