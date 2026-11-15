`timescale 1ns/1ps

// SysMAC: Systolic Array Matrix Multiplication Accelerator
// Module: output_registers
// Author: Piyush
//
// Description:
//   Holds the 3x3 result matrix (9 x 32 bits).
//   On a posedge with capture=1, c_flat <= c_in. Otherwise c_flat holds.
//   Synchronous active-high reset clears c_flat to 0.
//   C[i][j] = c_flat[(i*3+j)*32 +: 32]

module output_registers (
    input  wire         clk,
    input  wire         reset,
    input  wire         capture,
    input  wire [287:0] c_in,
    output reg  [287:0] c_flat
);

    always @(posedge clk) begin
        if (reset)
            c_flat <= 288'd0;
        else if (capture)
            c_flat <= c_in;
    end

endmodule
