`timescale 1ns/1ps

// SysMAC: Systolic Array Matrix Multiplication Accelerator
// Module: processing_element
// Author: Abhishek
//
// Description:
//   Output-stationary processing element (PE).
//   Contains:
//     - Pass-through registers for operand A (horizontal) and operand B (vertical)
//     - Pass-through registers for control/valid flags valid_a and valid_b
//     - Signed multiply-accumulate unit with 32-bit accumulator
//
// Behavior:
//   Synchronous active-high reset or clear synchronously clears all pipeline
//   registers (a_out, b_out, valid_a_out, valid_b_out) and the accumulator (acc) to 0.
//   Otherwise:
//     - Operands and valid flags are registered and forwarded every clock cycle:
//       a_out <= a_in, b_out <= b_in, valid_a_out <= valid_a_in, valid_b_out <= valid_b_in.
//     - When both valid_a_in and valid_b_in are asserted, acc <= acc + (a_in * b_in).
//     - When either valid flag is low, acc maintains its previous value.

module processing_element #(
    parameter integer DATA_WIDTH = 8,
    parameter integer ACC_WIDTH  = 32
) (
    input  wire                          clk,
    input  wire                          reset,        // Synchronous active-high reset
    input  wire                          clear,        // Synchronous active-high clear
    input  wire signed [DATA_WIDTH-1:0]  a_in,         // Horizontal operand input
    input  wire signed [DATA_WIDTH-1:0]  b_in,         // Vertical operand input
    input  wire                          valid_a_in,   // Horizontal valid flag input
    input  wire                          valid_b_in,   // Vertical valid flag input
    output reg  signed [DATA_WIDTH-1:0]  a_out,        // Registered horizontal operand output
    output reg  signed [DATA_WIDTH-1:0]  b_out,        // Registered vertical operand output
    output reg                           valid_a_out,  // Registered horizontal valid flag output
    output reg                           valid_b_out,  // Registered vertical valid flag output
    output reg  signed [ACC_WIDTH-1:0]   acc           // Output-stationary accumulator
);

    wire signed [2*DATA_WIDTH-1:0] product = a_in * b_in;

    always @(posedge clk) begin
        if (reset || clear) begin
            a_out       <= {DATA_WIDTH{1'b0}};
            b_out       <= {DATA_WIDTH{1'b0}};
            valid_a_out <= 1'b0;
            valid_b_out <= 1'b0;
            acc         <= {ACC_WIDTH{1'b0}};
        end else begin
            // Unconditional pipeline forwarding
            a_out       <= a_in;
            b_out       <= b_in;
            valid_a_out <= valid_a_in;
            valid_b_out <= valid_b_in;

            // Conditional accumulation: gated by both valid flags
            if (valid_a_in && valid_b_in) begin
                acc <= acc + product;
            end
        end
    end

endmodule
