`default_nettype none

/*
 * RO Delay Buffer
 *
 * This module is used to break the zero-delay combinational loops during 
 * Gate-Level Simulation (GLS). 
 *
 * In simulation, it adds a #1 unit delay.
 * In silicon synthesis, it is typically mapped to a simple buffer or wire.
 */
module ro_delay_buf (
    input  wire in,
    output wire out
);

    `ifdef SIM
    assign #1 out = in;
    `else
    assign out = in;
    `endif

endmodule
