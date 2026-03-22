`default_nettype none

/**
 * Lorenz Attractor Conditioner (Euler Method)
 *
 * dx/dt = sigma*(y - x)         sigma = 10
 * dy/dt = x*(rho - z) - y       rho = 28
 * dz/dt = x*y - beta*z          beta = 8/3 ≈ 3
 *
 * Fixed-point Q8.8 (16-bit signed). Euler step dt ≈ 0.01.
 */
module cond_lorenz (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        en,
    input  wire        sampled_bit,
    output wire        out_bit,
    output reg         out_valid,
    output wire [7:0]  state_out
);

    // Q8.8 state variables (±128 range)
    reg signed [15:0] x, y, z;

    // FSM states
    localparam S_IDLE    = 3'd0;
    localparam S_MUL_2   = 3'd2;  // compute x*(rho-z)
    localparam S_MUL_3   = 3'd3;  // compute x*y
    localparam S_UPDATE  = 3'd4;

    reg [2:0] state;
    reg [3:0] mul_step;

    // Multiplier operands and result
    reg signed [15:0] mul_a, mul_b;
    reg signed [31:0] mul_result;

    // Intermediate results - 24 bits to prevent overflow!
    // Max dx can be ~10 * 80 = 800. 800 in Q8.8 is 204,800.
    // 24 bits holds ±8,388,608.
    reg signed [23:0] dx, dy_partial, dz_partial;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x          <= 16'h0100;  // 1.0
            y          <= 16'h0100;  // 1.0
            z          <= 16'h0100;  // 1.0
            state      <= S_IDLE;
            mul_step   <= 4'd0;
            mul_a      <= 16'd0;
            mul_b      <= 16'd0;
            mul_result <= 32'd0;
            dx         <= 24'd0;
            dy_partial <= 24'd0;
            dz_partial <= 24'd0;
            out_valid  <= 1'b0;
        end else if (en) begin
            out_valid <= 1'b0;

            case (state)
                S_IDLE: begin
                    // dx = 10*(y-x)
                    dx <= $signed(((y - x) <<< 3) + ((y - x) <<< 1));
                    // Setup multiply for x * (rho - z)
                    mul_a <= x;
                    mul_b <= (16'h1C00 - z);  // 28 - z
                    mul_result <= 32'd0;
                    mul_step <= 4'd0;
                    state <= S_MUL_2;
                end

                S_MUL_2: begin
                    if (mul_step < 4'd8) begin
                        if (mul_step == 4'd0)
                            mul_result <= $signed(mul_a) * $signed(mul_b);
                        mul_step <= mul_step + 1'b1;
                    end else begin
                        // dy_partial = x*(rho-z) - y
                        // mul_result is Q16.16, shift by 8 to get Q8.8
                        dy_partial <= $signed(mul_result[31:8]) - $signed({{8{y[15]}}, y});
                        // Setup multiply for x * y
                        mul_a <= x;
                        mul_b <= y;
                        mul_result <= 32'd0;
                        mul_step <= 4'd0;
                        state <= S_MUL_3;
                    end
                end

                S_MUL_3: begin
                    if (mul_step < 4'd8) begin
                        if (mul_step == 4'd0)
                            mul_result <= $signed(mul_a) * $signed(mul_b);
                        mul_step <= mul_step + 1'b1;
                    end else begin
                        // dz_partial = x*y - beta*z (beta=3)
                        dz_partial <= $signed(mul_result[31:8]) - $signed({{8{z[15]}}, (z <<< 1) + z});
                        state <= S_UPDATE;
                    end
                end

                S_UPDATE: begin
                    // Euler update: var += (dvar * 3) >>> 8 (dt ≈ 0.011)
                    x <= x + $signed(((dx <<< 1) + dx) >>> 8);
                    y <= y + $signed(((dy_partial <<< 1) + dy_partial) >>> 8);
                    z <= z + $signed(((dz_partial <<< 1) + dz_partial) >>> 8);

                    // Entropy injection into LSB
                    x[0] <= x[0] ^ sampled_bit;

                    out_valid <= 1'b1;
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

    assign out_bit   = x[15];
    assign state_out = x[15:8];

endmodule
