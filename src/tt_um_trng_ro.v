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
    wire auto_en    = ui_in[4];
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

    // Frequency Counter Outputs (24-bit each)
    wire [23:0] freq_counts [7:0];

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

    // Register Read Multiplexer (Extended for 24-bit counts)
    always @(*) begin
        case (reg_addr)
            // Low Bytes (0x00 - 0x07)
            7'h00: reg_data_in = freq_counts[0][7:0];
            7'h01: reg_data_in = freq_counts[1][7:0];
            7'h02: reg_data_in = freq_counts[2][7:0];
            7'h03: reg_data_in = freq_counts[3][7:0];
            7'h04: reg_data_in = freq_counts[4][7:0];
            7'h05: reg_data_in = freq_counts[5][7:0];
            7'h06: reg_data_in = freq_counts[6][7:0];
            7'h07: reg_data_in = freq_counts[7][7:0];
            
            // Middle Bytes (0x08 - 0x0F)
            7'h08: reg_data_in = freq_counts[0][15:8];
            7'h09: reg_data_in = freq_counts[1][15:8];
            7'h0A: reg_data_in = freq_counts[2][15:8];
            7'h0B: reg_data_in = freq_counts[3][15:8];
            7'h0C: reg_data_in = freq_counts[4][15:8];
            7'h0D: reg_data_in = freq_counts[5][15:8];
            7'h0E: reg_data_in = freq_counts[6][15:8];
            7'h0F: reg_data_in = freq_counts[7][15:8];

            // High Bytes (0x18 - 0x1F)
            7'h18: reg_data_in = freq_counts[0][23:16];
            7'h19: reg_data_in = freq_counts[1][23:16];
            7'h1A: reg_data_in = freq_counts[2][23:16];
            7'h1B: reg_data_in = freq_counts[3][23:16];
            7'h1C: reg_data_in = freq_counts[4][23:16];
            7'h1D: reg_data_in = freq_counts[5][23:16];
            7'h1E: reg_data_in = freq_counts[6][23:16];
            7'h1F: reg_data_in = freq_counts[7][23:16];

            7'h10: reg_data_in = {3'b0, alarm, 1'b0, ro_sel}; // Status
            7'h11: reg_data_in = out_reg; // Last random byte
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
        .auto_en(auto_en),
        .manual_sel(man_sel),
        .alarm(alarm),
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

    // Frequency Counters for all 8 ROs
    genvar k;
    generate
        for (k = 0; k < 8; k = k + 1) begin : freq_bank
            ro_freq_counter fc_inst (
                .clk(clk),
                .rst_n(rst_n),
                .ro_in(ro_raw_signals[k]),
                .count(freq_counts[k])
            );
        end
    endgenerate

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

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            shift_reg  <= 8'd0;
            out_reg    <= 8'd0;
            bit_count  <= 3'd0;
            byte_valid <= 1'b0;
        end else begin
            byte_valid <= 1'b0;
            if (en && vn_valid) begin
                shift_reg <= {shift_reg[6:0], vn_bit};
                if (bit_count == 3'd7) begin
                    out_reg    <= {shift_reg[6:0], vn_bit};
                    byte_valid <= 1'b1;
                    bit_count  <= 3'd0;
                end else begin
                    bit_count <= bit_count + 1'b1;
                end
            end
        end
    end

    // -- Output Assignments --
    assign uo_out = out_reg;
    
    // Bidirectional pin configuration
    assign uio_out[0]   = byte_valid;
    assign uio_out[1]   = uart_tx_out;
    assign uio_out[6]   = spi_miso;
    assign uio_out[2]   = 1'b0;
    assign uio_out[5:3] = 3'b0;
    assign uio_out[7]   = 1'b0;
    
    assign uio_oe       = 8'b01000011; 

    wire _unused = &{ui_in[2:0], uio_in[2], uio_in[7], ena, spi_mosi};

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
    ro_tunable ro0 (.en(en), .sel(sel), .ro_out(ro_outs[0]));

    // RO 1-7: Fixed lengths (Primes)
    ro_fixed #(.LENGTH(13), .DRIVE(1)) ro1 (.en(en), .ro_out(ro_outs[1]));
    ro_fixed #(.LENGTH(17), .DRIVE(2)) ro2 (.en(en), .ro_out(ro_outs[2]));
    ro_fixed #(.LENGTH(19), .DRIVE(4)) ro3 (.en(en), .ro_out(ro_outs[3]));
    ro_fixed #(.LENGTH(23), .DRIVE(1)) ro4 (.en(en), .ro_out(ro_outs[4]));
    ro_fixed #(.LENGTH(29), .DRIVE(2)) ro5 (.en(en), .ro_out(ro_outs[5]));
    ro_fixed #(.LENGTH(31), .DRIVE(4)) ro6 (.en(en), .ro_out(ro_outs[6]));
    ro_fixed #(.LENGTH(37), .DRIVE(1)) ro7 (.en(en), .ro_out(ro_outs[7]));

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
    input  wire       en,
    input  wire [2:0] sel,
    output wire       ro_out
);
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

    `ifdef SIM
    assign chain[0] = ~(feedback & en);
    `else
    /* verilator lint_off PINMISSING */
    sky130_fd_sc_hd__nand2_1 nand_inst (.A(feedback), .B(en), .Y(chain[0]));
    /* verilator lint_on PINMISSING */
    `endif
    
    genvar i;
    generate
        for (i = 1; i < 32; i = i + 1) begin : ro_inverters
            `ifdef SIM
            assign chain[i] = ~chain[i-1];
            `else
            /* verilator lint_off PINMISSING */
            sky130_fd_sc_hd__inv_1 inv_inst (.A(chain[i-1]), .Y(chain[i]));
            /* verilator lint_on PINMISSING */
            `endif
        end
    endgenerate

    assign ro_out = chain[0];
endmodule

/* 
 * Fixed Length Ring Oscillator
 */
module ro_fixed #(parameter LENGTH = 15, parameter DRIVE = 1) (
    input  wire en,
    output wire ro_out
);
    (* keep *) wire [LENGTH:0] chain;

    `ifdef SIM
    assign chain[0] = ~(chain[LENGTH-1] & en);
    `else
    /* verilator lint_off PINMISSING */
    sky130_fd_sc_hd__nand2_1 nand_inst (.A(chain[LENGTH-1]), .B(en), .Y(chain[0]));
    /* verilator lint_on PINMISSING */
    `endif
    
    genvar i;
    generate
        for (i = 1; i < LENGTH; i = i + 1) begin : ro_inverters
            `ifdef SIM
            assign chain[i] = ~chain[i-1];
            `else
            /* verilator lint_off PINMISSING */
            if (DRIVE == 4)
                sky130_fd_sc_hd__inv_4 inv_inst (.A(chain[i-1]), .Y(chain[i]));
            else if (DRIVE == 2)
                sky130_fd_sc_hd__inv_2 inv_inst (.A(chain[i-1]), .Y(chain[i]));
            else
                sky130_fd_sc_hd__inv_1 inv_inst (.A(chain[i-1]), .Y(chain[i]));
            /* verilator lint_on PINMISSING */
            `endif
        end
    endgenerate

    assign ro_out = chain[0];
endmodule
