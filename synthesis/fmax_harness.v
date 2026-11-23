// Timing harness for place and route. Not part of the design.
//
// The accelerator has 436 I/O bits, more than any iCE40 package has pins,
// and nextpnr has no out-of-context mode. This wrapper feeds a_flat/b_flat
// from a 144-bit shift register (one input pin) and shifts c_flat out of a
// 288-bit register (one output pin). Every port of the core is driven by or
// captured in a flip-flop, so the core's register-to-register paths are what
// nextpnr times. Resource counts come from synthesising the bare core
// (scripts/run_synthesis.sh), not from this wrapper.
//
// Pick the core with -DCORE=systolic_accelerator_top or -DCORE=seq_matmul.
module fmax_harness (
    input  wire clk,
    input  wire reset,
    input  wire start_pin,
    input  wire sin,
    output wire done_pin,
    output wire sout
);
    reg  [143:0] in_sr;
    reg          start_q;
    reg  [287:0] out_sr;
    reg          done_q;
    wire         done;
    wire [287:0] c_flat;

    always @(posedge clk) begin
        in_sr   <= {in_sr[142:0], sin};
        start_q <= start_pin;
        done_q  <= done;
        out_sr  <= done ? c_flat : {out_sr[286:0], 1'b0};
    end

    `CORE u_core (
        .clk(clk), .reset(reset), .start(start_q),
        .a_flat(in_sr[71:0]), .b_flat(in_sr[143:72]),
        .done(done), .c_flat(c_flat)
    );

    assign done_pin = done_q;
    assign sout     = out_sr[287];
endmodule
