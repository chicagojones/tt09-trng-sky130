`default_nettype none

/* 
 * von Neumann Whitener
 * 
 * Takes raw biased bits and outputs an unbiased stream at a variable rate.
 * Rule: Looks at pairs of non-overlapping bits.
 * '01' -> Output '0' (Valid)
 * '10' -> Output '1' (Valid)
 * '00' or '11' -> Discarded (Invalid)
 */
module von_neumann (
    input  wire clk,
    input  wire rst_n,
    input  wire en,         // Enable processing
    input  wire raw_bit,
    output reg  valid,      // High for 1 clock cycle when out_bit is valid
    output reg  out_bit     // The whitened bit
);

    // FSM to group bits into pairs
    reg state; // 0: waiting for first bit, 1: waiting for second bit
    reg first_bit;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= 1'b0;
            first_bit <= 1'b0;
            valid     <= 1'b0;
            out_bit   <= 1'b0;
        end else begin
            valid <= 1'b0; // Default to not valid
            
            if (en) begin
                if (state == 1'b0) begin
                    // Store first bit of the pair
                    first_bit <= raw_bit;
                    state     <= 1'b1;
                end else begin
                    // Evaluate the pair (first_bit, raw_bit)
                    if (first_bit == 1'b1 && raw_bit == 1'b0) begin
                        out_bit <= 1'b1;
                        valid   <= 1'b1;
                    end else if (first_bit == 1'b0 && raw_bit == 1'b1) begin
                        out_bit <= 1'b0;
                        valid   <= 1'b1;
                    end
                    // '00' and '11' are discarded (valid remains 0)
                    
                    // Reset to look for the next pair
                    state <= 1'b0;
                end
            end
        end
    end

endmodule
