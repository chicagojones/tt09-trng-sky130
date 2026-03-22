`default_nettype none

/**
 * Parameterized Coupled Tent Map Conditioner
 */
module cond_coupled_tent #(
    parameter WIDTH = 8
)(
    input  wire             clk,
    input  wire             rst_n,
    input  wire             en,
    input  wire             sampled_bit,
    output wire             out_bit,
    output wire             out_valid,
    output wire [2*WIDTH-1:0] state_out
);

    localparam SEED_X = 8'hA5;
    localparam SEED_Y = 8'h5A;

    reg [WIDTH-1:0] x, y;

    // Independent tent maps
    wire [WIDTH-1:0] x_tent = x[WIDTH-1] ? (~x << 1) : (x << 1);
    wire [WIDTH-1:0] y_tent = y[WIDTH-1] ? (~y << 1) : (y << 1);

    // Cross-coupling: mix upper half of one into lower half of another
    localparam HALF = WIDTH / 2;
    wire [WIDTH-1:0] x_coupled = x_tent ^ { {HALF{1'b0}}, y[WIDTH-1:WIDTH-HALF] };
    wire [WIDTH-1:0] y_coupled = y_tent ^ { {HALF{1'b0}}, x[HALF-1:0] };

    // Entropy injection into x LSB
    wire [WIDTH-1:0] x_next = {x_coupled[WIDTH-1:1], x_coupled[0] ^ sampled_bit};
    wire [WIDTH-1:0] y_next = y_coupled;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x <= {{(WIDTH-8){1'b1}}, 8'hA5};
            y <= {{(WIDTH-8){1'b0}}, 8'h5A};
        end else if (en) begin
            x <= (x_next == {WIDTH{1'b0}}) ? {{(WIDTH-8){1'b1}}, 8'hA5} : x_next;
            y <= (y_next == {WIDTH{1'b0}}) ? {{(WIDTH-8){1'b0}}, 8'h5A} : y_next;
        end
    end

    assign out_bit   = x[WIDTH-1] ^ y[WIDTH-1];
    assign out_valid  = en;
    assign state_out  = {y, x};

endmodule
