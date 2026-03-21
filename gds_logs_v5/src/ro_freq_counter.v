`default_nettype none

/**
 * RO Frequency Counter
 * 
 * Measures an asynchronous RO signal by counting its edges over a fixed 
 * time window defined by the system clock.
 */
module ro_freq_counter (
    input  wire        clk,      // System clock (10MHz)
    input  wire        rst_n,    // System reset
    input  wire        ro_in,    // Async RO signal
    output wire [15:0] count     // Measured count over 1024 clk cycles
);

    // 16-bit ripple counter driven by the RO
    // Ripple counters are better for multi-GHz signals in 130nm 
    // as they don't have large carry chains.
    reg [15:0] ro_count;
    always @(posedge ro_in or negedge rst_n) begin
        if (!rst_n)
            ro_count <= 16'd0;
        else
            ro_count <= ro_count + 1'b1;
    end

    // Windowing logic (1024 cycles of 10MHz = 102.4 us)
    reg [9:0]  window_timer;
    reg [15:0] last_ro_count;
    reg [15:0] freq_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            window_timer  <= 10'd0;
            last_ro_count <= 16'd0;
            freq_reg      <= 16'd0;
        end else begin
            if (window_timer == 10'd1023) begin
                // End of 1024-cycle window
                // Difference in ro_count is the number of RO cycles seen
                freq_reg      <= ro_count - last_ro_count;
                last_ro_count <= ro_count;
                window_timer  <= 10'd0;
            end else begin
                window_timer <= window_timer + 1'b1;
            end
        end
    end

    assign count = freq_reg;

endmodule
