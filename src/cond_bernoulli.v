`default_nettype none

/**
 * Parameterized Bernoulli Shift Map Conditioner
 *
 * x_next = 2x mod 1 (left shift, MSB discarded).
 * Entropy injected into LSB via XOR with MSB.
 */
module cond_bernoulli #(
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

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x <= {{(WIDTH-8){1'b1}}, 8'hA5};
        end else if (en) begin
            // Left shift (2x mod 1) with entropy injection into LSB
            x <= {x[WIDTH-2:0], x[WIDTH-1] ^ sampled_bit};
        end
    end

    assign out_bit   = x[WIDTH-1];
    assign out_valid  = en;
    assign state_out  = x;

endmodule
