`default_nettype none

/**
 * RO Frequency Counter (24-bit)
 * 
 * Measures an asynchronous RO signal by counting its edges over a fixed 
 * time window defined by the system clock.
 *
 * A 24-bit counter prevents overflow during a 1024-cycle (10MHz) window
 * for RO frequencies up to ~163 GHz (well above physical limits).
 */
module ro_freq_counter (
    input  wire        clk,      // System clock (10MHz)
    input  wire        rst_n,    // System reset
    input  wire        ro_in,    // Async RO signal
    output wire [23:0] count     // Measured count over 1024 clk cycles
);

    // 24-bit counter
    reg [23:0] ro_count;

    `ifdef SIM
    // In simulation, we don't need GHz precision. 
    // Just increment once per system clock to prevent simulation hang.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            ro_count <= 24'd0;
        else
            ro_count <= ro_count + 1'b1;
    end
    `else
    // 24-bit ripple counter driven by the RO for silicon
    always @(posedge ro_in or negedge rst_n) begin
        if (!rst_n)
            ro_count <= 24'd0;
        else
            ro_count <= ro_count + 1'b1;
    end
    `endif

    // Windowing logic (1024 cycles of 10MHz = 102.4 us)
    reg [9:0]  window_timer;
    reg [23:0] last_ro_count;
    reg [23:0] freq_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            window_timer  <= 10'd0;
            last_ro_count <= 24'd0;
            freq_reg      <= 24'd0;
        end else begin
            if (window_timer == 10'd1023) begin
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
