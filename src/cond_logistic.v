`default_nettype none

/**
 * Parameterized Logistic Map Conditioner
 *
 * x_next = r * x * (1 - x), with r ≈ 4.
 * Fixed-point Q0.WIDTH: x represents [0, 1) as WIDTH-bit unsigned fraction.
 */
module cond_logistic #(
    parameter WIDTH = 8,
    parameter SEED  = 8'h66
)(
    input  wire             clk,
    input  wire             rst_n,
    input  wire             en,
    input  wire             sampled_bit,
    output wire             out_bit,
    output reg              out_valid,
    output wire [WIDTH-1:0] state_out
);

    reg [WIDTH-1:0] x;
    reg [WIDTH-1:0] one_minus_x;
    reg [2*WIDTH-1:0] product;
    reg [5:0]       mul_count; // Support up to 64 bits
    reg [WIDTH-1:0] multiplicand;
    reg             computing;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x             <= {{(WIDTH-8){1'b0}}, 8'h66};
            one_minus_x   <= {WIDTH{1'b1}} - {{(WIDTH-8){1'b0}}, 8'h66};
            product       <= {2*WIDTH{1'b0}};
            mul_count     <= 6'd0;
            multiplicand  <= {WIDTH{1'b0}};
            computing     <= 1'b0;
            out_valid     <= 1'b0;
        end else if (en) begin
            out_valid <= 1'b0;

            if (!computing) begin
                one_minus_x  <= {WIDTH{1'b1}} - x;
                multiplicand <= x;
                product      <= {2*WIDTH{1'b0}};
                mul_count    <= 6'd0;
                computing    <= 1'b1;
            end else begin
                if (mul_count < WIDTH) begin
                    if (multiplicand[mul_count[5:0]])
                        product <= product + ({{WIDTH{1'b0}}, one_minus_x} << mul_count[5:0]);
                    mul_count <= mul_count + 1'b1;
                end else begin
                    // r=4 is left shift by 2.
                    // x*one_minus_x is in Q0.(2*WIDTH). 
                    // x_next = (product << 2) >> WIDTH = product >> (WIDTH - 2)
                    // We take bits [WIDTH+WIDTH-3 : WIDTH-2]
                    // For WIDTH=8: bits [13:6]
                    x <= (product[2*WIDTH-3:WIDTH-2] == {WIDTH{1'b0}}) ? {{(WIDTH-8){1'b0}}, 8'h66} :
                         {product[2*WIDTH-3:WIDTH-1], product[WIDTH-2] ^ sampled_bit};
                    
                    computing <= 1'b0;
                    out_valid <= 1'b1;
                end
            end
        end
    end

    assign out_bit   = x[WIDTH-1] ^ x[WIDTH/2] ^ x[0];
    assign state_out = x;

endmodule
