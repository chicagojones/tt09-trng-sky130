# GEMINI.md - Tunable TRNG Project Instructions

## Design Directives
- **Oscillator Protection:** All Ring Oscillator (RO) logic must be protected from synthesis and placement optimization. Use `(* keep *)` on the `chain` wires in `src/tt_um_trng_ro.v`.
- **Metastability:** The asynchronous XOR output from the ROs must be sampled by the 4-stage synchronizer in `trng_core`. Do not reduce the stage count.
- **Auto-Tuning:** The `health_monitor` window is set to 1024 cycles. This is the baseline for "valid entropy" detection.
- **Physical Isolation:** When generating GDS, ROs should be placed to minimize injection locking.

## Build Guidelines
- **Simulation:** Always use `-DCOCOTB_SIM=1` in the `Makefile` or simulation command to include the unit delays required for oscillators.
- **OpenLane:** Do not enable `SYNTH_BUFFERING` or `SYNTH_SIZING` for the RO modules as it will destroy the oscillator structure.
