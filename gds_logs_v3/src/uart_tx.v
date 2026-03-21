`default_nettype none

module uart_tx #(
    parameter BAUD_DIV = 87 // 10MHz / 115200 baud
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] data,
    input  wire       trigger,
    output reg        tx,
    output wire       busy
);

    reg [3:0] bit_idx;
    reg [7:0] shift_reg;
    reg [15:0] baud_count;
    reg       sending;

    assign busy = sending;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx         <= 1'b1;
            bit_idx    <= 4'd0;
            shift_reg  <= 8'd0;
            baud_count <= 16'd0;
            sending    <= 1'b0;
        end else begin
            if (!sending) begin
                tx <= 1'b1;
                if (trigger) begin
                    shift_reg  <= data;
                    sending    <= 1'b1;
                    baud_count <= 16'd0;
                    bit_idx    <= 4'd0;
                    tx         <= 1'b0; // Start bit
                end
            end else begin
                if (baud_count < BAUD_DIV - 1) begin
                    baud_count <= baud_count + 1'b1;
                end else begin
                    baud_count <= 16'd0;
                    if (bit_idx < 4'd8) begin
                        tx        <= shift_reg[0];
                        shift_reg <= {1'b0, shift_reg[7:1]};
                        bit_idx   <= bit_idx + 1'b1;
                    end else if (bit_idx == 4'd8) begin
                        tx      <= 1'b1; // Stop bit
                        bit_idx <= bit_idx + 1'b1;
                    end else begin
                        sending <= 1'b0;
                    end
                end
            end
        end
    end

endmodule
