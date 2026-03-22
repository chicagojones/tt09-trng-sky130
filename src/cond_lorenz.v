`default_nettype none

/**
 * Parameterized Lorenz Attractor Conditioner (Euler Method)
 *
 * Fixed-point signed. Default WIDTH=16 (Q8.8).
 * Scaling depends on WIDTH. We assume the upper half is integer, lower half is fraction.
 */
module cond_lorenz #(
    parameter WIDTH = 16
)(
    input  wire             clk,
    input  wire             rst_n,
    input  wire             en,
    input  wire             sampled_bit,
    output wire             out_bit,
    output reg              out_valid,
    output wire [WIDTH-1:0] state_out
);

    localparam SHIFT = WIDTH / 2;

    // Q(WIDTH/2).(WIDTH/2) state variables
    reg signed [WIDTH-1:0] x, y, z;

    // FSM states
    localparam S_IDLE    = 3'd0;
    localparam S_MUL_2   = 3'd2;  // compute x*(rho-z)
    localparam S_MUL_3   = 3'd3;  // compute x*y
    localparam S_UPDATE  = 3'd4;

    reg [2:0] state;
    reg [5:0] mul_step;

    // Multiplier operands and result
    reg signed [WIDTH-1:0]   mul_a, mul_b;
    reg signed [2*WIDTH-1:0] mul_result;

    // Intermediate results - extra bits to prevent overflow
    reg signed [WIDTH+7:0] dx, dy_partial, dz_partial;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x          <= { {(WIDTH-SHIFT-1){1'b0}}, 1'b1, {SHIFT{1'b0}} }; // 1.0
            y          <= { {(WIDTH-SHIFT-1){1'b0}}, 1'b1, {SHIFT{1'b0}} }; // 1.0
            z          <= { {(WIDTH-SHIFT-1){1'b0}}, 1'b1, {SHIFT{1'b0}} }; // 1.0
            state      <= S_IDLE;
            mul_step   <= 6'd0;
            mul_a      <= {WIDTH{1'b0}};
            mul_b      <= {WIDTH{1'b0}};
            mul_result <= {2*WIDTH{1'b0}};
            dx         <= {(WIDTH+8){1'b0}};
            dy_partial <= {(WIDTH+8){1'b0}};
            dz_partial <= {(WIDTH+8){1'b0}};
            out_valid  <= 1'b0;
        end else if (en) begin
            out_valid <= 1'b0;

            case (state)
                S_IDLE: begin
                    // dx = 10*(y-x)
                    dx <= $signed(((y - x) <<< 3) + ((y - x) <<< 1));
                    // Setup multiply for x * (rho - z)
                    mul_a <= x;
                    mul_b <= $signed( (28 << SHIFT) ) - z;
                    mul_result <= {2*WIDTH{1'b0}};
                    mul_step <= 6'd0;
                    state <= S_MUL_2;
                end

                S_MUL_2: begin
                    if (mul_step < WIDTH) begin
                        if (mul_step == 0)
                            mul_result <= x * mul_b;
                        mul_step <= mul_step + 1'b1;
                    end else begin
                        // dy_partial = x*(rho-z) - y
                        dy_partial <= $signed(mul_result[WIDTH+SHIFT-1:SHIFT]) - $signed(y);
                        // Setup multiply for x * y
                        mul_a <= x;
                        mul_b <= y;
                        mul_result <= {2*WIDTH{1'b0}};
                        mul_step <= 6'd0;
                        state <= S_MUL_3;
                    end
                end

                S_MUL_3: begin
                    if (mul_step < WIDTH) begin
                        if (mul_step == 0)
                            mul_result <= x * mul_b;
                        mul_step <= mul_step + 1'b1;
                    end else begin
                        // dz_partial = x*y - beta*z (beta=3)
                        dz_partial <= $signed(mul_result[WIDTH+SHIFT-1:SHIFT]) - $signed((z <<< 1) + z);
                        state <= S_UPDATE;
                    end
                end

                S_UPDATE: begin
                    // Euler update: var += (dvar * 3) >>> SHIFT
                    x <= x + $signed(((dx <<< 1) + dx) >>> SHIFT);
                    y <= y + $signed(((dy_partial <<< 1) + dy_partial) >>> SHIFT);
                    z <= z + $signed(((dz_partial <<< 1) + dz_partial) >>> SHIFT);

                    // Entropy injection into LSB
                    x[0] <= x[0] ^ sampled_bit;

                    out_valid <= 1'b1;
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

    // Multi-bit XOR output for higher entropy rate.
    // We XOR the MSB (sign), a middle bit (integer LSB), and a fractional bit.
    assign out_bit   = x[WIDTH-1] ^ x[SHIFT] ^ x[SHIFT/2];
    assign state_out = x[WIDTH-1:WIDTH-8]; // Take top 8 bits for SPI readback

endmodule
