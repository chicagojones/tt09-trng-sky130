`default_nettype none

/**
 * Coupled Tent Map Conditioner
 *
 * Two 8-bit tent maps with cross-coupled XOR mixing.
 * Higher dimensional chaotic attractor than a single tent map.
 * Entropy injected into x[0] via XOR with sampled_bit.
 */
module cond_coupled_tent (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        en,
    input  wire        sampled_bit,
    output wire        out_bit,
    output wire        out_valid,
    output wire [15:0] state_out
);

    localparam SEED_X = 8'hA5;
    localparam SEED_Y = 8'h5A;

    reg [7:0] x, y;

    // Independent tent maps
    wire [7:0] x_tent = x[7] ? (~x << 1) : (x << 1);
    wire [7:0] y_tent = y[7] ? (~y << 1) : (y << 1);

    // Cross-coupling: mix nibbles between maps
    wire [7:0] x_coupled = x_tent ^ {4'b0, y[7:4]};
    wire [7:0] y_coupled = y_tent ^ {4'b0, x[3:0]};

    // Entropy injection into x LSB
    wire [7:0] x_next = {x_coupled[7:1], x_coupled[0] ^ sampled_bit};
    wire [7:0] y_next = y_coupled;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x <= SEED_X;
            y <= SEED_Y;
        end else if (en) begin
            x <= (x_next == 8'h00) ? SEED_X : x_next;
            y <= (y_next == 8'h00) ? SEED_Y : y_next;
        end
    end

    assign out_bit   = x[7] ^ y[7];
    assign out_valid  = en;
    assign state_out  = {y, x};

endmodule
