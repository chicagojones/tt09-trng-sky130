`default_nettype none

/* verilator lint_off UNUSEDSIGNAL */
/* verilator lint_off UNDRIVEN */

module tt_um_chicagojones_sky26a_trng #(
    parameter INCLUDE_TENT_MAP     = 1,
    parameter INCLUDE_COUPLED_TENT = 1,
    parameter INCLUDE_LOGISTIC     = 1,
    parameter INCLUDE_BERNOULLI    = 1,
    parameter INCLUDE_LORENZ       = 1,
    parameter INCLUDE_LFSR         = 1
) (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

    wire en         = ui_in[3];
    wire auto_en_pin = ui_in[4];
    wire [2:0] man_sel = ui_in[7:5];

    // SPI signals
    wire spi_cs_n   = uio_in[3];
    wire spi_sclk   = uio_in[4];
    wire spi_mosi   = uio_in[5];
    wire spi_miso;

    // UART RX signal
    wire uart_rx_pin = uio_in[2];

    // Sub-module connections
    wire [2:0] ro_sel;
    wire [7:0] ro_raw_signals;
    wire       sampled_bit;

    wire       alarm;
    wire       reset_monitor;

    wire       vn_valid;
    wire       vn_bit;

    wire       uart_tx_out;
    wire       uart_tx_busy;

    // -- Register File & Bus Arbitration --
    // SPI-side register bus
    wire [6:0] spi_reg_addr;
    reg  [7:0] reg_data_in;
    wire [7:0] spi_reg_data_out;
    wire       spi_reg_write_en;

    // UART command parser signals
    wire [7:0] uart_rx_data;
    wire       uart_rx_valid;
    reg  [6:0] uart_reg_addr;
    reg  [7:0] uart_reg_data_out;
    reg        uart_reg_write_en;
    reg        uart_read_done;
    reg        uart_cmd_active;   // 1 when UART owns the register bus

    // Arbitrated register bus (UART takes priority during its command)
    // uart_cmd_active goes low on the same edge as write_en/read_done,
    // so include those in the mux select to keep the address stable.
    wire       uart_bus_own  = uart_cmd_active | uart_reg_write_en | uart_read_done;
    wire [6:0] reg_addr      = uart_bus_own ? uart_reg_addr     : spi_reg_addr;
    wire [7:0] reg_data_out  = uart_bus_own ? uart_reg_data_out : spi_reg_data_out;
    wire       reg_write_en  = uart_reg_write_en | spi_reg_write_en;

    // Control Register (Address 0x13)
    // Bit 0: ro_bypass (1 = single-RO mode, selected by freq_mux_sel)
    // Bit 1: force_manual (1 = ignore auto_en pin)
    // Bit 2: mask_alarm (1 = ignore NIST alarm for auto-tuning)
    // Bits [4:3]: uo_mux_sel
    // Bits [7:5]: cond_sel — conditioning function select
    //   0=VonNeumann, 1=Bypass, 2=Tent, 3=CoupledTent,
    //   4=Logistic, 5=Bernoulli, 6=Lorenz, 7=LFSR
    reg [7:0] ctrl_reg;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ctrl_reg <= 8'h00;
        end else if (reg_write_en && reg_addr == 7'h13) begin
            ctrl_reg <= reg_data_out;
        end
    end

    wire [2:0] cond_sel  = ctrl_reg[7:5];
    wire ro_bypass       = ctrl_reg[0];
    wire force_manual    = ctrl_reg[1];
    wire mask_alarm      = ctrl_reg[2];
    wire [1:0] uo_sel    = ctrl_reg[4:3];

    // Entropy Control Register (Address 0x21)
    // Bit 0: sync_before_xor (1 = sync each RO independently, then XOR)
    // Bit 1: nist_inject_en (1 = override entropy source for NIST monitor)
    // Bit 2: nist_inject_bit (bit value to inject when injection enabled)
    // Bit 3: uart_stream_en (1 = stream random bytes on UART TX, default off)
    // Bits [7:4]: reserved
    reg [7:0] entropy_ctrl_reg;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            entropy_ctrl_reg <= 8'h00;
        else if (reg_write_en && reg_addr == 7'h21)
            entropy_ctrl_reg <= reg_data_out;
    end

    wire sync_before_xor = entropy_ctrl_reg[0];
    wire nist_inject_en  = entropy_ctrl_reg[1];
    wire nist_inject_bit = entropy_ctrl_reg[2];
    wire uart_stream_en  = entropy_ctrl_reg[3];

    // Frequency Mux Control
    reg [2:0] freq_mux_sel;
    reg [2:0] last_freq_mux_sel;
    wire      freq_counter_reset = (freq_mux_sel != last_freq_mux_sel);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            freq_mux_sel <= 3'd0;
            last_freq_mux_sel <= 3'd0;
        end else begin
            last_freq_mux_sel <= freq_mux_sel;
            if (reg_write_en && reg_addr == 7'h10) begin
                freq_mux_sel <= reg_data_out[2:0];
            end
        end
    end

    // Scratchpad Register (Address 0x20) - for SPI link verification
    reg [7:0] scratch_reg;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            scratch_reg <= 8'h00;
        else if (reg_write_en && reg_addr == 7'h20)
            scratch_reg <= reg_data_out;
    end

    // Frequency Counter Output (24-bit)
    wire [23:0] freq_count;

    // Latch-on-read: snapshot freq_count when address 0x00 (LSB) is read.
    // Subsequent reads of 0x01 and 0x02 return from the snapshot, ensuring
    // a consistent 24-bit value. Always read LSB first.
    reg [23:0] freq_count_latch;
    wire freq_latch_trigger = (reg_addr == 7'h00);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            freq_count_latch <= 24'd0;
        else if (freq_latch_trigger)
            freq_count_latch <= freq_count;
    end

    // SPI Follower
    spi_follower spi_inst (
        .clk(clk),
        .rst_n(rst_n),
        .sclk(spi_sclk),
        .cs_n(spi_cs_n),
        .mosi(spi_mosi),
        .miso(spi_miso),
        .reg_addr(spi_reg_addr),
        .reg_data_in(reg_data_in),
        .reg_data_out(spi_reg_data_out),
        .reg_write_en(spi_reg_write_en)
    );

    // -- UART Receiver --
    uart_rx #(
        .BAUD_DIV(87)
    ) uart_rx_inst (
        .clk(clk),
        .rst_n(rst_n),
        .rx(uart_rx_pin),
        .data(uart_rx_data),
        .valid(uart_rx_valid)
    );

    // -- UART Command Parser --
    // Protocol: 2 bytes per command
    //   Byte 1: {W/R_n, addr[6:0]}  (bit 7: 1=write, 0=read)
    //   Byte 2: write_data (for writes) or dummy (for reads)
    // On read: device responds with 1 byte on UART TX
    reg       uart_cmd_is_write;
    reg       uart_cmd_got_first;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            uart_cmd_got_first <= 1'b0;
            uart_cmd_is_write  <= 1'b0;
            uart_reg_addr      <= 7'd0;
            uart_reg_data_out  <= 8'd0;
            uart_reg_write_en  <= 1'b0;
            uart_read_done     <= 1'b0;
            uart_cmd_active    <= 1'b0;
        end else begin
            uart_reg_write_en <= 1'b0;
            uart_read_done    <= 1'b0;

            if (uart_rx_valid) begin
                if (!uart_cmd_got_first) begin
                    // First byte: command
                    uart_reg_addr      <= uart_rx_data[6:0];
                    uart_cmd_is_write  <= uart_rx_data[7];
                    uart_cmd_got_first <= 1'b1;
                    uart_cmd_active    <= 1'b1;
                end else begin
                    // Second byte: data
                    uart_cmd_got_first <= 1'b0;
                    uart_cmd_active    <= 1'b0;
                    if (uart_cmd_is_write) begin
                        uart_reg_data_out <= uart_rx_data;
                        uart_reg_write_en <= 1'b1;
                    end else begin
                        uart_read_done <= 1'b1;
                    end
                end
            end
        end
    end

    // -- UART TX Response Buffer --
    // When a UART read completes, buffer the register value and send via TX
    reg       uart_resp_pending;
    reg [7:0] uart_resp_buf;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            uart_resp_pending <= 1'b0;
            uart_resp_buf     <= 8'd0;
        end else if (uart_read_done) begin
            uart_resp_pending <= 1'b1;
            uart_resp_buf     <= reg_data_in;
        end else if (uart_resp_pending && !uart_tx_busy) begin
            uart_resp_pending <= 1'b0;
        end
    end

    // Suppress random byte streaming unless uart_stream_en is set,
    // and always suppress during UART command processing
    wire       uart_suppress  = uart_cmd_got_first | uart_resp_pending | ~uart_stream_en;
    wire       uart_resp_fire = uart_resp_pending & ~uart_tx_busy;
    wire [7:0] tx_mux_data    = uart_resp_fire ? uart_resp_buf : out_reg;
    wire       tx_mux_trig    = uart_resp_fire | (~uart_suppress & byte_valid & ~uart_tx_busy);

    // Register Read Multiplexer
    always @(*) begin
        case (reg_addr)
            7'h00: reg_data_in = freq_count[7:0];           // LSB (triggers latch)
            7'h01: reg_data_in = freq_count_latch[15:8];  // from snapshot
            7'h02: reg_data_in = freq_count_latch[23:16]; // from snapshot
            7'h10: reg_data_in = {3'b0, alarm, 1'b0, freq_mux_sel};
            7'h11: reg_data_in = out_reg;
            7'h12: reg_data_in = {5'b0, ro_sel};
            7'h13: reg_data_in = ctrl_reg;
            7'h14: reg_data_in = tent_state[15:8];
            7'h15: reg_data_in = coupled_state[15:8]; // X part MSB
            7'h16: reg_data_in = coupled_state[31:24]; // Y part MSB
            7'h17: reg_data_in = logistic_state[15:8];
            7'h18: reg_data_in = bern_state[15:8];
            7'h19: reg_data_in = lorenz_state[15:8];
            7'h1A: reg_data_in = lfsr_state[31:24];
            7'h1D: reg_data_in = {1'b0,
                                  INCLUDE_LFSR[0],
                                  INCLUDE_LORENZ[0],
                                  INCLUDE_BERNOULLI[0],
                                  INCLUDE_LOGISTIC[0],
                                  INCLUDE_COUPLED_TENT[0],
                                  INCLUDE_TENT_MAP[0],
                                  1'b1};  // bit 0 = VN always present
            7'h1B: reg_data_in = {dbg_rct_fail, dbg_apt_fail, dbg_rct_count};
            7'h1C: reg_data_in = dbg_apt_match_count[7:0];
            7'h1E: reg_data_in = {6'b0, dbg_apt_match_count[9:8]};
            7'h20: reg_data_in = scratch_reg;
            7'h21: reg_data_in = entropy_ctrl_reg;
            default: reg_data_in = 8'h00;
        endcase
    end

    // -- UART Transmitter --
    uart_tx #(
        .BAUD_DIV(87)
    ) uart_inst (
        .clk(clk),
        .rst_n(rst_n),
        .data(tx_mux_data),
        .trigger(tx_mux_trig),
        .tx(uart_tx_out),
        .busy(uart_tx_busy)
    );

    // -- Auto-Tuner --
    auto_tuner tuner_inst (
        .clk(clk),
        .rst_n(rst_n),
        .auto_en(force_manual ? 1'b0 : auto_en_pin),
        .manual_sel(man_sel),
        .alarm(mask_alarm ? 1'b0 : alarm),
        .current_sel(ro_sel),
        .reset_monitor(reset_monitor)
    );

    // -- Multi-RO Core (8 ROs) --
    trng_core ro_inst (
        .clk(clk),
        .rst_n(rst_n),
        .en(en),
        .sel(ro_sel),
        .ro_bypass(ro_bypass),
        .sync_before_xor(sync_before_xor),
        .bypass_sel(freq_mux_sel),
        .sampled_bit(sampled_bit),
        .ro_outs(ro_raw_signals)
    );

    // Multiplexed Frequency Counter
    wire ro_to_measure = ro_raw_signals[freq_mux_sel];
    ro_freq_counter fc_inst (
        .clk(clk),
        .rst_n(rst_n & ~freq_counter_reset),
        .ro_in(ro_to_measure),
        .count(freq_count)
    );

    // -- NIST Health Monitor (RCT & APT) --
    wire        nist_bit_in = nist_inject_en ? nist_inject_bit : sampled_bit;
    wire [5:0]  dbg_rct_count;
    wire        dbg_rct_fail;
    wire [9:0]  dbg_apt_match_count;
    wire        dbg_apt_fail;

    nist_health_monitor monitor_inst (
        .clk(clk),
        .rst_n(rst_n),
        .en(en),
        .bit_in(nist_bit_in),
        .reset_alarm(reset_monitor),
        .alarm(alarm),
        .dbg_rct_count(dbg_rct_count),
        .dbg_rct_fail(dbg_rct_fail),
        .dbg_apt_match_count(dbg_apt_match_count),
        .dbg_apt_fail(dbg_apt_fail)
    );

    // -- Von Neumann Whitener (always present) --
    von_neumann vn_inst (
        .clk(clk),
        .rst_n(rst_n),
        .en(en),
        .raw_bit(sampled_bit),
        .valid(vn_valid),
        .out_bit(vn_bit)
    );

    // -- Conditioner Module Wires --
    wire tent_bit, tent_valid;
    wire [15:0] tent_state;

    wire coupled_bit, coupled_valid;
    wire [31:0] coupled_state;

    wire logistic_bit, logistic_valid;
    wire [15:0] logistic_state;

    wire bern_bit, bern_valid;
    wire [15:0] bern_state;

    wire lorenz_bit, lorenz_valid;
    wire [15:0] lorenz_state;

    wire lfsr_bit, lfsr_valid;
    wire [31:0] lfsr_state;

    // -- Conditioner Instantiations (parameterized) --
    generate
        if (INCLUDE_TENT_MAP) begin : gen_tent
            cond_tent_map #(.WIDTH(16)) tent_inst (
                .clk(clk), .rst_n(rst_n), .en(en),
                .sampled_bit(sampled_bit),
                .out_bit(tent_bit), .out_valid(tent_valid),
                .state_out(tent_state)
            );
        end else begin : gen_no_tent
            assign tent_bit = 1'b0;
            assign tent_valid = 1'b0;
            assign tent_state = 8'h00;
        end

        if (INCLUDE_COUPLED_TENT) begin : gen_coupled
            cond_coupled_tent #(.WIDTH(16)) coupled_inst (
                .clk(clk), .rst_n(rst_n), .en(en),
                .sampled_bit(sampled_bit),
                .out_bit(coupled_bit), .out_valid(coupled_valid),
                .state_out(coupled_state)
            );
        end else begin : gen_no_coupled
            assign coupled_bit = 1'b0;
            assign coupled_valid = 1'b0;
            assign coupled_state = 16'h0000;
        end

        if (INCLUDE_LOGISTIC) begin : gen_logistic
            cond_logistic #(.WIDTH(16)) logistic_inst (
                .clk(clk), .rst_n(rst_n), .en(en),
                .sampled_bit(sampled_bit),
                .out_bit(logistic_bit), .out_valid(logistic_valid),
                .state_out(logistic_state)
            );
        end else begin : gen_no_logistic
            assign logistic_bit = 1'b0;
            assign logistic_valid = 1'b0;
            assign logistic_state = 8'h00;
        end

        if (INCLUDE_BERNOULLI) begin : gen_bernoulli
            cond_bernoulli #(.WIDTH(16)) bern_inst (
                .clk(clk), .rst_n(rst_n), .en(en),
                .sampled_bit(sampled_bit),
                .out_bit(bern_bit), .out_valid(bern_valid),
                .state_out(bern_state)
            );
        end else begin : gen_no_bernoulli
            assign bern_bit = 1'b0;
            assign bern_valid = 1'b0;
            assign bern_state = 8'h00;
        end

        if (INCLUDE_LORENZ) begin : gen_lorenz
            cond_lorenz #(.WIDTH(16)) lorenz_inst (
                .clk(clk), .rst_n(rst_n), .en(en),
                .sampled_bit(sampled_bit),
                .out_bit(lorenz_bit), .out_valid(lorenz_valid),
                .state_out(lorenz_state)
            );
        end else begin : gen_no_lorenz
            assign lorenz_bit = 1'b0;
            assign lorenz_valid = 1'b0;
            assign lorenz_state = 16'h0000;
        end

        if (INCLUDE_LFSR) begin : gen_lfsr
            cond_lfsr #(.WIDTH(32)) lfsr_inst (
                .clk(clk), .rst_n(rst_n), .en(en),
                .sampled_bit(sampled_bit),
                .out_bit(lfsr_bit), .out_valid(lfsr_valid),
                .state_out(lfsr_state)
            );
        end else begin : gen_no_lfsr
            assign lfsr_bit = 1'b0;
            assign lfsr_valid = 1'b0;
            assign lfsr_state = 8'h00;
        end
    endgenerate

    // -- Conditioning Output Mux (selected by cond_sel) --
    reg cond_bit;
    reg cond_valid;

    always @(*) begin
        case (cond_sel)
            3'd0: begin cond_bit = vn_bit;       cond_valid = vn_valid;       end // Von Neumann
            3'd1: begin cond_bit = sampled_bit;   cond_valid = 1'b1;          end // Bypass
            3'd2: begin cond_bit = tent_bit;      cond_valid = tent_valid;    end // Tent map
            3'd3: begin cond_bit = coupled_bit;   cond_valid = coupled_valid; end // Coupled tent
            3'd4: begin cond_bit = logistic_bit;  cond_valid = logistic_valid;end // Logistic
            3'd5: begin cond_bit = bern_bit;      cond_valid = bern_valid;    end // Bernoulli
            3'd6: begin cond_bit = lorenz_bit;    cond_valid = lorenz_valid;  end // Lorenz
            3'd7: begin cond_bit = lfsr_bit;      cond_valid = lfsr_valid;    end // LFSR
        endcase
    end

    wire active_bit   = cond_bit;
    wire active_valid = cond_valid;

    // -- 8-Bit Shift Register (Serial to Parallel) --
    reg [7:0] shift_reg;
    reg [7:0] out_reg;
    reg [2:0] bit_count;
    reg       byte_valid;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            shift_reg  <= 8'd0;
            out_reg    <= 8'd0;
            bit_count  <= 3'd0;
            byte_valid <= 1'b0;
        end else begin
            byte_valid <= 1'b0;
            if (en && active_valid) begin
                shift_reg <= {shift_reg[6:0], active_bit};
                if (bit_count == 3'd7) begin
                    out_reg    <= {shift_reg[6:0], active_bit};
                    byte_valid <= 1'b1;
                    bit_count  <= 3'd0;
                end else begin
                    bit_count <= bit_count + 1'b1;
                end
            end
        end
    end

    // -- Output Assignments --
    // Output Mux logic for debugging
    reg [7:0] final_uo_out;
    always @(*) begin
        case (uo_sel)
            2'b00:   final_uo_out = out_reg;
            2'b01:   final_uo_out = freq_count[7:0];
            2'b10:   final_uo_out = {6'b0, alarm, vn_valid};
            2'b11:   final_uo_out = {7'b0, sampled_bit};
            default: final_uo_out = out_reg;
        endcase
    end

    assign uo_out = final_uo_out;
    
    // Bidirectional pin configuration
    assign uio_out[0]   = byte_valid;
    assign uio_out[1]   = uart_tx_out;
    assign uio_out[6]   = spi_miso;
    assign uio_out[2]   = 1'b0;
    assign uio_out[5:3] = 3'b0;
    assign uio_out[7]   = 1'b0;
    
    assign uio_oe       = 8'b01000011; 

    wire _unused = &{ui_in[2:0], uio_in[7], ena, spi_mosi, spi_reg_data_out[7:3]};

endmodule

/* 
 * Multi-RO Core 
 */
module trng_core (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       en,
    input  wire [2:0] sel,
    input  wire       ro_bypass,       // 1 = single-RO mode (bypass XOR)
    input  wire       sync_before_xor, // 1 = sync each RO independently, then XOR
    input  wire [2:0] bypass_sel,      // which RO to use in bypass mode
    output wire       sampled_bit,
    output wire [7:0] ro_outs
);

    // RO 0: Tunable (3 to 31 stages)
    ro_tunable ro0 (.clk(clk), .rst_n(rst_n), .en(en), .sel(sel), .ro_out(ro_outs[0]));

    // RO 1-7: Fixed lengths (Primes)
    ro_fixed #(.LENGTH(13), .DRIVE(1)) ro1 (.clk(clk), .rst_n(rst_n), .en(en), .ro_out(ro_outs[1]));
    ro_fixed #(.LENGTH(17), .DRIVE(2)) ro2 (.clk(clk), .rst_n(rst_n), .en(en), .ro_out(ro_outs[2]));
    ro_fixed #(.LENGTH(19), .DRIVE(4)) ro3 (.clk(clk), .rst_n(rst_n), .en(en), .ro_out(ro_outs[3]));
    ro_fixed #(.LENGTH(23), .DRIVE(1)) ro4 (.clk(clk), .rst_n(rst_n), .en(en), .ro_out(ro_outs[4]));
    ro_fixed #(.LENGTH(29), .DRIVE(2)) ro5 (.clk(clk), .rst_n(rst_n), .en(en), .ro_out(ro_outs[5]));
    ro_fixed #(.LENGTH(31), .DRIVE(4)) ro6 (.clk(clk), .rst_n(rst_n), .en(en), .ro_out(ro_outs[6]));
    ro_fixed #(.LENGTH(37), .DRIVE(1)) ro7 (.clk(clk), .rst_n(rst_n), .en(en), .ro_out(ro_outs[7]));

    // --- Path A: XOR all ROs, then 4-stage sync (default) ---
    wire ro_combined = ^ro_outs;
    reg [3:0] sync_post_xor;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            sync_post_xor <= 4'b0;
        else
            sync_post_xor <= {sync_post_xor[2:0], ro_combined};
    end

    // --- Path B: 2-stage sync per RO, then XOR ---
    reg [7:0] ro_sync_s1, ro_sync_s2;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ro_sync_s1 <= 8'b0;
            ro_sync_s2 <= 8'b0;
        end else begin
            ro_sync_s1 <= ro_outs;
            ro_sync_s2 <= ro_sync_s1;
        end
    end

    // --- Path C: Single RO bypass with 4-stage sync ---
    wire ro_selected = ro_outs[bypass_sel];
    reg [3:0] sync_bypass;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            sync_bypass <= 4'b0;
        else
            sync_bypass <= {sync_bypass[2:0], ro_selected};
    end

    // Output selection: bypass takes priority, then sync_before_xor, else default
    assign sampled_bit = ro_bypass      ? sync_bypass[3] :
                         sync_before_xor ? ^ro_sync_s2   :
                         sync_post_xor[3];

endmodule

/* 
 * Tunable Ring Oscillator
 */
module ro_tunable (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       en,
    input  wire [2:0] sel,
    output wire       ro_out
);
    `ifdef SIM
    reg sim_ro;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) sim_ro <= 1'b0;
        else if (en) sim_ro <= ~sim_ro;
    end
    assign ro_out = sim_ro;
    `else
    (* keep *) wire [31:0] chain;
    wire        feedback;

    assign feedback = (sel == 3'd0) ? chain[2]  :
                      (sel == 3'd1) ? chain[6]  :
                      (sel == 3'd2) ? chain[10] :
                      (sel == 3'd3) ? chain[14] :
                      (sel == 3'd4) ? chain[18] :
                      (sel == 3'd5) ? chain[22] :
                      (sel == 3'd6) ? chain[26] :
                                      chain[30];

    /* verilator lint_off PINMISSING */
    sky130_fd_sc_hd__nand2_1 nand_inst (.A(feedback), .B(en), .Y(chain[0]));

    genvar i;
    generate
        for (i = 1; i < 32; i = i + 1) begin : ro_inverters
            sky130_fd_sc_hd__inv_1 inv_inst (.A(chain[i-1]), .Y(chain[i]));
        end
    endgenerate
    /* verilator lint_on PINMISSING */

    assign ro_out = chain[0];
    `endif
endmodule

/* 
 * Fixed Length Ring Oscillator
 */
module ro_fixed #(parameter LENGTH = 15, parameter DRIVE = 1) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       en,
    output wire       ro_out
);
    `ifdef SIM
    reg sim_ro;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) sim_ro <= 1'b0;
        else if (en) sim_ro <= ~sim_ro;
    end
    assign ro_out = sim_ro;
    `else
    (* keep *) wire [LENGTH:0] chain;

    /* verilator lint_off PINMISSING */
    sky130_fd_sc_hd__nand2_1 nand_inst (.A(chain[LENGTH-1]), .B(en), .Y(chain[0]));

    genvar i;
    generate
        for (i = 1; i < LENGTH; i = i + 1) begin : ro_inverters
            if (DRIVE == 4)
                sky130_fd_sc_hd__inv_4 inv_inst (.A(chain[i-1]), .Y(chain[i]));
            else if (DRIVE == 2)
                sky130_fd_sc_hd__inv_2 inv_inst (.A(chain[i-1]), .Y(chain[i]));
            else
                sky130_fd_sc_hd__inv_1 inv_inst (.A(chain[i-1]), .Y(chain[i]));
        end
    endgenerate
    /* verilator lint_on PINMISSING */

    assign ro_out = chain[0];
    `endif
endmodule
