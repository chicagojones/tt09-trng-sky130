`default_nettype none

/**
 * Logistic Map Conditioner
 *
 * x_next = r * x * (1 - x), with r ≈ 4.
 * Fixed-point Q0.8: x represents [0, 1) as 8-bit unsigned fraction.
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

    localparam SEED = 8'h66;

    reg [7:0] x;
    reg [7:0] one_minus_x;
    reg [15:0] product;
    reg [3:0] mul_count;
    reg [7:0] multiplicand;
    reg       computing;

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
                    // r=4 is a left shift by 2.
                    // x*one_minus_x is in Q0.16. 
                    // x_next = (product * 4) >> 8 = product >> 6
                    // Use bits [13:6] to represent the new Q0.8 value.
                    // This avoids overflow because max product is ~0.25 in real terms (0x3FXX)
                    x <= (product[13:6] == 8'h00) ? SEED :
                         {product[13:7], product[6] ^ sampled_bit};
                    
                    computing <= 1'b0;
                    out_valid <= 1'b1;
                end
            end
        end
    end

    assign out_bit   = x[7];
    assign state_out = x;

endmodule
