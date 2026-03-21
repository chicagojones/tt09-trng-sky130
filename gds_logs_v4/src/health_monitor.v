`default_nettype none

/* 
 * 1024-bit Window Health Monitor
 * 
 * Tracks the running disparity (balance of 1s and 0s) over a 1024-clock cycle
 * window of the raw sampled bit. If the count of '1's falls outside an 
 * acceptable threshold, it asserts the `alarm` signal.
 */
module health_monitor (
    input  wire clk,
    input  wire rst_n,
    input  wire en,         // Only process when enabled
    input  wire bit_in,     // Raw sampled bit
    input  wire reset_alarm,// Clear the alarm state manually or via auto-tuner
    output reg  alarm       // High if entropy is poor
);

    // 10-bit counter to track the 1024-cycle window (0 to 1023)
    reg [9:0] window_count;
    
    // 10-bit counter for the number of '1's seen in the window
    reg [9:0] ones_count;

    // Thresholds for the balance test.
    // Ideal balance is 512. 
    // We allow a margin of error (e.g., < 400 or > 624).
    localparam THRESHOLD_LOW  = 10'd400;
    localparam THRESHOLD_HIGH = 10'd624;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            window_count <= 10'd0;
            ones_count   <= 10'd0;
            alarm        <= 1'b0;
        end else begin
            if (reset_alarm) begin
                window_count <= 10'd0;
                ones_count   <= 10'd0;
                alarm        <= 1'b0;
            end else if (en) begin
                // Evaluate at the end of the 1024-bit window
                if (window_count == 10'd1023) begin
                    if (ones_count < THRESHOLD_LOW || ones_count > THRESHOLD_HIGH) begin
                        alarm <= 1'b1;
                    end else begin
                        alarm <= 1'b0;
                    end
                    // Reset for the next window
                    window_count <= 10'd0;
                    ones_count   <= 10'd0;
                end else begin
                    // Accumulate
                    window_count <= window_count + 1'b1;
                    if (bit_in) begin
                        ones_count <= ones_count + 1'b1;
                    end
                end
            end
        end
    end

endmodule
