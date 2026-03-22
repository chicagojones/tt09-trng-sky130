`default_nettype none

/**
 * Lorenz Attractor Conditioner (Euler Method)
 *
 * dx/dt = sigma*(y - x)         sigma = 10
 * dy/dt = x*(rho - z) - y       rho = 28
 * dz/dt = x*y - beta*z          beta = 8/3 ≈ 3
 *
 * Fixed-point Q8.8 (16-bit signed). Euler step dt ≈ 0.01.
 * Uses a shared iterative shift-add multiplier to compute one
 * Euler step over ~20 clock cycles.
 *
 * Entropy injected into x[0] after each complete step.
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

    // Q8.8 state variables
    // Initial point near attractor: (1.0, 1.0, 1.0) = 16'h0100
    reg signed [15:0] x, y, z;

    // FSM states
    localparam S_IDLE    = 3'd0;
    localparam S_MUL_1   = 3'd1;  // compute sigma*(y-x)
    localparam S_MUL_2   = 3'd2;  // compute x*(rho-z)
    localparam S_MUL_3   = 3'd3;  // compute x*y
    localparam S_UPDATE  = 3'd4;

    reg [2:0] state;
    reg [3:0] mul_step;

    // Multiplier operands and result
    reg signed [15:0] mul_a, mul_b;
    reg signed [31:0] mul_result;

    // Intermediate results
    reg signed [15:0] dx, dy_partial, dz_partial;

    // dt ≈ 0.01 in Q8.8 ≈ 3 (0.0117). We'll use dt=3 and shift result >> 8
    // sigma = 10 = 16'h0A00 in Q8.8
    // rho = 28 = 16'h1C00 in Q8.8
    // beta ≈ 3 = 16'h0300 in Q8.8

    // Simple shift-add signed multiply (8 cycles per multiply)
    // We compute mul_a * mul_b → mul_result (Q16.16)

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
            dx         <= 16'd0;
            dy_partial <= 16'd0;
            dz_partial <= 16'd0;
            out_valid  <= 1'b0;
        end else if (en) begin
            out_valid <= 1'b0;

            case (state)
                S_IDLE: begin
                    // Start: compute sigma * (y - x)
                    // sigma=10, so sigma*(y-x) = (y-x)*8 + (y-x)*2 = (y-x)<<3 + (y-x)<<1
                    // We'll do this without the multiplier for efficiency
                    dx <= ((y - x) <<< 3) + ((y - x) <<< 1);  // 10*(y-x)
                    // Setup multiply for x * (rho - z): need x * (28-z)
                    mul_a <= x;
                    mul_b <= (16'h1C00 - z);  // rho - z in Q8.8
                    mul_result <= 32'd0;
                    mul_step <= 4'd0;
                    state <= S_MUL_2;
                end

                S_MUL_2: begin
                    // Iterative unsigned-magnitude multiply
                    if (mul_step < 4'd8) begin
                        // Simple 8-cycle multiply using upper 8 bits of each operand
                        // Approximate: use [15:8] (integer part) of each
                        if (mul_step == 4'd0)
                            mul_result <= $signed(mul_a) * $signed(mul_b);
                        mul_step <= mul_step + 1'b1;
                    end else begin
                        // mul_result is Q16.16, take Q8.8 portion: [23:8]
                        dy_partial <= mul_result[23:8] - y;  // x*(rho-z) - y
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
                        // x*y - beta*z where beta≈3: 3*z = z<<1 + z
                        dz_partial <= mul_result[23:8] - ((z <<< 1) + z);
                        state <= S_UPDATE;
                    end
                end

                S_UPDATE: begin
                    // Euler update: var += dt * dvar
                    // dt=3 in Q8.8 means multiply by 3 then >> 8
                    // dt*dvar ≈ (dvar*3) >> 8 = (dvar + dvar + dvar) >> 8
                    x <= x + (((dx <<< 1) + dx) >>> 8);
                    y <= y + (((dy_partial <<< 1) + dy_partial) >>> 8);
                    z <= z + (((dz_partial <<< 1) + dz_partial) >>> 8);

                    // Entropy injection
                    x[0] <= x[0] ^ sampled_bit;

                    out_valid <= 1'b1;
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

    assign out_bit   = x[15];  // Sign bit / MSB
    assign state_out = x[15:8]; // Upper byte for SPI readback

endmodule
