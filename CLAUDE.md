# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Tiny Tapeout Sky26a True Random Number Generator (TRNG) based on tunable ring oscillators, targeting the Sky130 PDK. The design fits in 1x2 TT tiles (160um x 450um). Top module: `tt_um_chicagojones_sky26a_trng`.

## Build and Test Commands

```bash
# Run RTL simulation (cocotb + Icarus Verilog)
cd test && make clean && make

# Gate-level simulation (requires PDK_ROOT set to sky130A location)
cd test && make clean && GATES=yes make
```

Tests use cocotb 2.0.1 with pytest. The test module is `test/test_trng.py`.

## Architecture

**Entropy pipeline (3 selectable modes via SPI):**
- **Default:** 8 ROs → XOR combiner → 4-stage synchronizer → conditioner → shift register → output byte
- **Sync-before-XOR** (`entropy_ctrl[0]=1`): 8 ROs → 8× 2-stage sync → XOR → conditioner → shift register → output byte
- **Single-RO bypass** (`ctrl_reg[0]=1`): 1 RO (selected by `freq_mux_sel`) → 4-stage sync → conditioner → shift register → output byte

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
- `uio_in[2]`: UART RX at 115200 baud — register read/write command interface (2-byte protocol: `{W/R|addr, data}`)
- SPI follower on `uio[3:6]` (CS_N, SCLK, MOSI, MISO) with 7-bit register address space

**SPI register map:**
| Address | Description |
|---------|-------------|
| 0x00–0x02 | Frequency count (24-bit, read-only) |
| 0x10 | Status / Frequency mux select (`{3'b0, alarm, 1'b0, freq_mux_sel[2:0]}`) |
| 0x11 | Random byte output |
| 0x12 | RO selection readback |
| 0x13 | Control register |
| 0x14–0x1A | Conditioner state readback (read-only) |
| 0x1D | Conditioner capability bitmask (read-only) |
| 0x20 | Scratchpad (read/write, for SPI link verification) |
| 0x21 | Entropy control register |

**Control register (0x13) bit fields:**
| Bit(s) | Name | Description |
|--------|------|-------------|
| 0 | `ro_bypass` | 1 = single-RO mode (bypass XOR, RO selected by `freq_mux_sel`) |
| 1 | `force_manual` | 1 = ignore `auto_en` pin for RO tuning |
| 2 | `mask_alarm` | 1 = suppress NIST alarm for auto-tuning |
| 4:3 | `uo_mux_sel` | Output mux: 0=random byte, 1=freq count, 2=status, 3=raw sampled_bit |
| 7:5 | `cond_sel` | Conditioner: 0=VN, 1=Bypass, 2=Tent, 3=CoupledTent, 4=Logistic, 5=Bernoulli, 6=Lorenz, 7=LFSR |

**Entropy control register (0x21) bit fields:**
| Bit(s) | Name | Description |
|--------|------|-------------|
| 0 | `sync_before_xor` | 1 = sync each RO independently (2-stage) before XOR combination |
| 7:1 | reserved | |

## Critical Design Constraints

- **RO protection:** All `chain` wires use `(* keep *)` to prevent synthesis optimization. Do not remove.
- **Synchronizer:** The 4-stage metastability synchronizers in `trng_core` (post-XOR and bypass paths) must not be reduced. The per-RO 2-stage synchronizers (sync-before-XOR path) must also be preserved.
- **OpenLane:** `SYNTH_BUFFERING` and `SYNTH_SIZING` must be disabled for RO modules to preserve oscillator structure.
- **Simulation flag:** Always compile with `-DCOCOTB_SIM=1 -DSIM=1` for simulation (already in Makefile).

## Source Files

All Verilog sources are in `src/`. The key files: `tt_um_trng_ro.v` (top-level with trng_core, RO instantiation, register file, UART command parser, output mux), `nist_health_monitor.v`, `auto_tuner.v`, `von_neumann.v`, `uart_tx.v`, `uart_rx.v`, `spi_follower.v`, `ro_freq_counter.v`.

## Test Structure

Tests in `test/test_trng.py` use SPI read/write helpers to exercise the register interface. Asynchronous RO tests are skipped during gate-level simulation (`GATES=yes`). The testbench wrapper is `test/tb.v`.
