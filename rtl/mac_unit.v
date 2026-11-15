`timescale 1ns/1ps

// SysMAC: Systolic Array Matrix Multiplication Accelerator
// Module: mac_unit
// Author: Abhishek
//
// Description:
//   Signed multiply-accumulate unit.
//   Synchronous active-high reset clears the accumulator to 0.
//   On each clock posedge when not in reset, it adds the signed product (a * b)
//   to the accumulator: acc <= acc + (a * b).

module mac_unit #(
    parameter integer DATA_WIDTH = 8,
    parameter integer ACC_WIDTH  = 32
) (
    input  wire                          clk,
    input  wire                          reset,
    input  wire signed [DATA_WIDTH-1:0]  a,
    input  wire signed [DATA_WIDTH-1:0]  b,
    output reg  signed [ACC_WIDTH-1:0]   acc
);

    wire signed [2*DATA_WIDTH-1:0] product = a * b;

    always @(posedge clk) begin
        if (reset) begin
            acc <= {ACC_WIDTH{1'b0}};
        end else begin
            acc <= acc + product;
        end
    end

endmodule
