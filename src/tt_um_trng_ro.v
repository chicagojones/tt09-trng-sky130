`default_nettype none

/* verilator lint_off UNUSEDSIGNAL */
/* verilator lint_off UNDRIVEN */

module tt_um_chicagojones_tt09_trng_sky130 (
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

    // Sub-module connections
    wire [2:0] ro_sel;
    wire [7:0] ro_raw_signals;
    wire       sampled_bit;
    
    wire       alarm;
    wire       reset_monitor;

    wire       vn_valid;
    wire       vn_bit;

    wire       uart_tx_out;

    // -- Register File & SPI --
    wire [6:0] reg_addr;
    reg  [7:0] reg_data_in;
    wire [7:0] reg_data_out;
    wire       reg_write_en;

    // Control Register (Address 0x13)
    // Bit 0: bypass_vn (1 = use raw sampled bits)
    // Bit 1: force_manual (1 = ignore auto_en pin)
    // Bit 2: mask_alarm (1 = ignore NIST alarm for auto-tuning)
    // Bits [4:3]: uo_mux_sel
    reg [7:0] ctrl_reg;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ctrl_reg <= 8'h00;
        end else if (reg_write_en && reg_addr == 7'h13) begin
            ctrl_reg <= reg_data_out;
        end
    end

    wire bypass_vn    = ctrl_reg[0];
    wire force_manual = ctrl_reg[1];
    wire mask_alarm   = ctrl_reg[2];
    wire [1:0] uo_sel  = ctrl_reg[4:3];

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

    // SPI Follower
    spi_follower spi_inst (
        .clk(clk),
        .rst_n(rst_n),
        .sclk(spi_sclk),
        .cs_n(spi_cs_n),
        .mosi(spi_mosi),
        .miso(spi_miso),
        .reg_addr(reg_addr),
        .reg_data_in(reg_data_in),
        .reg_data_out(reg_data_out),
        .reg_write_en(reg_write_en)
    );

    // Register Read Multiplexer
    always @(*) begin
        case (reg_addr)
            7'h00: reg_data_in = freq_count[7:0];
            7'h01: reg_data_in = freq_count[15:8];
            7'h02: reg_data_in = freq_count[23:16];
            7'h10: reg_data_in = {3'b0, alarm, 1'b0, freq_mux_sel};
            7'h11: reg_data_in = out_reg;
            7'h12: reg_data_in = {5'b0, ro_sel};
            7'h13: reg_data_in = ctrl_reg;
            7'h20: reg_data_in = scratch_reg;
            default: reg_data_in = 8'h00;
        endcase
    end

    // -- UART Transmitter --
    uart_tx #(
        .BAUD_DIV(87)
    ) uart_inst (
        .clk(clk),
        .rst_n(rst_n),
        .data(out_reg),
        .trigger(byte_valid),
        .tx(uart_tx_out),
        .busy()
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
        .sampled_bit(sampled_bit),
        .ro_outs(ro_raw_signals)
    );

    // Multiplexed Frequency Counter
    wire ro_to_measure = ro_raw_signals[freq_mux_sel];
    ro_freq_counter fc_inst (
        .clk(clk),
        .rst_n(rst_n | ~freq_counter_reset),
        .ro_in(ro_to_measure),
        .count(freq_count)
    );

    // -- NIST Health Monitor (RCT & APT) --
    nist_health_monitor monitor_inst (
        .clk(clk),
        .rst_n(rst_n),
        .en(en),
        .bit_in(sampled_bit),
        .reset_alarm(reset_monitor),
        .alarm(alarm)
    );

    // -- Von Neumann Whitener --
    von_neumann vn_inst (
        .clk(clk),
        .rst_n(rst_n),
        .en(en),
        .raw_bit(sampled_bit),
        .valid(vn_valid),
        .out_bit(vn_bit)
    );

    // -- 8-Bit Shift Register (Serial to Parallel) --
    reg [7:0] shift_reg;
    reg [7:0] out_reg;
    reg [2:0] bit_count;
    reg       byte_valid;

    // Use either whitened or raw sampled bits based on ctrl_reg
    wire active_bit   = bypass_vn ? sampled_bit : vn_bit;
    wire active_valid = bypass_vn ? 1'b1        : vn_valid;

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

    wire _unused = &{ui_in[2:0], uio_in[2], uio_in[7], ena, spi_mosi, reg_data_out[7:3]};

endmodule

/* 
 * Multi-RO Core 
 */
module trng_core (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       en,
    input  wire [2:0] sel,
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

    // XOR tree to mix the entropy
    wire ro_combined = ^ro_outs;

    // 4-stage Synchronizer
    reg [3:0] sync_regs;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            sync_regs <= 4'b0;
        else
            sync_regs <= {sync_regs[2:0], ro_combined};
    end

    assign sampled_bit = sync_regs[3];

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
