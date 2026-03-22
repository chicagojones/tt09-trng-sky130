# Silicon Test & Characterization Plan

Comprehensive test plan for the Sky26a Advanced Tunable TRNG on silicon, covering link verification, entropy path validation, RO characterization, conditioner verification, and NIST health monitor validation.

## Prerequisites

- Tiny Tapeout demo board with SPI access to `uio[3:6]` (CS_N, SCLK, MOSI, MISO)
- USB-serial adapter for UART access: TX→`uio[2]` (RXD), RX←`uio[1]` (TXD), 115200 baud 8N1
- Logic analyzer or oscilloscope (optional, for timing verification)
- 10 MHz system clock (default `BAUD_DIV=87` for 115200 baud UART)
- SPI configuration: CPOL=0, CPHA=0, MSB-first, 7-bit address + R/W bit

## Phase 1: SPI Link Verification

**Goal:** Confirm basic SPI communication before any entropy testing.

1. Write `0xA5` to scratchpad register `0x20`.
2. Read back `0x20` and verify the returned byte is `0xA5`.
3. Write `0x5A`, read back, verify.
4. If readback fails, check SPI wiring and clock polarity.

## Phase 1b: UART Link Verification

**Goal:** Confirm UART command interface works (backup to SPI).

The UART command protocol uses 2-byte commands at 115200 baud, 8N1:
- **Write:** Send `{0x80 | addr, data}` (2 bytes). Bit 7 of byte 1 = 1 for write.
- **Read:** Send `{addr, 0x00}` (2 bytes). Device responds with 1 byte on TX.

1. Send write command: `0xA0, 0xA5` (write `0xA5` to scratchpad at `0x20`).
2. Send read command: `0x20, 0x00` (read scratchpad). Verify response = `0xA5`.
3. Write `0x5A`, read back, verify.
4. **Cross-interface test:** Write via UART, read via SPI (and vice versa) to confirm both interfaces share the same register file.
5. If UART works but SPI doesn't, all subsequent phases can be run via UART instead.

## Phase 2: Default Entropy Path Validation

**Goal:** Verify the default XOR-then-sync entropy pipeline produces random output.

1. Reset the device. Leave `ctrl_reg` (0x13) and `entropy_ctrl_reg` (0x21) at defaults (all zeros).
2. Read random byte from `0x11` repeatedly (100+ reads).
3. Verify output is not stuck (all-zeros or all-ones).
4. Check `uo_out[7:0]` directly for the parallel random byte output.
5. Monitor UART on `uio_out[1]` at 115200 baud; verify streaming random bytes.
6. Read status register `0x10` — confirm `alarm` bit (bit 4) is low.

## Phase 3: RO Characterization (Single-RO Bypass Mode)

**Goal:** Measure each ring oscillator individually using the bypass path.

### 3.1 Enable Bypass Mode

1. Write `ctrl_reg` (0x13) = `0x01` (set `ro_bypass = 1`).
2. This routes a single RO (selected by `freq_mux_sel`) through a 4-stage synchronizer, bypassing the XOR combiner.

### 3.2 Measure Each RO

For each RO index `i` (0–7):

1. Write `0x10` = `i` (set `freq_mux_sel[2:0]`).
2. Wait for frequency counter to complete (~2^17 cycles at 10 MHz = ~13 ms).
3. Read frequency count: `0x00` (LSB), `0x01` (mid), `0x02` (MSB).
4. Record the 24-bit frequency count.
5. Read the random byte `0x11` — in bypass mode this reflects the single RO's output through the conditioner.

### 3.3 Tunable RO Sweep (RO0)

1. Keep bypass mode on (`ctrl_reg[0] = 1`), select RO0 (`0x10` = 0).
2. Sweep `ui_in[7:5]` through values 0–7 (3, 5, 7, ..., 31 inverter stages).
3. At each setting, read the 24-bit frequency count.
4. Verify frequency decreases as chain length increases.

### 3.4 Expected Frequencies

| RO | Stages | Expected Relative Freq |
|----|--------|----------------------|
| RO0 | 3–31 (tunable) | Highest at 3, lowest at 31 |
| RO1 | 13 | High |
| RO2 | 17 | Medium-high |
| RO3 | 19 | Medium |
| RO4 | 23 | Medium-low |
| RO5 | 29 | Low |
| RO6 | 31 | Low |
| RO7 | 37 | Lowest |

## Phase 4: Sync-Before-XOR Mode

**Goal:** Validate the independent-sync entropy path and compare randomness quality.

1. Disable bypass: write `ctrl_reg` (0x13) = `0x00`.
2. Enable sync-before-XOR: write `entropy_ctrl_reg` (0x21) = `0x01`.
3. Read back `0x21` to confirm the bit is set.
4. Collect 1000+ random bytes from `0x11`.
5. Run basic statistical tests (frequency, runs, serial) and compare against Phase 2 (default path) data.
6. Disable sync-before-XOR: write `0x21` = `0x00`.

## Phase 5: NIST Health Monitor Validation

**Goal:** Verify the RCT and APT alarms trigger correctly using test injection, and confirm debug register readback.

### 5.1 Debug Register Overview

| Address | Description |
|---------|-------------|
| 0x1B | `{rct_fail, apt_fail, rct_count[5:0]}` |
| 0x1C | `apt_match_count[7:0]` |
| 0x1E | `{6'b0, apt_match_count[9:8]}` |

### 5.2 Read Debug Registers (Baseline)

1. With default configuration (no injection), read `0x1B`, `0x1C`, `0x1E`.
2. Verify `rct_fail` (bit 7 of `0x1B`) = 0 and `apt_fail` (bit 6 of `0x1B`) = 0.
3. Verify `rct_count` (bits [5:0] of `0x1B`) is small and varying (normal operation resets count frequently).

### 5.3 Test Injection — Repetition Count Test (RCT)

The NIST monitor can be fed deterministic bits via `entropy_ctrl_reg`:
- Bit 1 (`nist_inject_en`): Enable test injection (overrides real entropy source for the monitor input).
- Bit 2 (`nist_inject_bit`): The bit value to inject (0 or 1).

**Procedure to trigger RCT alarm:**

1. Write `entropy_ctrl_reg` (0x21) = `0x06` (inject_en=1, inject_bit=1, sync_before_xor=0).
2. Wait ~50 clock cycles (RCT cutoff = 32 consecutive identical bits).
3. Read `0x1B`: verify `rct_count` is ≥ 31 and `rct_fail` (bit 7) = 1.
4. Read status `0x10`: verify `alarm` (bit 4) = 1.
5. Disable injection: write `0x21` = `0x00`.

**Verify RCT resets on transitions:**

1. Write `0x21` = `0x06` (inject constant 1s).
2. Read `0x1B` and note `rct_count` growing.
3. Write `0x21` = `0x02` (inject constant 0s — flip the bit).
4. Read `0x1B` and verify `rct_count` has reset to a small value (transition detected).

### 5.4 Test Injection — Adaptive Proportion Test (APT)

**Procedure to trigger APT alarm:**

1. Write `0x21` = `0x06` (inject constant 1s).
2. Wait for 1024+ clock cycles (APT window size).
3. Read `0x1C` and `0x1E` to get `apt_match_count`.
4. Verify `apt_match_count` ≥ 600 and `apt_fail` (bit 6 of `0x1B`) = 1.

**Note:** The APT requires many more injected bits than the RCT, so the alarm will take longer to appear.

### 5.5 Alarm Clear and Recovery

1. After triggering alarms via injection, disable injection: write `0x21` = `0x00`.
2. Write `ctrl_reg[2]` = 1 to mask alarm temporarily, then clear it.
3. Verify the alarm clears and normal operation resumes.
4. Collect random bytes and confirm they look healthy.

## Phase 6: Conditioner Verification

**Goal:** Verify each conditioning mode produces output and characterize its quality.

### 6.1 Conditioner Selection

The conditioner is selected via `ctrl_reg[7:5]` (`cond_sel`):

| `cond_sel` | Mode |
|------------|------|
| 0 | von Neumann (default) |
| 1 | Bypass (raw bits, no conditioning) |
| 2 | Tent map |
| 3 | Coupled Tent map |
| 4 | Logistic map |
| 5 | Bernoulli map |
| 6 | Lorenz map |
| 7 | LFSR |

### 6.2 Test Each Conditioner

For each `cond_sel` value (0–7):

1. Write `ctrl_reg` (0x13) with `cond_sel` in bits [7:5], other bits as desired.
2. Collect 1000+ random bytes from `0x11`.
3. Check for stuck output (all-zeros, all-ones, or repeating pattern).
4. Read conditioner state registers `0x14`–`0x1A` to verify internal state is evolving.
5. Read `0x1D` (capability bitmask) to confirm which conditioners are present in the build.

### 6.3 Conditioner + Entropy Path Combinations

Test each conditioner with:
- Default entropy path (XOR→sync)
- Sync-before-XOR (`entropy_ctrl_reg[0] = 1`)
- Single-RO bypass (`ctrl_reg[0] = 1`)

Record randomness quality metrics for each combination.

## Phase 7: Output Interface Verification

### 7.1 Parallel Output (`uo_out`)

1. Set `uo_mux_sel` = 0 (`ctrl_reg[4:3] = 00`): read random bytes.
2. Set `uo_mux_sel` = 1: read frequency count LSB, compare with SPI `0x00`.
3. Set `uo_mux_sel` = 2: read status byte, compare with SPI `0x10`.
4. Set `uo_mux_sel` = 3: observe raw `sampled_bit` toggling.

### 7.2 UART Output

1. Connect to `uio_out[1]` at 115200 baud, 8N1.
2. Verify continuous random byte stream.
3. Collect 10,000+ bytes for offline statistical analysis.

### 7.3 SPI Full Register Sweep

Read all defined register addresses and verify no bus conflicts or unexpected values:
- `0x00`–`0x02`: frequency count
- `0x10`–`0x13`: status, random byte, RO selection, control
- `0x14`–`0x1A`: conditioner state
- `0x1B`, `0x1C`, `0x1E`: NIST debug
- `0x1D`: conditioner capability
- `0x20`: scratchpad
- `0x21`: entropy control

## Phase 8: Auto-Tuner Verification

**Goal:** Verify the auto-tuner responds to NIST alarms.

1. Set `ctrl_reg[1]` = 0 (auto mode, `force_manual` off).
2. Use test injection to trigger an alarm (Phase 5.3).
3. Read RO selection register `0x12` — verify the auto-tuner has cycled to a different RO configuration.
4. Disable injection and verify the alarm clears.

## Phase 9: Statistical Analysis (Offline)

Collect large datasets (100,000+ bytes) under various configurations and run:

1. **NIST SP 800-22** test suite (frequency, block frequency, runs, longest run, FFT, etc.)
2. **Dieharder** test battery
3. **ent** entropy estimation
4. Compare results across:
   - Default vs. sync-before-XOR entropy paths
   - Each conditioner mode
   - Different tunable RO settings

## Appendix: Quick Reference

### SPI Write Sequence
1. Pull CS_N low
2. Send: `{1'b1, 7-bit address}` (write bit + address)
3. Send: `{8-bit data}`
4. Pull CS_N high

### SPI Read Sequence
1. Pull CS_N low
2. Send: `{1'b0, 7-bit address}` (read bit + address)
3. Send: `{8'h00}` (dummy byte, read MISO during this phase)
4. Pull CS_N high

### UART Write Command
1. Send byte: `{1, addr[6:0]}` (bit 7 = 1 for write)
2. Send byte: `{data[7:0]}`

### UART Read Command
1. Send byte: `{0, addr[6:0]}` (bit 7 = 0 for read)
2. Send byte: `{0x00}` (dummy)
3. Receive 1 byte response on TX

### Key Register Quick-Set Examples
```
Default mode:           ctrl_reg=0x00, entropy_ctrl=0x00
Bypass RO3:             ctrl_reg=0x01, freq_mux_sel=0x03
Sync-before-XOR:        ctrl_reg=0x00, entropy_ctrl=0x01
Lorenz conditioner:     ctrl_reg=0xC0 (cond_sel=6)
Inject constant 1s:     entropy_ctrl=0x06
Inject constant 0s:     entropy_ctrl=0x02
Disable injection:      entropy_ctrl=0x00

# UART examples (hex bytes to send on RX pin):
Write 0xA5 to scratch:  A0 A5
Read scratch:           20 00  → receive 1 byte
Write ctrl_reg=0x01:    93 01
Read status:            10 00  → receive 1 byte
```
