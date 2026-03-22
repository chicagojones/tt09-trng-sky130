`default_nettype none

module uart_rx #(
    parameter BAUD_DIV = 87 // 10MHz / 115200 baud
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       rx,
    output reg  [7:0] data,
    output reg        valid
);

    // Sample at mid-bit for reliable capture
    localparam HALF_BAUD = BAUD_DIV / 2;

    reg [1:0] rx_sync;
    wire      rx_in = rx_sync[1];

    // 2-stage synchronizer for async RX input
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            rx_sync <= 2'b11;
        else
            rx_sync <= {rx_sync[0], rx};
    end

    localparam IDLE  = 2'd0,
               START = 2'd1,
               DATA  = 2'd2,
               STOP  = 2'd3;

    reg [1:0]  state;
    reg [15:0] baud_count;
    reg [2:0]  bit_idx;
    reg [7:0]  shift_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= IDLE;
            baud_count <= 16'd0;
            bit_idx    <= 3'd0;
            shift_reg  <= 8'd0;
            data       <= 8'd0;
            valid      <= 1'b0;
        end else begin
            valid <= 1'b0;

            case (state)
                IDLE: begin
                    if (rx_in == 1'b0) begin
                        // Falling edge detected — start bit
                        baud_count <= 16'd0;
                        state      <= START;
                    end
                end

                START: begin
                    // Wait to mid-start-bit to confirm it's real
                    if (baud_count == HALF_BAUD[15:0]) begin
                        if (rx_in == 1'b0) begin
                            // Valid start bit
                            baud_count <= 16'd0;
                            bit_idx    <= 3'd0;
                            state      <= DATA;
                        end else begin
                            // False start — glitch
                            state <= IDLE;
                        end
                    end else begin
                        baud_count <= baud_count + 1'b1;
                    end
                end

                DATA: begin
                    if (baud_count == BAUD_DIV[15:0] - 1) begin
                        baud_count <= 16'd0;
                        // Sample at mid-bit (we started counting from mid-start-bit)
                        shift_reg <= {rx_in, shift_reg[7:1]}; // LSB first
                        if (bit_idx == 3'd7) begin
                            state <= STOP;
                        end else begin
                            bit_idx <= bit_idx + 1'b1;
                        end
                    end else begin
                        baud_count <= baud_count + 1'b1;
                    end
                end

                STOP: begin
                    if (baud_count == BAUD_DIV[15:0] - 1) begin
                        // Stop bit period done — output data regardless of stop bit value
                        // (being lenient on stop bit allows back-to-back frames)
                        data  <= shift_reg;
                        valid <= 1'b1;
                        state <= IDLE;
                    end else begin
                        baud_count <= baud_count + 1'b1;
                    end
                end
            endcase
        end
    end

endmodule
