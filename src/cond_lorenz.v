`default_nettype none

/**
 * Parameterized Lorenz Attractor Conditioner (Euler Method)
 *
 * Fixed-point signed. Default WIDTH=16 (Q8.8).
 * Uses a sequential shift-and-add multiplier to save area.
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

    // Shift-and-add Multiplier operands and result
    reg [WIDTH-1:0]          mul_a_abs, mul_b_abs;
    reg [2*WIDTH-1:0]        mul_result_abs;
    reg                      mul_sign;
    wire signed [2*WIDTH-1:0] mul_result_signed = mul_sign ? -$signed(mul_result_abs) : $signed(mul_result_abs);

    // Intermediate results - extra bits to prevent overflow
    reg signed [WIDTH+7:0] dx, dy_partial, dz_partial;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x              <= { {(WIDTH-SHIFT-1){1'b0}}, 1'b1, {SHIFT{1'b0}} }; // 1.0
            y              <= { {(WIDTH-SHIFT-1){1'b0}}, 1'b1, {SHIFT{1'b0}} }; // 1.0
            z              <= { {(WIDTH-SHIFT-1){1'b0}}, 1'b1, {SHIFT{1'b0}} }; // 1.0
            state          <= S_IDLE;
            mul_step       <= 6'd0;
            mul_a_abs      <= {WIDTH{1'b0}};
            mul_b_abs      <= {WIDTH{1'b0}};
            mul_result_abs <= {2*WIDTH{1'b0}};
            mul_sign       <= 1'b0;
            dx             <= {(WIDTH+8){1'b0}};
            dy_partial     <= {(WIDTH+8){1'b0}};
            dz_partial     <= {(WIDTH+8){1'b0}};
            out_valid      <= 1'b0;
        end else if (en) begin
            out_valid <= 1'b0;

            case (state)
                S_IDLE: begin
                    // dx = 10*(y-x)
                    dx <= $signed(((y - x) <<< 3) + ((y - x) <<< 1));
                    
                    // Setup shift-and-add multiply for x * (rho - z)
                    mul_sign <= x[WIDTH-1] ^ ($signed( (28 << SHIFT) ) - z) < 0;
                    mul_a_abs <= x[WIDTH-1] ? -x : x;
                    mul_b_abs <= ($signed( (28 << SHIFT) ) - z) < 0 ? -($signed( (28 << SHIFT) ) - z) : ($signed( (28 << SHIFT) ) - z);
                    
                    mul_result_abs <= {2*WIDTH{1'b0}};
                    mul_step <= 6'd0;
                    state <= S_MUL_2;
                end

                S_MUL_2: begin
                    if (mul_step < WIDTH) begin
                        if (mul_a_abs[mul_step[5:0]]) begin
                            mul_result_abs <= mul_result_abs + ({ {WIDTH{1'b0}}, mul_b_abs } << mul_step[5:0]);
                        end
                        mul_step <= mul_step + 1'b1;
                    end else begin
                        // dy_partial = x*(rho-z) - y
                        dy_partial <= $signed(mul_result_signed[WIDTH+SHIFT-1:SHIFT]) - $signed(y);
                        
                        // Setup multiply for x * y
                        mul_sign <= x[WIDTH-1] ^ y[WIDTH-1];
                        mul_a_abs <= x[WIDTH-1] ? -x : x;
                        mul_b_abs <= y[WIDTH-1] ? -y : y;
                        
                        mul_result_abs <= {2*WIDTH{1'b0}};
                        mul_step <= 6'd0;
                        state <= S_MUL_3;
                    end
                end

                S_MUL_3: begin
                    if (mul_step < WIDTH) begin
                        if (mul_a_abs[mul_step[5:0]]) begin
                            mul_result_abs <= mul_result_abs + ({ {WIDTH{1'b0}}, mul_b_abs } << mul_step[5:0]);
                        end
                        mul_step <= mul_step + 1'b1;
                    end else begin
                        // dz_partial = x*y - beta*z (beta=3)
                        dz_partial <= $signed(mul_result_signed[WIDTH+SHIFT-1:SHIFT]) - $signed((z <<< 1) + z);
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
    assign state_out = x;

endmodule
