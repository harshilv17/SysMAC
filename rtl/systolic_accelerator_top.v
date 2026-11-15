// Top: controller -> buffer -> scheduler -> 3x3 array -> output registers
module systolic_accelerator_top (
    input  wire         clk,
    input  wire         reset,
    input  wire         start,
    input  wire [71:0]  a_flat,
    input  wire [71:0]  b_flat,
    output wire         done,
    output wire [287:0] c_flat
);
    wire        load, clear, run, capture;
    wire [2:0]  t;
    wire [71:0] a_mat, b_mat;
    wire [23:0] a_in_flat, b_in_flat;
    wire [2:0]  valid_a_in, valid_b_in;
    wire [287:0] c_acc;

    systolic_controller u_ctrl (
        .clk(clk), .reset(reset), .start(start),
        .load(load), .clear(clear), .run(run),
        .capture(capture), .done(done), .t(t)
    );

    input_buffer u_buf (
        .clk(clk), .reset(reset), .load(load),
        .a_flat(a_flat), .b_flat(b_flat),
        .a_mat(a_mat), .b_mat(b_mat)
    );

    input_scheduler u_sched (
        .run(run), .t(t), .a_mat(a_mat), .b_mat(b_mat),
        .a_in_flat(a_in_flat), .b_in_flat(b_in_flat),
        .valid_a_in(valid_a_in), .valid_b_in(valid_b_in)
    );

    systolic_array_3x3 u_array (
        .clk(clk), .reset(reset), .clear(clear),
        .a_in_flat(a_in_flat), .b_in_flat(b_in_flat),
        .valid_a_in(valid_a_in), .valid_b_in(valid_b_in),
        .c_flat(c_acc)
    );

    output_registers u_out (
        .clk(clk), .reset(reset), .capture(capture),
        .c_in(c_acc), .c_flat(c_flat)
    );
endmodule
