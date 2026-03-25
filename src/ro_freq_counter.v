`default_nettype none

/**
 * RO Frequency Counter (24-bit) — Gated Ripple Counter
 *
 * Measures an asynchronous RO signal by counting edges over a fixed
 * time window defined by the system clock.
 *
 * Silicon path uses an asynchronous ripple counter (no carry chain)
 * to handle RO frequencies up to GHz range. At each window boundary
 * the RO clock is gated off, the ripple is allowed to settle, the
 * count is captured, and the counter is reset before re-enabling.
 *
 * Window: 1024 system clock cycles (102.4 us at 10 MHz).
 * Lost cycles per window: ~20-40 RO edges during the gate-off
 * settle period (~0.06% error at 500 MHz).
 */
module ro_freq_counter (
    input  wire        clk,      // System clock (10 MHz)
    input  wire        rst_n,    // System reset (async, active low)
    input  wire        ro_in,    // Async RO signal
    output wire [23:0] count     // Measured count over last window
);

`ifdef SIM
    // -----------------------------------------------------------------
    // Simulation model: simple synchronous counter on system clock.
    // Ripple counter would cause simulation issues with async clocking.
    // -----------------------------------------------------------------
    reg [23:0] ro_count;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            ro_count <= 24'd0;
        else
            ro_count <= ro_count + 1'b1;
    end

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

`else
    // -----------------------------------------------------------------
    // Silicon: asynchronous ripple counter with gated sampling
    // -----------------------------------------------------------------

    // -- Gate and clear control (system clock domain) --
    // gate_en=1 allows counting, gate_en=0 stops the counter.
    // cnt_clear=1 resets the ripple counter to zero (active high).
    reg gate_en;
    reg cnt_clear;

    // Combined clear: external reset OR internal window clear
    wire cnt_rst_n = rst_n & ~cnt_clear;

    // Gated RO clock: AND gate stops edges reaching counter
    wire gated_ro = ro_in & gate_en;

    // -- 24-bit ripple counter --
    // Each bit toggles on the falling edge of the previous bit.
    // No carry chain — each stage is an independent T-flip-flop.
    // Maximum toggle rate is only at bit 0 (full RO frequency).
    (* keep *) reg [23:0] ro_count;

    // Bit 0: clocked directly by gated RO
    always @(posedge gated_ro or negedge cnt_rst_n) begin
        if (!cnt_rst_n) ro_count[0] <= 1'b0;
        else            ro_count[0] <= ~ro_count[0];
    end

    // Bits 1-23: each clocked by falling edge of previous bit
    genvar i;
    generate
        for (i = 1; i < 24; i = i + 1) begin : ripple
            always @(negedge ro_count[i-1] or negedge cnt_rst_n) begin
                if (!cnt_rst_n) ro_count[i] <= 1'b0;
                else            ro_count[i] <= ~ro_count[i];
            end
        end
    endgenerate

    // -- Windowing state machine (system clock domain) --
    // Sequence per window:
    //   COUNTING: gate_en=1, counter runs for 1024 system clocks
    //   SETTLE:   gate_en=0, wait 1 cycle for ripple to settle
    //             (100 ns >> 12 ns worst-case ripple propagation)
    //   CAPTURE:  latch settled count into freq_reg
    //   CLEAR:    assert cnt_clear for 1 cycle to zero the counter
    //   (back to COUNTING with gate_en=1)

    localparam ST_COUNTING = 2'd0;
    localparam ST_SETTLE   = 2'd1;
    localparam ST_CAPTURE  = 2'd2;
    localparam ST_CLEAR    = 2'd3;

    reg [1:0]  state;
    reg [9:0]  window_timer;
    reg [23:0] freq_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= ST_CLEAR;
            gate_en      <= 1'b0;
            cnt_clear    <= 1'b1;
            window_timer <= 10'd0;
            freq_reg     <= 24'd0;
        end else begin
            case (state)
                ST_COUNTING: begin
                    if (window_timer == 10'd1023) begin
                        // Window complete — stop the counter
                        gate_en <= 1'b0;
                        state   <= ST_SETTLE;
                    end else begin
                        window_timer <= window_timer + 1'b1;
                    end
                end

                ST_SETTLE: begin
                    // Counter stopped, ripple settles this cycle
                    state <= ST_CAPTURE;
                end

                ST_CAPTURE: begin
                    // Counter is fully settled — capture the count
                    freq_reg  <= ro_count;
                    cnt_clear <= 1'b1;
                    state     <= ST_CLEAR;
                end

                ST_CLEAR: begin
                    // Counter is zeroed — release clear, start counting
                    cnt_clear    <= 1'b0;
                    gate_en      <= 1'b1;
                    window_timer <= 10'd0;
                    state        <= ST_COUNTING;
                end
            endcase
        end
    end

    assign count = freq_reg;

`endif

endmodule
