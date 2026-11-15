`timescale 1ns/1ps

// SysMAC: Systolic Array Matrix Multiplication Accelerator
// Module: tb_systolic_array
// Author: Sushant Yadav
//
// Description:
//   Self-checking verification testbench for the parameterized N x N systolic array
//   (`systolic_array`) integrating the actual `processing_element` and `mac_unit`
//   modules authored by Abhishek.
//
// Test Coverage:
//   1. Reset and Clear Verification (Requirement C):
//      - Active-high synchronous reset during active operation.
//      - Active-high synchronous clear during active operation.
//      - Pipeline register flush and accumulator return to zero.
//      - Deassertion behavior and post-clear/reset accumulation.
//      - Zero-accumulation during invalid cycles.
//   2. Validity Propagation Verification (Requirement B):
//      - All 4 combinations of valid flags:
//        (a) valid_a=1, valid_b=0 (forwarding only, acc unchanged)
//        (b) valid_a=0, valid_b=1 (forwarding only, acc unchanged)
//        (c) valid_a=0, valid_b=0 (idle forwarding, acc unchanged)
//        (d) valid_a=1, valid_b=1 (accumulation enabled)
//      - Multi-hop propagation through interior PEs.
//   3. Signed Arithmetic and Edge Cases (Requirement E):
//      - Positive operands (+127 * +127)
//      - Negative operands (-128 * -128)
//      - Mixed signs (-128 * +127, +127 * -128)
//      - Zero operand gating (0 * x = 0, x * 0 = 0)
//      - Extended multi-cycle accumulation beyond 16-bit range (> 32767 and < -32768)
//        to verify full signed 32-bit accumulator width and sign-extension.
//   4. Parameterized N=2 Verification (Requirement D):
//      - Identity matrix multiplication (A * I = A)
//      - Deterministic ramp matrices
//      - Signed negative matrices
//      - Extreme boundary limits
//      - Zero matrix tests
//      - 25 pseudo-random 2x2 matrix multiplications verified against independent
//        mathematical matrix multiplication model.
//      - Synchronous clear verified between all jobs.
//   5. Parameterized N=4 Verification (Requirement D):
//      - 4x4 Identity matrix
//      - 4x4 Ramp and reverse ramp
//      - 4x4 Signed matrix
//      - 4x4 Extreme limits (all -128 * all -128, all -128 * all 127, all 127 * all 127)
//      - 4x4 Zero matrix
//      - 25 pseudo-random 4x4 matrix multiplications verified against independent
//        mathematical matrix multiplication model.
//      - Synchronous clear verified between all jobs.
//   6. Shared Golden-Vector Regression N=3 (Requirement A):
//      - Full regression using `sim/vectors/trace_in.hex` and `sim/vectors/trace_c.hex`.
//      - 112 jobs x 7 cycles = 784 cycles.
//      - Cycle-by-cycle comparison of all 9 PE accumulators (7,056 comparisons).
//      - Synchronous clear verified between all 112 jobs (1,008 checks).
//   7. Backward-Compatible Wrapper Verification (`systolic_array_3x3`):
//      - Validates wrapper instantiation and delegation to parameterized module.

module tb_systolic_array;

    // -------------------------------------------------------------------------
    // Clock Generation
    // -------------------------------------------------------------------------
    reg clk = 0;
    always #5 clk = ~clk; // 10 ns clock period (100 MHz)

    // -------------------------------------------------------------------------
    // Error and Statistics Tracking
    // -------------------------------------------------------------------------
    integer total_tests        = 0;
    integer total_errors       = 0;
    integer total_cycles       = 0;
    integer golden_jobs        = 0;
    integer golden_comparisons = 0;
    integer golden_mismatches  = 0;

    reg [1023:0] dump_file;

    // -------------------------------------------------------------------------
    // Check Task Helpers
    // -------------------------------------------------------------------------
    task check(input cond, input [511:0] msg);
        begin
            total_tests = total_tests + 1;
            if (!cond) begin
                total_errors = total_errors + 1;
                $display("ERROR at %0t ps: %0s", $time, msg);
            end
        end
    endtask

    task check_signed_eq(
        input signed [31:0] act,
        input signed [31:0] exp,
        input [511:0]       msg
    );
        begin
            total_tests = total_tests + 1;
            if (act !== exp) begin
                total_errors = total_errors + 1;
                $display("ERROR at %0t ps: %0s | Expected: %0d (0x%08h), Got: %0d (0x%08h)",
                         $time, msg, exp, exp, act, act);
            end
        end
    endtask

    // -------------------------------------------------------------------------
    // UUT 1: Parameterized N=3 Systolic Array
    // -------------------------------------------------------------------------
    reg         n3_reset      = 1;
    reg         n3_clear      = 0;
    reg  [23:0] n3_a_in_flat  = 24'd0;
    reg  [23:0] n3_b_in_flat  = 24'd0;
    reg  [2:0]  n3_valid_a_in = 3'd0;
    reg  [2:0]  n3_valid_b_in = 3'd0;
    wire [287:0] n3_c_flat;

    systolic_array #(
        .N         (3),
        .DATA_WIDTH(8),
        .ACC_WIDTH (32)
    ) uut_n3 (
        .clk        (clk),
        .reset      (n3_reset),
        .clear      (n3_clear),
        .a_in_flat  (n3_a_in_flat),
        .b_in_flat  (n3_b_in_flat),
        .valid_a_in (n3_valid_a_in),
        .valid_b_in (n3_valid_b_in),
        .c_flat     (n3_c_flat)
    );

    // -------------------------------------------------------------------------
    // UUT 2: Parameterized N=2 Systolic Array
    // -------------------------------------------------------------------------
    reg         n2_reset      = 1;
    reg         n2_clear      = 0;
    reg  [15:0] n2_a_in_flat  = 16'd0;
    reg  [15:0] n2_b_in_flat  = 16'd0;
    reg  [1:0]  n2_valid_a_in = 2'd0;
    reg  [1:0]  n2_valid_b_in = 2'd0;
    wire [127:0] n2_c_flat;

    systolic_array #(
        .N         (2),
        .DATA_WIDTH(8),
        .ACC_WIDTH (32)
    ) uut_n2 (
        .clk        (clk),
        .reset      (n2_reset),
        .clear      (n2_clear),
        .a_in_flat  (n2_a_in_flat),
        .b_in_flat  (n2_b_in_flat),
        .valid_a_in (n2_valid_a_in),
        .valid_b_in (n2_valid_b_in),
        .c_flat     (n2_c_flat)
    );

    // -------------------------------------------------------------------------
    // UUT 3: Parameterized N=4 Systolic Array
    // -------------------------------------------------------------------------
    reg         n4_reset      = 1;
    reg         n4_clear      = 0;
    reg  [31:0] n4_a_in_flat  = 32'd0;
    reg  [31:0] n4_b_in_flat  = 32'd0;
    reg  [3:0]  n4_valid_a_in = 4'd0;
    reg  [3:0]  n4_valid_b_in = 4'd0;
    wire [511:0] n4_c_flat;

    systolic_array #(
        .N         (4),
        .DATA_WIDTH(8),
        .ACC_WIDTH (32)
    ) uut_n4 (
        .clk        (clk),
        .reset      (n4_reset),
        .clear      (n4_clear),
        .a_in_flat  (n4_a_in_flat),
        .b_in_flat  (n4_b_in_flat),
        .valid_a_in (n4_valid_a_in),
        .valid_b_in (n4_valid_b_in),
        .c_flat     (n4_c_flat)
    );

    // -------------------------------------------------------------------------
    // UUT 4: Backward-Compatible systolic_array_3x3 Wrapper
    // -------------------------------------------------------------------------
    reg         wrap_reset      = 1;
    reg         wrap_clear      = 0;
    reg  [23:0] wrap_a_in_flat  = 24'd0;
    reg  [23:0] wrap_b_in_flat  = 24'd0;
    reg  [2:0]  wrap_valid_a_in = 3'd0;
    reg  [2:0]  wrap_valid_b_in = 3'd0;
    wire [287:0] wrap_c_flat;

    systolic_array_3x3 uut_wrap (
        .clk        (clk),
        .reset      (wrap_reset),
        .clear      (wrap_clear),
        .a_in_flat  (wrap_a_in_flat),
        .b_in_flat  (wrap_b_in_flat),
        .valid_a_in (wrap_valid_a_in),
        .valid_b_in (wrap_valid_b_in),
        .c_flat     (wrap_c_flat)
    );

    // -------------------------------------------------------------------------
    // Memories for Shared Golden Vectors (N=3)
    // -------------------------------------------------------------------------
    reg [55:0]  trace_in_mem [0:783];
    reg [287:0] trace_c_mem  [0:783];

    // =========================================================================
    // Test Suite 1: Synchronous Reset and Synchronous Clear Verification
    // =========================================================================
    task test_reset_and_clear;
        integer pe_idx;
        begin
            $display("[TEST SUITE 1] Verifying Synchronous Reset and Synchronous Clear...");

            // 1. Initial State: reset active
            @(negedge clk);
            n3_reset      = 1;
            n3_clear      = 0;
            n3_a_in_flat  = 24'h050505;
            n3_b_in_flat  = 24'h060606;
            n3_valid_a_in = 3'b111;
            n3_valid_b_in = 3'b111;
            @(posedge clk);
            #1;
            check(n3_c_flat === 288'd0, "Reset holds all accumulators at zero");

            // 2. Release reset and accumulate some values
            @(negedge clk);
            n3_reset      = 0;
            n3_clear      = 0;
            n3_a_in_flat  = {8'sd3, 8'sd2, 8'sd4};
            n3_b_in_flat  = {8'sd5, 8'sd7, 8'sd6};
            n3_valid_a_in = 3'b001; // PE(0,0) receives valid inputs
            n3_valid_b_in = 3'b001;
            @(posedge clk);
            #1;
            check(n3_c_flat[31:0] === 32'sd24, "PE(0,0) accumulated 4 * 6 = 24");

            // 3. Assert Synchronous Reset mid-operation
            @(negedge clk);
            n3_reset      = 1;
            n3_clear      = 0;
            @(posedge clk);
            #1;
            check(n3_c_flat === 288'd0, "Synchronous reset flushes all accumulators to 0");

            // 4. Deassert reset with invalid inputs -> must remain zero
            @(negedge clk);
            n3_reset      = 0;
            n3_valid_a_in = 3'b000;
            n3_valid_b_in = 3'b000;
            @(posedge clk);
            #1;
            check(n3_c_flat === 288'd0, "Accumulators remain 0 after reset release with valid=0");

            // 5. Accumulate again to test Clear
            @(negedge clk);
            n3_a_in_flat  = {8'sd0, 8'sd0, 8'sd10};
            n3_b_in_flat  = {8'sd0, 8'sd0, 8'sd5};
            n3_valid_a_in = 3'b001;
            n3_valid_b_in = 3'b001;
            @(posedge clk);
            #1;
            check(n3_c_flat[31:0] === 32'sd50, "PE(0,0) accumulated 10 * 5 = 50");

            // 6. Assert Synchronous Clear
            @(negedge clk);
            n3_clear = 1;
            @(posedge clk);
            #1;
            check(n3_c_flat === 288'd0, "Synchronous clear flushes all accumulators to 0");

            // 7. Verify pipeline forwarding registers were also cleared by Clear
            @(negedge clk);
            n3_clear      = 0;
            n3_valid_a_in = 3'b000;
            n3_valid_b_in = 3'b000;
            @(posedge clk);
            #1;
            check(n3_c_flat === 288'd0, "Accumulators remain 0 after clear release");

            // 8. Test Concurrent Reset and Clear
            @(negedge clk);
            n3_reset      = 1;
            n3_clear      = 1;
            n3_a_in_flat  = 24'hFFFFFF;
            n3_b_in_flat  = 24'hFFFFFF;
            n3_valid_a_in = 3'b111;
            n3_valid_b_in = 3'b111;
            @(posedge clk);
            #1;
            check(n3_c_flat === 288'd0, "Concurrent reset and clear holds all accumulators at 0");

            @(negedge clk);
            n3_reset      = 0;
            n3_clear      = 0;
            n3_valid_a_in = 3'b000;
            n3_valid_b_in = 3'b000;
            @(posedge clk);
            #1;
            $display("[TEST SUITE 1] Synchronous Reset and Clear PASSED.");
        end
    endtask

    // =========================================================================
    // Test Suite 2: Independent Validity Propagation Verification
    // =========================================================================
    task test_validity_propagation;
        begin
            $display("[TEST SUITE 2] Verifying Independent Validity Propagation (All 4 Combinations)...");

            // Clear array
            @(negedge clk);
            n3_reset = 0;
            n3_clear = 1;
            @(posedge clk);
            #1;
            @(negedge clk);
            n3_clear = 0;

            // -----------------------------------------------------------------
            // Combination 1: valid_a = 1, valid_b = 0
            // -----------------------------------------------------------------
            @(negedge clk);
            n3_a_in_flat  = {8'sd0, 8'sd0, 8'sd42}; // Row 0 receives A=42
            n3_b_in_flat  = {8'sd0, 8'sd0, 8'sd10}; // Col 0 receives B=10
            n3_valid_a_in = 3'b001;                 // Valid A
            n3_valid_b_in = 3'b000;                 // Invalid B
            @(posedge clk);
            #1;
            check(n3_c_flat[31:0] === 32'sd0, "Comb 1 (va=1, vb=0): PE(0,0) does NOT accumulate");

            // Cycle 2: A=42 and valid_a=1 forward into PE(0,1).
            // Provide valid B at Col 1. PE(0,1) should accumulate 42 * 2 = 84!
            @(negedge clk);
            n3_a_in_flat  = 24'd0;
            n3_b_in_flat  = {8'sd0, 8'sd2, 8'sd0};  // Col 1 receives B=2
            n3_valid_a_in = 3'b000;
            n3_valid_b_in = 3'b010;                 // Valid B on Col 1
            @(posedge clk);
            #1;
            check(n3_c_flat[(0*3 + 1)*32 +: 32] === 32'sd84,
                  "Comb 1 Forwarding: PE(0,1) accumulated forwarded A(42) * Col 1 B(2) = 84");

            // -----------------------------------------------------------------
            // Combination 2: valid_a = 0, valid_b = 1
            // -----------------------------------------------------------------
            // Clear array
            @(negedge clk);
            n3_clear = 1;
            @(posedge clk);
            #1;
            @(negedge clk);
            n3_clear = 0;

            @(negedge clk);
            n3_a_in_flat  = {8'sd0, 8'sd0, 8'sd15}; // Row 0 receives A=15
            n3_b_in_flat  = {8'sd0, 8'sd0, 8'sd25}; // Col 0 receives B=25
            n3_valid_a_in = 3'b000;                 // Invalid A
            n3_valid_b_in = 3'b001;                 // Valid B
            @(posedge clk);
            #1;
            check(n3_c_flat[31:0] === 32'sd0, "Comb 2 (va=0, vb=1): PE(0,0) does NOT accumulate");

            // Cycle 2: B=25 and valid_b=1 forward into PE(1,0).
            // Provide valid A at Row 1. PE(1,0) should accumulate 3 * 25 = 75!
            @(negedge clk);
            n3_a_in_flat  = {8'sd0, 8'sd3, 8'sd0};  // Row 1 receives A=3
            n3_b_in_flat  = 24'd0;
            n3_valid_a_in = 3'b010;                 // Valid A on Row 1
            n3_valid_b_in = 3'b000;
            @(posedge clk);
            #1;
            check(n3_c_flat[(1*3 + 0)*32 +: 32] === 32'sd75,
                  "Comb 2 Forwarding: PE(1,0) accumulated Row 1 A(3) * forwarded B(25) = 75");

            // -----------------------------------------------------------------
            // Combination 3: valid_a = 0, valid_b = 0
            // -----------------------------------------------------------------
            @(negedge clk);
            n3_a_in_flat  = {8'sd0, 8'sd50, 8'sd50};
            n3_b_in_flat  = {8'sd0, 8'sd50, 8'sd50};
            n3_valid_a_in = 3'b000;
            n3_valid_b_in = 3'b000;
            @(posedge clk);
            #1;
            check(n3_c_flat[(1*3 + 0)*32 +: 32] === 32'sd75,
                  "Comb 3 (va=0, vb=0): PE(1,0) maintains value, no accumulation");

            // -----------------------------------------------------------------
            // Combination 4: valid_a = 1, valid_b = 1
            // -----------------------------------------------------------------
            @(negedge clk);
            n3_a_in_flat  = {8'sd0, 8'sd0, 8'sd7};
            n3_b_in_flat  = {8'sd0, 8'sd0, 8'sd9};
            n3_valid_a_in = 3'b001;
            n3_valid_b_in = 3'b001;
            @(posedge clk);
            #1;
            check(n3_c_flat[31:0] === 32'sd63, "Comb 4 (va=1, vb=1): PE(0,0) accumulated 7 * 9 = 63");

            // Flush with clear
            @(negedge clk);
            n3_clear      = 1;
            n3_a_in_flat  = 24'd0;
            n3_b_in_flat  = 24'd0;
            n3_valid_a_in = 3'd0;
            n3_valid_b_in = 3'd0;
            @(posedge clk);
            #1;
            @(negedge clk);
            n3_clear = 0;

            $display("[TEST SUITE 2] Independent Validity Propagation PASSED.");
        end
    endtask

    // =========================================================================
    // Test Suite 3: Signed Arithmetic and Edge Cases Verification
    // =========================================================================
    task test_signed_and_edge_cases;
        integer k;
        begin
            $display("[TEST SUITE 3] Verifying Signed Arithmetic and Edge Cases...");

            // Reset array
            @(negedge clk);
            n3_clear      = 1;
            n3_a_in_flat  = 24'd0;
            n3_b_in_flat  = 24'd0;
            n3_valid_a_in = 3'd0;
            n3_valid_b_in = 3'd0;
            @(posedge clk);
            #1;
            @(negedge clk);
            n3_clear = 0;

            // 1. Positive * Positive: (+127) * (+127) = +16,129
            @(negedge clk);
            n3_a_in_flat  = {8'sd0, 8'sd0, 8'sd127};
            n3_b_in_flat  = {8'sd0, 8'sd0, 8'sd127};
            n3_valid_a_in = 3'b001;
            n3_valid_b_in = 3'b001;
            @(posedge clk);
            #1;
            check_signed_eq(n3_c_flat[31:0], 32'sd16129, "Max pos * Max pos: 127 * 127 = 16129");

            // 2. Negative * Negative: (-128) * (-128) = +16,384 -> acc = 16129 + 16384 = 32513
            @(negedge clk);
            n3_a_in_flat  = {8'sd0, 8'sd0, -8'sd128};
            n3_b_in_flat  = {8'sd0, 8'sd0, -8'sd128};
            @(posedge clk);
            #1;
            check_signed_eq(n3_c_flat[31:0], 32'sd32513, "Min neg * Min neg: (-128)*(-128) -> acc = 32513");

            // 3. Negative * Positive: (-128) * (+127) = -16,256 -> acc = 32513 - 16256 = 16257
            @(negedge clk);
            n3_a_in_flat  = {8'sd0, 8'sd0, -8'sd128};
            n3_b_in_flat  = {8'sd0, 8'sd0,  8'sd127};
            @(posedge clk);
            #1;
            check_signed_eq(n3_c_flat[31:0], 32'sd16257, "Min neg * Max pos: (-128)*(127) -> acc = 16257");

            // 4. Positive * Negative: (+127) * (-128) = -16,256 -> acc = 16257 - 16256 = 1
            @(negedge clk);
            n3_a_in_flat  = {8'sd0, 8'sd0,  8'sd127};
            n3_b_in_flat  = {8'sd0, 8'sd0, -8'sd128};
            @(posedge clk);
            #1;
            check_signed_eq(n3_c_flat[31:0], 32'sd1, "Max pos * Min neg: (127)*(-128) -> acc = 1");

            // 5. Zero Operands: 0 * 127 = 0, -128 * 0 = 0, 0 * 0 = 0
            @(negedge clk);
            n3_a_in_flat  = {8'sd0, 8'sd0,  8'sd0};
            n3_b_in_flat  = {8'sd0, 8'sd0,  8'sd127};
            @(posedge clk);
            #1;
            check_signed_eq(n3_c_flat[31:0], 32'sd1, "Zero operand A: 0 * 127 -> acc remains 1");

            @(negedge clk);
            n3_a_in_flat  = {8'sd0, 8'sd0, -8'sd128};
            n3_b_in_flat  = {8'sd0, 8'sd0,  8'sd0};
            @(posedge clk);
            #1;
            check_signed_eq(n3_c_flat[31:0], 32'sd1, "Zero operand B: -128 * 0 -> acc remains 1");

            // 6. Multi-Cycle Large Positive Accumulation (> 16-bit range: > 32767)
            @(negedge clk);
            n3_clear      = 1;
            n3_a_in_flat  = 24'd0;
            n3_b_in_flat  = 24'd0;
            n3_valid_a_in = 3'd0;
            n3_valid_b_in = 3'd0;
            @(posedge clk);
            #1;
            @(negedge clk);
            n3_clear      = 0;
            n3_a_in_flat  = {8'sd0, 8'sd0, -8'sd128};
            n3_b_in_flat  = {8'sd0, 8'sd0, -8'sd128};
            n3_valid_a_in = 3'b001;
            n3_valid_b_in = 3'b001;

            // Accumulate (-128 * -128 = 16384) 10 times -> expected 163,840 (0x00028000)
            for (k = 0; k < 10; k = k + 1) begin
                @(posedge clk);
            end
            #1;
            check_signed_eq(n3_c_flat[31:0], 32'sd163840,
                            "Large pos accumulation: 10 * 16384 = 163840 (>16-bit signed limit)");

            // 7. Multi-Cycle Negative Accumulation (< -16-bit range: < -32768)
            @(negedge clk);
            n3_clear      = 1;
            n3_a_in_flat  = 24'd0;
            n3_b_in_flat  = 24'd0;
            n3_valid_a_in = 3'd0;
            n3_valid_b_in = 3'd0;
            @(posedge clk);
            #1;
            @(negedge clk);
            n3_clear      = 0;
            n3_a_in_flat  = {8'sd0, 8'sd0, -8'sd128};
            n3_b_in_flat  = {8'sd0, 8'sd0,  8'sd127};
            n3_valid_a_in = 3'b001;
            n3_valid_b_in = 3'b001;

            // Accumulate (-128 * 127 = -16256) 10 times -> expected -162,560 (0xFFFD8000)
            for (k = 0; k < 10; k = k + 1) begin
                @(posedge clk);
            end
            #1;
            check_signed_eq(n3_c_flat[31:0], -32'sd162560,
                            "Large neg accumulation: 10 * (-16256) = -162560 (32-bit sign extension)");

            // Clear array
            @(negedge clk);
            n3_clear      = 1;
            n3_a_in_flat  = 24'd0;
            n3_b_in_flat  = 24'd0;
            n3_valid_a_in = 3'd0;
            n3_valid_b_in = 3'd0;
            @(posedge clk);
            #1;
            @(negedge clk);
            n3_clear = 0;

            $display("[TEST SUITE 3] Signed Arithmetic and Edge Cases PASSED.");
        end
    endtask

    // =========================================================================
    // Test Suite 4: Parameterized N=2 Array Verification
    // =========================================================================
    task run_n2_matmul(
        input signed [7:0] a00, input signed [7:0] a01,
        input signed [7:0] a10, input signed [7:0] a11,
        input signed [7:0] b00, input signed [7:0] b01,
        input signed [7:0] b10, input signed [7:0] b11,
        input [511:0] tag
    );
        reg signed [31:0] exp_c00, exp_c01, exp_c10, exp_c11;
        integer t, r, c, k;
        reg signed [7:0] cur_a, cur_b;
        reg              cur_va, cur_vb;
        begin
            // Mathematical matrix multiplication reference
            exp_c00 = (a00 * b00) + (a01 * b10);
            exp_c01 = (a00 * b01) + (a01 * b11);
            exp_c10 = (a10 * b00) + (a11 * b10);
            exp_c11 = (a10 * b01) + (a11 * b11);

            // Synchronous Clear before job
            @(negedge clk);
            n2_clear      = 1;
            n2_a_in_flat  = 16'd0;
            n2_b_in_flat  = 16'd0;
            n2_valid_a_in = 2'd0;
            n2_valid_b_in = 2'd0;
            @(posedge clk);
            #1;
            check(n2_c_flat === 128'd0, {tag, " [N=2 Clear Check]"});
            @(negedge clk);
            n2_clear = 0;

            // Compute window: 3*N - 2 = 4 cycles (t = 0..3)
            for (t = 0; t < 4; t = t + 1) begin
                @(negedge clk);
                // Schedule Row 0
                k = t - 0;
                if (k == 0) begin n2_valid_a_in[0] = 1'b1; n2_a_in_flat[7:0]   = a00; end
                else if (k == 1) begin n2_valid_a_in[0] = 1'b1; n2_a_in_flat[7:0]   = a01; end
                else begin n2_valid_a_in[0] = 1'b0; n2_a_in_flat[7:0]   = 8'd0; end

                // Schedule Row 1
                k = t - 1;
                if (k == 0) begin n2_valid_a_in[1] = 1'b1; n2_a_in_flat[15:8]  = a10; end
                else if (k == 1) begin n2_valid_a_in[1] = 1'b1; n2_a_in_flat[15:8]  = a11; end
                else begin n2_valid_a_in[1] = 1'b0; n2_a_in_flat[15:8]  = 8'd0; end

                // Schedule Col 0
                k = t - 0;
                if (k == 0) begin n2_valid_b_in[0] = 1'b1; n2_b_in_flat[7:0]   = b00; end
                else if (k == 1) begin n2_valid_b_in[0] = 1'b1; n2_b_in_flat[7:0]   = b10; end
                else begin n2_valid_b_in[0] = 1'b0; n2_b_in_flat[7:0]   = 8'd0; end

                // Schedule Col 1
                k = t - 1;
                if (k == 0) begin n2_valid_b_in[1] = 1'b1; n2_b_in_flat[15:8]  = b01; end
                else if (k == 1) begin n2_valid_b_in[1] = 1'b1; n2_b_in_flat[15:8]  = b11; end
                else begin n2_valid_b_in[1] = 1'b0; n2_b_in_flat[15:8]  = 8'd0; end

                @(posedge clk);
            end

            #1;
            // Verify final accumulators
            check_signed_eq(n2_c_flat[31:0],   exp_c00, {tag, " [PE(0,0)]"});
            check_signed_eq(n2_c_flat[63:32],  exp_c01, {tag, " [PE(0,1)]"});
            check_signed_eq(n2_c_flat[95:64],  exp_c10, {tag, " [PE(1,0)]"});
            check_signed_eq(n2_c_flat[127:96], exp_c11, {tag, " [PE(1,1)]"});

            // Verify stationary hold for 2 idle cycles
            @(negedge clk);
            n2_valid_a_in = 2'b00;
            n2_valid_b_in = 2'b00;
            n2_a_in_flat  = 16'h0000;
            n2_b_in_flat  = 16'h0000;
            repeat (2) @(posedge clk);
            #1;
            check_signed_eq(n2_c_flat[31:0],   exp_c00, {tag, " [Hold PE(0,0)]"});
            check_signed_eq(n2_c_flat[63:32],  exp_c01, {tag, " [Hold PE(0,1)]"});
            check_signed_eq(n2_c_flat[95:64],  exp_c10, {tag, " [Hold PE(1,0)]"});
            check_signed_eq(n2_c_flat[127:96], exp_c11, {tag, " [Hold PE(1,1)]"});
        end
    endtask

    task test_parameterized_n2;
        integer job_i, seed_n2;
        reg signed [7:0] ra00, ra01, ra10, ra11;
        reg signed [7:0] rb00, rb01, rb10, rb11;
        begin
            $display("[TEST SUITE 4] Verifying Parameterized N=2 Array...");
            @(negedge clk);
            n2_reset = 0;

            // 1. Identity Matrix: A * I = A
            run_n2_matmul(8'sd1, 8'sd2, 8'sd3, 8'sd4,
                          8'sd1, 8'sd0, 8'sd0, 8'sd1, "N=2 Identity");

            // 2. Ramp Matrix: [[1, 2], [3, 4]] * [[5, 6], [7, 8]]
            // C = [[1*5+2*7, 1*6+2*8], [3*5+4*7, 3*6+4*8]] = [[19, 22], [43, 50]]
            run_n2_matmul(8'sd1, 8'sd2, 8'sd3, 8'sd4,
                          8'sd5, 8'sd6, 8'sd7, 8'sd8, "N=2 Ramp");

            // 3. Mixed Signed: [[-2, 3], [4, -5]] * [[6, -7], [-8, 9]]
            run_n2_matmul(-8'sd2, 8'sd3, 8'sd4, -8'sd5,
                           8'sd6, -8'sd7, -8'sd8, 8'sd9, "N=2 Signed");

            // 4. Extreme Limits: [[-128, 127], [127, -128]] * [[-128, 127], [127, -128]]
            run_n2_matmul(-8'sd128,  8'sd127,  8'sd127, -8'sd128,
                          -8'sd128,  8'sd127,  8'sd127, -8'sd128, "N=2 Extremes");

            // 5. Zero Matrix
            run_n2_matmul(8'sd0, 8'sd0, 8'sd0, 8'sd0,
                          8'sd45, -8'sd88, 8'sd12, 8'sd99, "N=2 Zeros");

            // 6. Pseudo-Random Regression (25 Jobs)
            seed_n2 = 42;
            for (job_i = 0; job_i < 25; job_i = job_i + 1) begin
                ra00 = $dist_uniform(seed_n2, -128, 127);
                ra01 = $dist_uniform(seed_n2, -128, 127);
                ra10 = $dist_uniform(seed_n2, -128, 127);
                ra11 = $dist_uniform(seed_n2, -128, 127);
                rb00 = $dist_uniform(seed_n2, -128, 127);
                rb01 = $dist_uniform(seed_n2, -128, 127);
                rb10 = $dist_uniform(seed_n2, -128, 127);
                rb11 = $dist_uniform(seed_n2, -128, 127);
                run_n2_matmul(ra00, ra01, ra10, ra11,
                              rb00, rb01, rb10, rb11, "N=2 Random Job");
            end

            $display("[TEST SUITE 4] Parameterized N=2 Array PASSED.");
        end
    endtask

    // =========================================================================
    // Test Suite 5: Parameterized N=4 Array Verification
    // =========================================================================
    reg signed [7:0]  n4_mat_A [0:3][0:3];
    reg signed [7:0]  n4_mat_B [0:3][0:3];
    reg signed [31:0] n4_exp_C [0:3][0:3];

    task run_n4_matmul(input [511:0] tag);
        integer r, c, k, t;
        begin
            // Compute expected matrix C = A x B
            for (r = 0; r < 4; r = r + 1) begin
                for (c = 0; c < 4; c = c + 1) begin
                    n4_exp_C[r][c] = 0;
                    for (k = 0; k < 4; k = k + 1) begin
                        n4_exp_C[r][c] = n4_exp_C[r][c] + (n4_mat_A[r][k] * n4_mat_B[k][c]);
                    end
                end
            end

            // Synchronous Clear before job
            @(negedge clk);
            n4_clear      = 1;
            n4_a_in_flat  = 32'd0;
            n4_b_in_flat  = 32'd0;
            n4_valid_a_in = 4'd0;
            n4_valid_b_in = 4'd0;
            @(posedge clk);
            #1;
            check(n4_c_flat === 512'd0, {tag, " [N=4 Clear Check]"});
            @(negedge clk);
            n4_clear = 0;

            // Compute window: 3*N - 2 = 10 cycles (t = 0..9)
            for (t = 0; t < 10; t = t + 1) begin
                @(negedge clk);
                // Schedule Rows 0..3
                for (r = 0; r < 4; r = r + 1) begin
                    k = t - r;
                    if (k >= 0 && k < 4) begin
                        n4_valid_a_in[r]              = 1'b1;
                        n4_a_in_flat[r*8 +: 8]        = n4_mat_A[r][k];
                    end else begin
                        n4_valid_a_in[r]              = 1'b0;
                        n4_a_in_flat[r*8 +: 8]        = 8'd0;
                    end
                end

                // Schedule Cols 0..3
                for (c = 0; c < 4; c = c + 1) begin
                    k = t - c;
                    if (k >= 0 && k < 4) begin
                        n4_valid_b_in[c]              = 1'b1;
                        n4_b_in_flat[c*8 +: 8]        = n4_mat_B[k][c];
                    end else begin
                        n4_valid_b_in[c]              = 1'b0;
                        n4_b_in_flat[c*8 +: 8]        = 8'd0;
                    end
                end
                @(posedge clk);
            end

            #1;
            // Verify final accumulators for all 16 PEs
            for (r = 0; r < 4; r = r + 1) begin
                for (c = 0; c < 4; c = c + 1) begin
                    check_signed_eq(n4_c_flat[(r*4 + c)*32 +: 32], n4_exp_C[r][c],
                                    {tag, " [PE Accumulator Verification]"});
                end
            end

            // Verify stationary hold for 2 idle cycles
            @(negedge clk);
            n4_valid_a_in = 4'b0000;
            n4_valid_b_in = 4'b0000;
            n4_a_in_flat  = 32'h0;
            n4_b_in_flat  = 32'h0;
            repeat (2) @(posedge clk);
            #1;
            for (r = 0; r < 4; r = r + 1) begin
                for (c = 0; c < 4; c = c + 1) begin
                    check_signed_eq(n4_c_flat[(r*4 + c)*32 +: 32], n4_exp_C[r][c],
                                    {tag, " [Stationary Hold Verification]"});
                end
            end
        end
    endtask

    task test_parameterized_n4;
        integer r, c, job_i, seed_n4;
        begin
            $display("[TEST SUITE 5] Verifying Parameterized N=4 Array...");
            @(negedge clk);
            n4_reset = 0;

            // 1. Identity Matrix: A * I = A
            for (r = 0; r < 4; r = r + 1) begin
                for (c = 0; c < 4; c = c + 1) begin
                    n4_mat_A[r][c] = r * 4 + c + 1;
                    n4_mat_B[r][c] = (r == c) ? 8'sd1 : 8'sd0;
                end
            end
            run_n4_matmul("N=4 Identity");

            // 2. Ramp and Reverse Ramp
            for (r = 0; r < 4; r = r + 1) begin
                for (c = 0; c < 4; c = c + 1) begin
                    n4_mat_A[r][c] = r * 4 + c + 1;
                    n4_mat_B[r][c] = 16 - (r * 4 + c);
                end
            end
            run_n4_matmul("N=4 Ramp and Reverse");

            // 3. Extremes: All -128 * All -128 -> C[i][j] = 4 * 16384 = 65536
            for (r = 0; r < 4; r = r + 1) begin
                for (c = 0; c < 4; c = c + 1) begin
                    n4_mat_A[r][c] = -8'sd128;
                    n4_mat_B[r][c] = -8'sd128;
                end
            end
            run_n4_matmul("N=4 Min * Min (65536)");

            // 4. Extremes: All -128 * All 127 -> C[i][j] = 4 * (-16256) = -65024
            for (r = 0; r < 4; r = r + 1) begin
                for (c = 0; c < 4; c = c + 1) begin
                    n4_mat_A[r][c] = -8'sd128;
                    n4_mat_B[r][c] =  8'sd127;
                end
            end
            run_n4_matmul("N=4 Min * Max (-65024)");

            // 5. Extremes: All 127 * All 127 -> C[i][j] = 4 * 16129 = 64516
            for (r = 0; r < 4; r = r + 1) begin
                for (c = 0; c < 4; c = c + 1) begin
                    n4_mat_A[r][c] = 8'sd127;
                    n4_mat_B[r][c] = 8'sd127;
                end
            end
            run_n4_matmul("N=4 Max * Max (64516)");

            // 6. Zero Matrix
            for (r = 0; r < 4; r = r + 1) begin
                for (c = 0; c < 4; c = c + 1) begin
                    n4_mat_A[r][c] = 8'sd0;
                    n4_mat_B[r][c] = r * 10 - c * 5;
                end
            end
            run_n4_matmul("N=4 Zeros");

            // 7. Pseudo-Random Regression (25 Jobs)
            seed_n4 = 12345;
            for (job_i = 0; job_i < 25; job_i = job_i + 1) begin
                for (r = 0; r < 4; r = r + 1) begin
                    for (c = 0; c < 4; c = c + 1) begin
                        n4_mat_A[r][c] = $dist_uniform(seed_n4, -128, 127);
                        n4_mat_B[r][c] = $dist_uniform(seed_n4, -128, 127);
                    end
                end
                run_n4_matmul("N=4 Random Job");
            end

            $display("[TEST SUITE 5] Parameterized N=4 Array PASSED.");
        end
    endtask

    // =========================================================================
    // Test Suite 6: Shared Golden-Vector Regression N=3 (Requirement A)
    // =========================================================================
    task test_shared_golden_vectors_n3;
        integer job, t, line_idx, pe_r, pe_c;
        reg signed [31:0] exp_acc, act_acc;
        begin
            $display("[TEST SUITE 6] Running Shared Golden-Vector Regression (N=3, 112 jobs, 784 cycles)...");

            // Read vector files
            $readmemh("sim/vectors/trace_in.hex", trace_in_mem);
            $readmemh("sim/vectors/trace_c.hex", trace_c_mem);

            @(negedge clk);
            n3_reset = 0;

            for (job = 0; job < 112; job = job + 1) begin
                // Synchronous clear between jobs
                @(negedge clk);
                n3_clear      = 1;
                n3_a_in_flat  = 24'd0;
                n3_b_in_flat  = 24'd0;
                n3_valid_a_in = 3'd0;
                n3_valid_b_in = 3'd0;
                @(posedge clk);
                #1;

                // Verify synchronous clear of all 9 PEs
                for (pe_r = 0; pe_r < 3; pe_r = pe_r + 1) begin
                    for (pe_c = 0; pe_c < 3; pe_c = pe_c + 1) begin
                        total_tests = total_tests + 1;
                        act_acc = n3_c_flat[(pe_r*3 + pe_c)*32 +: 32];
                        if (act_acc !== 32'sd0) begin
                            total_errors = total_errors + 1;
                            $display("ERROR: Clear Mismatch before Job %0d at PE(%0d,%0d): expected 0, got %0d",
                                     job, pe_r, pe_c, act_acc);
                        end
                    end
                end

                @(negedge clk);
                n3_clear = 0;

                // 7 compute cycles per job (t = 0..6)
                for (t = 0; t < 7; t = t + 1) begin
                    line_idx = job * 7 + t;
                    total_cycles = total_cycles + 1;

                    // Apply boundary inputs from trace_in.hex
                    n3_a_in_flat  = trace_in_mem[line_idx][23:0];
                    n3_b_in_flat  = trace_in_mem[line_idx][47:24];
                    n3_valid_a_in = trace_in_mem[line_idx][50:48];
                    n3_valid_b_in = trace_in_mem[line_idx][53:51];

                    @(posedge clk);
                    #1;

                    // Compare all 9 PE accumulators against trace_c.hex
                    for (pe_r = 0; pe_r < 3; pe_r = pe_r + 1) begin
                        for (pe_c = 0; pe_c < 3; pe_c = pe_c + 1) begin
                            golden_comparisons = golden_comparisons + 1;
                            total_tests        = total_tests + 1;
                            exp_acc = trace_c_mem[line_idx][(pe_r*3 + pe_c)*32 +: 32];
                            act_acc = n3_c_flat[(pe_r*3 + pe_c)*32 +: 32];

                            if (act_acc !== exp_acc) begin
                                golden_mismatches = golden_mismatches + 1;
                                total_errors      = total_errors + 1;
                                $display("ERROR: Golden Mismatch Job %0d Cycle %0d (t=%0d) PE(%0d,%0d): exp 0x%08h (%0d), got 0x%08h (%0d)",
                                         job, line_idx, t, pe_r, pe_c, exp_acc, exp_acc, act_acc, act_acc);
                            end
                        end
                    end
                end
                golden_jobs = golden_jobs + 1;
            end

            $display("[TEST SUITE 6] Golden Regression Complete: %0d jobs, %0d cycles, %0d comparisons, %0d mismatches.",
                     golden_jobs, total_cycles, golden_comparisons, golden_mismatches);
        end
    endtask

    // =========================================================================
    // Test Suite 7: Backward-Compatible Wrapper Verification (`systolic_array_3x3`)
    // =========================================================================
    task test_backward_compatible_wrapper;
        integer t;
        begin
            $display("[TEST SUITE 7] Verifying Backward-Compatible Wrapper systolic_array_3x3...");

            @(negedge clk);
            wrap_reset = 0;
            wrap_clear = 1;
            @(posedge clk);
            #1;
            check(wrap_c_flat === 288'd0, "Wrapper clear check");
            @(negedge clk);
            wrap_clear = 0;

            // Run Demo Job 0 through the wrapper
            for (t = 0; t < 7; t = t + 1) begin
                @(negedge clk);
                wrap_a_in_flat  = trace_in_mem[t][23:0];
                wrap_b_in_flat  = trace_in_mem[t][47:24];
                wrap_valid_a_in = trace_in_mem[t][50:48];
                wrap_valid_b_in = trace_in_mem[t][53:51];
                @(posedge clk);
                #1;
                check(wrap_c_flat === trace_c_mem[t], "Wrapper trace match");
            end

            $display("[TEST SUITE 7] Backward-Compatible Wrapper PASSED.");
        end
    endtask

    // =========================================================================
    // Main Test Execution Flow
    // =========================================================================
    initial begin
        // Optional VCD waveform dumping
        if ($value$plusargs("vcd=%s", dump_file)) begin
            $dumpfile(dump_file);
            $dumpvars(0, tb_systolic_array);
        end

        $display("========================================================================");
        $display("SysMAC: Parameterized Systolic Array Verification Testbench");
        $display("RTL: rtl/systolic_array.v with Abhishek's actual rtl/processing_element.v");
        $display("========================================================================");

        // Run all suites
        test_reset_and_clear();
        test_validity_propagation();
        test_signed_and_edge_cases();
        test_parameterized_n2();
        test_parameterized_n4();
        test_shared_golden_vectors_n3();
        test_backward_compatible_wrapper();

        // ---------------------------------------------------------------------
        // Final Summary and Reporting
        // -------------------------------------------------------------------------
        $display("========================================================================");
        $display("jobs=%0d errors=%0d", golden_jobs, total_errors + golden_mismatches);
        $display("Total checks performed: %0d", total_tests);
        $display("Golden vector comparisons: %0d", golden_comparisons);
        $display("Golden vector mismatches: %0d", golden_mismatches);
        $display("========================================================================");

        if ((total_errors + golden_mismatches) == 0 && golden_jobs == 112) begin
            $display("ALL SYSTOLIC ARRAY TESTS PASSED");
        end else begin
            $display("SYSTOLIC ARRAY TESTS FAILED: %0d errors, %0d mismatches",
                     total_errors, golden_mismatches);
            $finish(1);
        end

        $finish;
    end

endmodule
