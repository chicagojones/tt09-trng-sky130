# Sky26a Advanced Tunable TRNG

A high-reliability True Random Number Generator (TRNG) based on an 8-oscillator bank, featuring NIST-compliant health monitors and dual-interface data retrieval (SPI/UART). Designed for the Tiny Tapeout Sky26a shuttle (Sky130 process).

## Design Goals
- **High Entropy:** 8 independent Ring Oscillators with prime-number depths to minimize phase-locking.
- **Robustness:** Built-in NIST SP 800-90B health monitors (RCT and APT) with auto-tuning feedback.
- **Characterization:** On-chip 24-bit frequency counters for RO profiling via SPI.
- **Fail-Safe:** Comprehensive control register to bypass whitening or manual override tuning.
- **Compactness:** Fits within 2x2 Tiny Tapeout tiles (approx. 334um x 216um).

## Architecture
1. **Entropy Bank:** 8 Ring Oscillators (1 tunable, 7 fixed prime lengths).
2. **Entropy Path (3 selectable modes):**
   - **Default:** All ROs → XOR → 4-stage synchronizer (classic post-XOR sync).
   - **Sync-before-XOR** (`entropy_ctrl[0]=1`): Each RO → 2-stage sync → XOR (independent sampling, better theoretical randomness).
   - **Single-RO bypass** (`ctrl_reg[0]=1`): One RO (selected by `freq_mux_sel`) → 4-stage sync (for individual RO characterization).
3. **NIST Monitor:** Real-time Repetition Count Test (RCT) and Adaptive Proportion Test (APT).
4. **Conditioning:** von Neumann corrector (default) + 6 selectable chaotic map conditioners.
5. **Output Interface:**
   - **Parallel:** 8-bit random byte on `uo_out`.
   - **UART TX:** 115200 baud serial stream on `uio_out[1]`.
   - **UART RX:** 115200 baud command interface on `uio_in[2]` for register read/write (SPI fallback).
   - **SPI:** Register-based follower on `uio[6:3]` for status and frequency readback.

## Top Module
The top module is `tt_um_chicagojones_sky26a_trng`.

## SPI Register Map
| Address | Description |
|---------|-------------|
| 0x00–0x02 | Frequency count (24-bit, read-only) |
| 0x10 | Status / Frequency mux select (`{3'b0, alarm, 1'b0, freq_mux_sel[2:0]}`) |
| 0x11 | Random byte output |
| 0x12 | RO selection readback |
| 0x13 | Control register (see below) |
| 0x14–0x1A | Conditioner state readback (read-only) |
| 0x1D | Conditioner capability bitmask (read-only) |
| 0x20 | Scratchpad (read/write, for SPI link verification) |
| 0x21 | Entropy control register (see below) |

### Control Register (0x13)
| Bit(s) | Name | Description |
|--------|------|-------------|
| 0 | `ro_bypass` | 1 = single-RO mode (bypass XOR, RO selected by `freq_mux_sel`) |
| 1 | `force_manual` | 1 = ignore `auto_en` pin for RO tuning |
| 2 | `mask_alarm` | 1 = suppress NIST alarm for auto-tuning |
| 4:3 | `uo_mux_sel` | 0=random byte, 1=freq count LSB, 2=status, 3=raw sampled_bit |
| 7:5 | `cond_sel` | 0=VN, 1=Bypass, 2=Tent, 3=CoupledTent, 4=Logistic, 5=Bernoulli, 6=Lorenz, 7=LFSR |

### Entropy Control Register (0x21)
| Bit(s) | Name | Description |
|--------|------|-------------|
| 0 | `sync_before_xor` | 1 = sync each RO independently (2-stage) before XOR combination |
| 1 | `nist_inject_en` | 1 = override entropy source for NIST monitor with inject_bit |
| 2 | `nist_inject_bit` | Bit value to inject when injection enabled |
| 3 | `uart_stream_en` | 1 = stream random bytes on UART TX (default off) |
| 7:4 | reserved | |

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

See [docs/test_plan.md](docs/test_plan.md) for the comprehensive silicon test and characterization plan.
