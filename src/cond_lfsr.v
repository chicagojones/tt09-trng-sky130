`default_nettype none

/**
 * Fibonacci LFSR Conditioner
 *
 * 16-bit maximal-length LFSR: x^16 + x^14 + x^13 + x^11 + 1
 * Period: 2^16 - 1 = 65535.
 * NOT chaotic — linear and predictable. Included as a baseline
 * to compare against nonlinear conditioners on the same die.
 * Entropy injected by XORing sampled_bit into feedback.
 */
module cond_lfsr (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       en,
    input  wire       sampled_bit,
    output wire       out_bit,
    output wire       out_valid,
    output wire [7:0] state_out
);

    localparam SEED = 16'hACE1;

    reg [15:0] lfsr;

    wire feedback = lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lfsr <= SEED;
        end else if (en) begin
            lfsr <= {lfsr[14:0], feedback ^ sampled_bit};
        end
    end

    assign out_bit   = lfsr[15];
    assign out_valid  = en;
    assign state_out  = lfsr[15:8];

endmodule
