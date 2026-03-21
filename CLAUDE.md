# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Tiny Tapeout 09 True Random Number Generator (TRNG) based on tunable ring oscillators, targeting the Sky130 PDK. The design fits in 1x2 TT tiles (160um x 450um). Top module: `tt_um_chicagojones_tt09_trng_sky130`.

## Build and Test Commands

```bash
# Run RTL simulation (cocotb + Icarus Verilog)
cd test && make clean && make

# Gate-level simulation (requires PDK_ROOT set to sky130A location)
cd test && make clean && GATES=yes make
```

Tests use cocotb 2.0.1 with pytest. The test module is `test/test_trng.py`.

## Architecture

**Entropy pipeline:** 8 Ring Oscillators → XOR combiner → 4-stage synchronizer → von Neumann whitener → 8-bit shift register → output byte

**Ring Oscillators (in `tt_um_trng_ro.v`):**
- RO0: tunable (3–31 stages via `ui_in[7:5]` select bits)
- RO1–RO7: fixed lengths (13, 17, 19, 23, 29, 31, 37 stages) with varying drive strengths
- In simulation (`SIM` defined): ROs toggle synchronously on system clock instead of oscillating asynchronously
- On silicon: structural sky130_fd_sc_hd cells (NAND + inverter chains)

**Health monitoring (`nist_health_monitor.v`):**
- NIST SP 800-90B Repetition Count Test (cutoff: 32) and Adaptive Proportion Test (window: 1024, cutoff: 600)
- Alarm triggers auto-tuner to cycle RO selection

**Output interfaces:**
- `uo_out[7:0]`: random byte (directly readable)
- `uio_out[1]`: UART TX at 115200 baud (BAUD_DIV=87 @ 10MHz clock)
- SPI follower on `uio[3:6]` (CS_N, SCLK, MOSI, MISO) with 7-bit register address space

**SPI register map:**
| Address | Description |
|---------|-------------|
| 0x00–0x02 | Frequency count (24-bit, read-only) |
| 0x10 | Status / Frequency mux select |
| 0x11 | Random byte output |
| 0x12 | RO selection readback |
| 0x13 | Control register (bypass whitener, force manual, mask alarm, output select) |
| 0x20 | Scratchpad (read/write, for SPI link verification) |

## Critical Design Constraints

- **RO protection:** All `chain` wires use `(* keep *)` to prevent synthesis optimization. Do not remove.
- **Synchronizer:** The 4-stage metastability synchronizer in `trng_core` must not be reduced.
- **OpenLane:** `SYNTH_BUFFERING` and `SYNTH_SIZING` must be disabled for RO modules to preserve oscillator structure.
- **Simulation flag:** Always compile with `-DCOCOTB_SIM=1 -DSIM=1` for simulation (already in Makefile).

## Source Files

All Verilog sources are in `src/`. The key files: `tt_um_trng_ro.v` (top-level with trng_core, RO instantiation, register file, output mux), `nist_health_monitor.v`, `auto_tuner.v`, `von_neumann.v`, `uart_tx.v`, `spi_follower.v`, `ro_freq_counter.v`.

## Test Structure

Tests in `test/test_trng.py` use SPI read/write helpers to exercise the register interface. Asynchronous RO tests are skipped during gate-level simulation (`GATES=yes`). The testbench wrapper is `test/tb.v`.
