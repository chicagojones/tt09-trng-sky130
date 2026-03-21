`default_nettype none

/*
 * RO Delay Buffer
 *
 * This module is used to break the zero-delay combinational loops during 
 * Gate-Level Simulation (GLS). 
 *
 * It is ALWAYS behavioral with a #1 delay to ensure that even the 
 * synthesized netlist (which keeps this as a module) has a non-zero delay.
 */
module ro_delay_buf (
    input  wire in,
    output wire out
);

    assign #1 out = in;

endmodule
