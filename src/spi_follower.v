`default_nettype none

/* 
 * SPI Follower (Mode 0)
 * 
 * Shifts out an 8-bit byte when CS is low.
 * CPOL=0, CPHA=0.
 */
module spi_follower (
    input  wire       clk,      // System clock
    input  wire       rst_n,    // System reset
    input  wire [7:0] data_in,  // Byte to transmit
    input  wire       sclk,     // SPI Clock
    input  wire       cs_n,     // SPI Chip Select (Active Low)
    input  wire       mosi,     // SPI MOSI (Unused)
    output wire       miso      // SPI MISO
);

    reg [7:0] shift_reg;
    reg [2:0] bit_count;

    // Synchronize SPI signals to system clock
    reg [2:0] sclk_sync;
    reg [2:0] cs_sync;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sclk_sync <= 3'b0;
            cs_sync   <= 3'b111;
        end else begin
            sclk_sync <= {sclk_sync[1:0], sclk};
            cs_sync   <= {cs_sync[1:0], cs_n};
        end
    end

    wire cs_active   = ~cs_sync[1];
    wire cs_falling  =  cs_sync[2] & ~cs_sync[1];
    wire sclk_rising = ~sclk_sync[2] &  sclk_sync[1];
    wire sclk_falling=  sclk_sync[2] & ~sclk_sync[1];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            shift_reg <= 8'd0;
            bit_count <= 3'd0;
        end else begin
            if (cs_falling) begin
                // Load data on start of transaction
                shift_reg <= data_in;
                bit_count <= 3'd0;
            end else if (cs_active) begin
                if (sclk_falling) begin
                    // Shift out on falling edge (Mode 0)
                    shift_reg <= {shift_reg[6:0], 1'b0};
                    bit_count <= bit_count + 1'b1;
                end
            end
        end
    end

    // Drive MISO only when CS is active
    assign miso = cs_active ? shift_reg[7] : 1'bz;

endmodule
