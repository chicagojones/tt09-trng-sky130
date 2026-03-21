`default_nettype none

/**
 * Logistic Map Conditioner
 *
 * x_next = r * x * (1 - x), with r ≈ 4 (maximum chaos).
 * Fixed-point Q0.8: x represents [0, 1) as 8-bit unsigned fraction.
 * Uses iterative shift-add multiply (8 cycles per iteration).
 *
 * With r=4: x_next = 4 * x * (1-x) = (x * (1-x)) << 2
 * Lyapunov exponent = ln(2) at r=4.
 */
module cond_logistic (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       en,
    input  wire       sampled_bit,
    output wire       out_bit,
    output reg        out_valid,
    output wire [7:0] state_out
);

    localparam SEED = 8'h66;  // ~0.4 in Q0.8

    reg [7:0] x;
    reg [7:0] one_minus_x;
    reg [15:0] product;
    reg [3:0] mul_count;
    reg [7:0] multiplicand;
    reg       computing;

    // Shift-add multiplier: compute x * (1-x) over 8 cycles
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x             <= SEED;
            one_minus_x   <= 8'hFF - SEED;
            product       <= 16'd0;
            mul_count     <= 4'd0;
            multiplicand  <= 8'd0;
            computing     <= 1'b0;
            out_valid     <= 1'b0;
        end else if (en) begin
            out_valid <= 1'b0;

            if (!computing) begin
                // Start multiplication: x * (255 - x) ≈ x * (1-x) scaled
                one_minus_x  <= 8'hFF - x;
                multiplicand <= x;
                product      <= 16'd0;
                mul_count    <= 4'd0;
                computing    <= 1'b1;
            end else begin
                if (mul_count < 4'd8) begin
                    if (multiplicand[mul_count[2:0]])
                        product <= product + ({8'd0, one_minus_x} << mul_count[2:0]);
                    mul_count <= mul_count + 1'b1;
                end else begin
                    // Multiply by 4 (r=4): shift left by 2, take upper 8 bits
                    // product is x*(1-x) in Q0.16, *4 = Q0.16 << 2, take [17:10]
                    // But product max = 255*128 = 32640 = 0x7F80
                    // *4 = 130560, but that overflows 16 bits. Instead:
                    // Take product[15:8] << 2 as approximation
                    x <= (product[15:8] == 8'h00) ? SEED :
                         {product[13:8], product[7] ^ sampled_bit, product[6]};
                    computing <= 1'b0;
                    out_valid <= 1'b1;
                end
            end
        end
    end

    assign out_bit   = x[7];
    assign state_out = x;

endmodule
