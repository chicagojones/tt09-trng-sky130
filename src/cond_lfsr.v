`default_nettype none

/**
 * Parameterized LFSR Conditioner
 *
 * Uses a Galois LFSR with primitive polynomials for 8, 16, 24, 32 bits.
 * Entropy injected via XOR into the feedback path.
 */
module cond_lfsr #(
    parameter WIDTH = 16,
    parameter SEED  = 16'hACE1
)(
    input  wire             clk,
    input  wire             rst_n,
    input  wire             en,
    input  wire             sampled_bit,
    output wire             out_bit,
    output wire             out_valid,
    output wire [WIDTH-1:0] state_out
);

    reg [WIDTH-1:0] lfsr;
    wire feedback;

    // Primitive polynomials:
    // 8:  x^8 + x^6 + x^5 + x^4 + 1
    // 16: x^16 + x^14 + x^13 + x^11 + 1
    // 24: x^24 + x^23 + x^22 + x^17 + 1
    // 32: x^32 + x^22 + x^2 + x^1 + 1
    generate
        if (WIDTH == 8)
            assign feedback = lfsr[7] ^ lfsr[5] ^ lfsr[4] ^ lfsr[3];
        else if (WIDTH == 16)
            assign feedback = lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10];
        else if (WIDTH == 24)
            assign feedback = lfsr[23] ^ lfsr[22] ^ lfsr[21] ^ lfsr[16];
        else // default to 32
            assign feedback = lfsr[31] ^ lfsr[21] ^ lfsr[1] ^ lfsr[0];
    endgenerate

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lfsr <= {WIDTH{1'b1}} & 16'hACE1;
        end else if (en) begin
            lfsr <= {lfsr[WIDTH-2:0], feedback ^ sampled_bit};
        end
    end

    assign out_bit   = lfsr[WIDTH-1];
    assign out_valid  = en;
    assign state_out  = lfsr;

endmodule
