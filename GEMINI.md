# GEMINI.md - Advanced TRNG Project Instructions

## Design Directives
- **Oscillator Protection:** All Ring Oscillator (RO) logic must be protected from synthesis and placement optimization. Use `(* keep *)` on the `chain` wires in `src/tt_um_trng_ro.v`. We are using structural `sky130_fd_sc_hd__inv_1`, `inv_2`, `inv_4` and `sky130_fd_sc_hd__nand2_1` cells.
- **Metastability:** The asynchronous XOR output from the 8-RO bank must be sampled by the 4-stage synchronizer in `trng_core`. Do not reduce the stage count.
- **NIST Health Monitoring:** Continuous health tests (RCT and APT) are mandatory. Thresholds: RCT=32 bits, APT=600/1024.
- **Frequency Characterization:** RO frequencies are measured using a multiplexed 24-bit ripple counter accessible via SPI. 
- **Fail-Safe Control:** SPI register 0x13 allows bypassing the whitener or NIST alarms. Essential for post-silicon debugging.

## Build Guidelines
- **Simulation:** Always use `-DSIM=1` in the `Makefile` or simulation command. This enables synchronous RO toggle models to prevent multi-GHz event stalls in Icarus Verilog.
- **OpenLane:** Do not enable `SYNTH_BUFFERING` or `SYNTH_SIZING` for the RO modules as it will destroy the oscillator structure.
- **UART:** Default baud rate is 115200 (BAUD_DIV=87 at 10MHz).
