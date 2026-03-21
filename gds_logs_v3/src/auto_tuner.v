`default_nettype none

/* 
 * Auto-Tuner FSM
 * 
 * Controls the tuning bits `sel` for the Ring Oscillators.
 * In manual mode, it passes the external `manual_sel` through.
 * In auto mode, if an `alarm` is received, it increments its internal 
 * `auto_sel` state to try a different RO feedback length, and issues
 * a `reset_monitor` pulse to clear the alarm and restart the evaluation window.
 */
module auto_tuner (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       auto_en,      // 1 = Auto Mode, 0 = Manual Mode
    input  wire [2:0] manual_sel,   // Selection from external pins
    input  wire       alarm,        // Alarm from health monitor
    output wire [2:0] current_sel,  // Driven to the ROs
    output reg        reset_monitor // Pulse to clear health monitor
);

    reg [2:0] auto_sel_reg;
    reg       alarm_handled;

    assign current_sel = auto_en ? auto_sel_reg : manual_sel;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            auto_sel_reg  <= 3'd0;
            reset_monitor <= 1'b0;
            alarm_handled <= 1'b0;
        end else begin
            reset_monitor <= 1'b0; // Default: no pulse
            
            // Re-arm when the alarm is cleared
            if (!alarm) begin
                alarm_handled <= 1'b0;
            end

            // Only react to alarms in auto mode, and only once per alarm assertion
            if (auto_en && alarm && !alarm_handled) begin
                auto_sel_reg  <= auto_sel_reg + 1'b1;
                reset_monitor <= 1'b1; // Trigger a reset of the health monitor window
                alarm_handled <= 1'b1; // Mark handled so we don't spin rapidly
            end
        end
    end

endmodule
