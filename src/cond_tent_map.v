`default_nettype none

/**
 * Parameterized Tent Map Conditioner
 *
 * Piecewise linear chaotic map: x_next = 2*x if x < 0.5, else 2*(1-x)
 * Fixed-point: if MSB=0, shift left; if MSB=1, invert then shift left.
 * Entropy injected via XOR into LSB.
 */
module cond_tent_map #(
    parameter WIDTH = 8,
    parameter SEED  = 8'hA5
)(
    input  wire             clk,
    input  wire             rst_n,
    input  wire             en,
    input  wire             sampled_bit,
    output wire             out_bit,
    output wire             out_valid,
    output wire [WIDTH-1:0] state_out
);

    reg [WIDTH-1:0] x;

    wire [WIDTH-1:0] x_tent = x[WIDTH-1] ? (~x << 1) : (x << 1);
    wire [WIDTH-1:0] x_next = {x_tent[WIDTH-1:1], x_tent[0] ^ sampled_bit};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x <= {{(WIDTH-8){1'b1}}, 8'hA5};
        end else if (en) begin
            x <= (x_next == {WIDTH{1'b0}}) ? {{(WIDTH-8){1'b1}}, 8'hA5} : x_next;
        end
    end

    assign out_bit   = x[WIDTH-1];
    assign out_valid  = en;
    assign state_out  = x;

endmodule
