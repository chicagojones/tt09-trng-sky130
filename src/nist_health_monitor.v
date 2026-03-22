`default_nettype none

/* 
 * NIST SP 800-90B Compliant Health Monitor
 * 
 * Implements two mandatory continuous health tests:
 * 1. Repetition Count Test (RCT): Detects stuck-at failures.
 * 2. Adaptive Proportion Test (APT): Detects bias over a window.
 */
module nist_health_monitor (
    input  wire clk,
    input  wire rst_n,
    input  wire en,             // Only process when enabled
    input  wire bit_in,         // Raw sampled bit
    input  wire reset_alarm,    // Clear alarm
    output reg  alarm,          // High if RCT or APT fails
    output wire [5:0] dbg_rct_count,
    output wire       dbg_rct_fail,
    output wire [9:0] dbg_apt_match_count,
    output wire       dbg_apt_fail
);

    // --- Repetition Count Test (RCT) ---
    // Cutoff C = 32. 
    reg       rct_last_bit;
    reg [5:0] rct_count;
    reg       rct_fail;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rct_last_bit <= 1'b0;
            rct_count    <= 6'd1;
            rct_fail     <= 1'b0;
        end else if (reset_alarm) begin
            rct_count    <= 6'd1;
            rct_fail     <= 1'b0;
        end else if (en) begin
            if (bit_in == rct_last_bit) begin
                if (rct_count < 6'd63) begin
                    rct_count <= rct_count + 1'b1;
                end
                if (rct_count >= 6'd31) begin // This bit makes it 32
                    rct_fail <= 1'b1;
                end
            end else begin
                rct_last_bit <= bit_in;
                rct_count    <= 6'd1;
            end
        end
    end

    // --- Adaptive Proportion Test (APT) ---
    // Window W = 1024. Cutoff C = 600.
    reg [9:0] apt_window_count;
    reg [9:0] apt_match_count;
    reg       apt_target_bit;
    reg       apt_fail;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            apt_window_count <= 10'd0;
            apt_match_count  <= 10'd0;
            apt_target_bit   <= 1'b0;
            apt_fail         <= 1'b0;
        end else if (reset_alarm) begin
            apt_window_count <= 10'd0;
            apt_match_count  <= 10'd0;
            apt_fail         <= 1'b0;
        end else if (en) begin
            if (apt_window_count == 10'd0) begin
                // Start of window
                apt_target_bit   <= bit_in;
                apt_match_count  <= 10'd1;
                apt_window_count <= 10'd1;
            end else begin
                if (bit_in == apt_target_bit) begin
                    apt_match_count <= apt_match_count + 1'b1;
                end
                
                if (apt_match_count >= 10'd600) begin
                    apt_fail <= 1'b1;
                end

                if (apt_window_count == 10'd1023) begin
                    apt_window_count <= 10'd0; // Reset window
                end else begin
                    apt_window_count <= apt_window_count + 1'b1;
                end
            end
        end
    end

    // Combined alarm
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            alarm <= 1'b0;
        else
            alarm <= rct_fail | apt_fail;
    end

    // Debug outputs
    assign dbg_rct_count     = rct_count;
    assign dbg_rct_fail      = rct_fail;
    assign dbg_apt_match_count = apt_match_count;
    assign dbg_apt_fail      = apt_fail;

endmodule
