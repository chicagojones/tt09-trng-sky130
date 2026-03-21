`default_nettype none

/**
 * Enhanced SPI Follower (Register Based)
 * 
 * Supports reading internal status and characterization registers.
 * Transaction:
 *   1. Master sends Command Byte (Address[6:0], 1=Read/0=Write)
 *   2. Master sends Dummy/Data Byte, Slave returns Register Value
 * 
 * Mode 0 (CPOL=0, CPHA=0).
 */
module spi_follower (
    input  wire        clk,      // System clock
    input  wire        rst_n,    // System reset
    
    // External SPI pins
    input  wire        sclk,     
    input  wire        cs_n,     
    input  wire        mosi,     
    output wire        miso,     

    // Internal Register Interface
    output reg  [6:0]  reg_addr,
    input  wire [7:0]  reg_data_in,
    output wire [7:0]  reg_data_out,
    output reg         reg_write_en
);

    // --- Signal Synchronization ---
    reg [2:0] sclk_sync, cs_sync, mosi_sync;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sclk_sync <= 3'b0;
            cs_sync   <= 3'b111;
            mosi_sync <= 3'b0;
        end else begin
            sclk_sync <= {sclk_sync[1:0], sclk};
            cs_sync   <= {cs_sync[1:0], cs_n};
            mosi_sync <= {mosi_sync[1:0], mosi};
        end
    end

    wire cs_active   = ~cs_sync[1];
    wire cs_falling  =  cs_sync[2] & ~cs_sync[1];
    wire sclk_rising = ~sclk_sync[2] &  sclk_sync[1];
    wire sclk_falling=  sclk_sync[2] & ~sclk_sync[1];
    wire mosi_data   =  mosi_sync[1];

    // --- State Machine ---
    reg [3:0] bit_count;
    reg [7:0] shift_in;
    reg [7:0] shift_out;
    reg       byte_received;
    reg       is_second_byte;

    assign reg_data_out = shift_in;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bit_count      <= 4'd0;
            shift_in       <= 8'd0;
            shift_out      <= 8'd0;
            byte_received  <= 1'b0;
            is_second_byte <= 1'b0;
            reg_addr       <= 7'd0;
            reg_write_en   <= 1'b0;
        end else begin
            byte_received <= 1'b0;
            reg_write_en  <= 1'b0;

            if (cs_falling) begin
                bit_count      <= 4'd0;
                is_second_byte <= 1'b0;
            end else if (cs_active) begin
                // Shift in on rising edge (Mode 0)
                if (sclk_rising) begin
                    shift_in <= {shift_in[6:0], mosi_data};
                    if (bit_count == 4'd7) begin
                        byte_received <= 1'b1;
                        bit_count     <= 4'd0;
                    end else begin
                        bit_count <= bit_count + 1'b1;
                    end
                end

                // Handle Received Byte
                if (byte_received) begin
                    if (!is_second_byte) begin
                        // This was the Command Byte
                        reg_addr       <= shift_in[7:1];
                        // Prepare data for next byte shift-out
                        // We use reg_data_in which is already indexed by reg_addr
                        shift_out      <= reg_data_in; 
                        is_second_byte <= 1'b1;
                    end else begin
                        // This was the Data Byte
                        reg_write_en   <= ~reg_addr[0]; // Example write logic if needed
                        is_second_byte <= 1'b0; // Reset for multi-byte or wait for CS
                    end
                end

                // Shift out on falling edge
                if (sclk_falling) begin
                    shift_out <= {shift_out[6:0], 1'b0};
                end
            end
        end
    end

    // Drive MISO
    assign miso = cs_active ? shift_out[7] : 1'bz;

endmodule
