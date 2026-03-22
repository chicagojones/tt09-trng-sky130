# TT09 Advanced Tunable TRNG (Sky130)

A high-reliability True Random Number Generator (TRNG) based on an 8-oscillator bank, featuring NIST-compliant health monitors and dual-interface data retrieval (SPI/UART). Designed for Tiny Tapeout 09 (Sky130 sky26a process).

## Design Goals
- **High Entropy:** 8 independent Ring Oscillators with prime-number depths to minimize phase-locking.
- **Robustness:** Built-in NIST SP 800-90B health monitors (RCT and APT) with auto-tuning feedback.
- **Characterization:** On-chip 24-bit frequency counters for RO profiling via SPI.
- **Fail-Safe:** Comprehensive control register to bypass whitening or manual override tuning.
- **Compactness:** Fits within 2x2 Tiny Tapeout tiles (approx. 334um x 216um).

## Architecture
1. **Entropy Bank:** 8 Ring Oscillators (1 tunable, 7 fixed prime lengths) XORed together.
2. **Synchronizer:** 4-stage metastability mitigation for high-speed asynchronous sampling.
3. **NIST Monitor:** Real-time Repetition Count Test (RCT) and Adaptive Proportion Test (APT).
4. **Whitening:** von Neumann corrector for bias removal.
5. **Output Interface:** 
   - **Parallel:** 8-bit random byte on `uo_out`.
   - **UART:** 115200 baud serial stream on `uio_out[1]`.
   - **SPI:** Register-based follower on `uio[6:3]` for status and frequency readback.

## Top Module
The top module is `tt_um_chicagojones_tt09_trng_sky130`.

## SPI Register Map
| Address | Description |
|---------|-------------|
| 0x00–0x02 | Frequency count (24-bit, read-only) |
| 0x10 | Status / Frequency mux select |
| 0x11 | Random byte output |
| 0x12 | RO selection readback |
| 0x13 | Control register (bypass whitener, force manual, mask alarm, output select) |
| 0x20 | Scratchpad (read/write, for SPI link verification) |

## Project Structure
- `src/`: Verilog source files.
- `test/`: Cocotb testbenches and simulations.
- `docs/`: Documentation and datasheet materials.
- `info.yaml`: Tiny Tapeout configuration.

## How to Test
1. **Verification:** Run the Cocotb testbench.
   ```bash
   cd test
   make clean && make
   ```
2. **Gate-Level Sim:**
   ```bash
   cd test
   make clean && GATES=yes make
   ```
3. **SPI Access:** Use the SPI interface to read the scratchpad at `0x20` to verify the link, then read frequency data from `0x00-0x02`.
