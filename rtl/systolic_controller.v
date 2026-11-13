// FSM: IDLE -> LOAD -> COMPUTE(7 cycles) -> CAPTURE -> DONE -> IDLE
module systolic_controller (
    input  wire       clk,
    input  wire       reset,
    input  wire       start,
    output wire       load,
    output wire       clear,
    output wire       run,
    output wire       capture,
    output wire       done,
    output reg  [2:0] t
);
    localparam IDLE = 3'd0, LOAD = 3'd1, COMPUTE = 3'd2, CAPTURE = 3'd3, DONE = 3'd4;

    reg [2:0] state;

    // Moore outputs
    assign load    = (state == LOAD);
    assign clear   = (state == LOAD);
    assign run     = (state == COMPUTE);
    assign capture = (state == CAPTURE);
    assign done    = (state == DONE);

    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            t     <= 3'd0;
        end else begin
            case (state)
                IDLE:    if (start) state <= LOAD;
                LOAD:    begin state <= COMPUTE; t <= 3'd0; end
                COMPUTE: if (t == 3'd6) state <= CAPTURE;
                         else           t <= t + 3'd1;
                CAPTURE: state <= DONE;
                DONE:    state <= IDLE;
                default: state <= IDLE;
            endcase
        end
    end
endmodule
