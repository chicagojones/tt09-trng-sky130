`default_nettype none

/**
 * Tent Map Conditioner
 *
 * Piecewise linear chaotic map: x_next = 2*x if x < 0.5, else 2*(1-x)
 * Fixed-point 8-bit: if MSB=0, shift left; if MSB=1, invert then shift left.
 * Lyapunov exponent = ln(2). Entropy injected via XOR into LSB.
 */
module cond_tent_map (
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

    wire [7:0] x_tent = x[7] ? (~x << 1) : (x << 1);
    wire [7:0] x_next = {x_tent[7:1], x_tent[0] ^ sampled_bit};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x <= SEED;
        end else if (en) begin
            x <= (x_next == 8'h00) ? SEED : x_next;
        end
    end

    assign out_bit   = x[7];
    assign out_valid  = en;
    assign state_out  = x;

endmodule
