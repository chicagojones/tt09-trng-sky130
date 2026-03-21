`default_nettype none

module tt_um_chicagojones_trng_ro (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can use it to enable the design
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

    wire en         = ui_in[3];
    wire auto_en    = ui_in[4];
    wire [2:0] man_sel = ui_in[7:5];

    // Sub-module connections
    wire [2:0] ro_sel;
    wire       ro_raw;
    wire       sampled_bit;
    
    wire       alarm;
    wire       reset_monitor;

    wire       vn_valid;
    wire       vn_bit;

    wire       uart_tx_out;

    // -- UART Transmitter --
    uart_tx #(
        .BAUD_DIV(87) // 10MHz / 115200
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

    // -- Multi-RO Core --
    trng_core ro_inst (
        .clk(clk),
        .rst_n(rst_n),
        .en(en),
        .sel(ro_sel),
        .sampled_bit(sampled_bit),
        .ro_raw(ro_raw)
    );

    // -- Health Monitor --
    health_monitor monitor_inst (
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
            byte_valid <= 1'b0; // Pulse for 1 cycle
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
    assign uio_out[7:2] = 6'b0;
    assign uio_oe       = 8'b00000011; // uio[0,1] are outputs, rest are inputs

    // Use a dummy wire to "use" otherwise unused inputs to satisfy the linter
    wire _unused = &{ui_in[2:0], uio_in, ena, ro_raw};

endmodule

/* 
 * Multi-RO Core 
 * Instantiates 3 ROs and XORs them. 
 * RO0 is tunable. RO1 and RO2 have fixed lengths to ensure varied frequencies.
 */
module trng_core (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       en,
    input  wire [2:0] sel,
    output wire       sampled_bit,
    output wire       ro_raw
);

    wire out_ro0, out_ro1, out_ro2;

    // RO 0: Tunable (3 to 31 stages)
    ro_tunable ro0 (
        .en(en),
        .sel(sel),
        .ro_out(out_ro0)
    );

    // RO 1: Fixed 15 stages
    ro_fixed #(.LENGTH(15)) ro1 (
        .en(en),
        .ro_out(out_ro1)
    );

    // RO 2: Fixed 23 stages
    ro_fixed #(.LENGTH(23)) ro2 (
        .en(en),
        .ro_out(out_ro2)
    );

    // XOR tree to mix the entropy
    assign ro_raw = out_ro0 ^ out_ro1 ^ out_ro2;

    // 4-stage Synchronizer for metastability mitigation
    // Sampling a high-speed asynchronous XOR tree requires multiple stages
    // to ensure the output resolves to a stable 0 or 1 before the whitener.
    reg [3:0] sync_regs;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            sync_regs <= 4'b0;
        else
            sync_regs <= {sync_regs[2:0], ro_raw};
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

    `ifdef COCOTB_SIM
    assign #1 chain[0] = ~(feedback & en);
    `else
    /* verilator lint_off PINMISSING */
    sky130_fd_sc_hd__nand2_1 nand_inst (
        .A(feedback),
        .B(en),
        .Y(chain[0])
    );
    /* verilator lint_on PINMISSING */
    `endif
    
    genvar i;
    generate
        for (i = 1; i < 32; i = i + 1) begin : ro_inverters
            `ifdef COCOTB_SIM
            assign #1 chain[i] = ~chain[i-1];
            `else
            /* verilator lint_off PINMISSING */
            sky130_fd_sc_hd__inv_1 inv_inst (
                .A(chain[i-1]),
                .Y(chain[i])
            );
            /* verilator lint_on PINMISSING */
            `endif
        end
    endgenerate

    assign ro_out = chain[0];
endmodule

/* 
 * Fixed Length Ring Oscillator
 */
module ro_fixed #(parameter LENGTH = 15) (
    input  wire en,
    output wire ro_out
);
    (* keep *) wire [LENGTH:0] chain;

    `ifdef COCOTB_SIM
    assign #1 chain[0] = ~(chain[LENGTH-1] & en);
    `else
    /* verilator lint_off PINMISSING */
    sky130_fd_sc_hd__nand2_1 nand_inst (
        .A(chain[LENGTH-1]),
        .B(en),
        .Y(chain[0])
    );
    /* verilator lint_on PINMISSING */
    `endif
    
    genvar i;
    generate
        for (i = 1; i < LENGTH; i = i + 1) begin : ro_inverters
            `ifdef COCOTB_SIM
            assign #1 chain[i] = ~chain[i-1];
            `else
            /* verilator lint_off PINMISSING */
            sky130_fd_sc_hd__inv_1 inv_inst (
                .A(chain[i-1]),
                .Y(chain[i])
            );
            /* verilator lint_on PINMISSING */
            `endif
        end
    endgenerate

    assign ro_out = chain[0];
endmodule
