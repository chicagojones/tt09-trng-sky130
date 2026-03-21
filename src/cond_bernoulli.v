`default_nettype none

/**
 * Bernoulli Shift Map Conditioner
 *
 * Simplest chaotic map: x_next = 2x mod 1 (left shift, discard MSB).
 * Lyapunov exponent = ln(2). Entropy injected into LSB via XOR.
 * Serves as a "minimal chaos" baseline — any improvement from more
 * complex maps (tent, logistic, Lorenz) is due to their nonlinearity.
 */
module cond_bernoulli (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       en,
    input  wire       sampled_bit,
    output wire       out_bit,
    output wire       out_valid,
    output wire [7:0] state_out
);

    localparam SEED = 8'hA5;

    reg [7:0] x;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x <= SEED;
        end else if (en) begin
            // Left shift (2x mod 1) with entropy injection into LSB
            x <= {x[6:0], x[7] ^ sampled_bit};
        end
    end

    assign out_bit   = x[7];
    assign out_valid  = en;
    assign state_out  = x;

endmodule
