# Plan: Parameterized Multi-Conditioner Architecture for TRNG

## Context

The current TRNG uses only a von Neumann whitener for entropy conditioning, which discards ~75% of input bits. The goal is to add multiple chaotic map and linear conditioning options as alternatives, selectable at runtime via SPI and includable/excludable at synthesis time via top-level Verilog parameters. This enables on-silicon comparison of different conditioning strategies — a novel research contribution since no prior work has done this on an open-source ASIC with side-by-side characterization.

### Prior Art
- Avaroglu et al. (2015): Logistic map post-processing for RO-TRNG on FPGA
- Garipcan & Erdem (2020): "Chaotic entropy pool" (tent, quadratic, cubic, Bernoulli) on FPGA
- Nouri et al. (2022): PWLCM on TSMC 90nm ASIC (standalone PRNG, not hybrid)
- **Gap:** No open-source ASIC with side-by-side conditioner comparison and SPI characterization

## Architecture

```
                              ┌──────────────┐
                              │ Von Neumann   │──→ vn_bit, vn_valid
                              ├──────────────┤
sampled_bit ──────────┬──────→│ Tent Map      │──→ tent_bit, tent_valid
(from 4-stage sync)   │       ├──────────────┤
                      ├──────→│ Coupled Tent  │──→ coupled_bit, coupled_valid
                      │       ├──────────────┤                            ┌──────────┐
                      ├──────→│ Logistic Map  │──→ logistic_bit, valid ──→│ cond_sel │
                      │       ├──────────────┤                            │   mux    │──→ active_bit/valid
                      ├──────→│ Bernoulli Map │──→ bern_bit, valid       │          │       │
                      │       ├──────────────┤                            └──────────┘       │
                      ├──────→│ Lorenz (Euler)│──→ lorenz_bit, valid          ↑               ▼
                      │       ├──────────────┤                       ctrl_reg[7:5]     8-bit shift reg
                      ├──────→│ LFSR          │──→ lfsr_bit, valid                         │
                      │       └──────────────┘                                             ▼
                      └──────────────────────────→ (bypass = raw sampled_bit)           out_reg
```

Each conditioning module is wrapped in `generate if (INCLUDE_xxx)` so it's completely removed at synthesis when not needed.

## ctrl_reg[7:0] Bit Reassignment (SPI addr 0x13)

| Bit(s) | Name | Description |
|--------|------|-------------|
| 0 | _(reserved)_ | Was bypass_vn — now unused, reads 0 |
| 1 | force_manual | Force manual RO selection |
| 2 | mask_alarm | Ignore NIST health alarm |
| 4:3 | uo_sel[1:0] | Output mux select |
| 7:5 | **cond_sel[2:0]** | **Conditioning select (new)** |

**cond_sel values:**
| Value | Conditioner | Parameter Gate | Notes |
|-------|-------------|---------------|-------|
| 0 | Von Neumann | _(always present)_ | Default after reset |
| 1 | Bypass (raw) | _(always present)_ | Replaces old bypass_vn |
| 2 | Tent map | `INCLUDE_TENT_MAP` | Piecewise linear, Lyapunov = ln(2) |
| 3 | Coupled tent map | `INCLUDE_COUPLED_TENT` | Higher dimensional chaos |
| 4 | Logistic map | `INCLUDE_LOGISTIC` | Nonlinear (quadratic), classic |
| 5 | Bernoulli shift map | `INCLUDE_BERNOULLI` | Simplest chaotic map |
| 6 | Lorenz attractor (Euler) | `INCLUDE_LORENZ` | 3-variable ODE, multi-cycle |
| 7 | Fibonacci LFSR | `INCLUDE_LFSR` | Linear baseline comparison |

> **Note:** With 3 bits we have exactly 8 slots. If all 8 are included, the mux is full. If area is tight, cut the most expensive ones first (Lorenz > Coupled Tent > Logistic > others).

## New Files — Conditioning Modules

All modules share a standard interface:
```verilog
module cond_xxx (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        en,
    input  wire        sampled_bit,   // raw entropy injection
    output wire        out_bit,       // conditioned output
    output wire        out_valid,     // 1 = output valid this cycle
    output wire [N:0]  state_out      // internal state for SPI characterization
);
```

---

### 1. `src/cond_tent_map.v` — Single Tent Map
**Estimated area:** ~90 cells | **Throughput:** 1 bit/clock (100%)

**Algorithm (fixed-point 8-bit):**
```
if x[7] == 0:  x_next = x << 1           // multiply by 2
if x[7] == 1:  x_next = (~x) << 1        // 2*(1-x) via complement + shift
x_next[0] ^= sampled_bit                  // entropy injection into LSB
```
- State: 8-bit register `x`, seed `0xA5`
- Lyapunov exponent: ln(2) ≈ 0.693 (provably chaotic)
- Output: `x[7]` (MSB)
- `state_out[7:0] = x`
- Stuck-state guard: if `x == 0`, reinitialize to seed

---

### 2. `src/cond_coupled_tent.v` — Coupled Tent Map
**Estimated area:** ~200 cells | **Throughput:** 1 bit/clock

**Algorithm:**
```
x_tent = tent(x);  y_tent = tent(y);      // independent tent maps
x_next = x_tent ^ {4'b0, y[7:4]};         // cross-couple: y's high nibble into x
y_next = y_tent ^ {4'b0, x[3:0]};         // cross-couple: x's low nibble into y
x_next[0] ^= sampled_bit;                 // entropy injection
```
- State: two 8-bit registers `x`/`y`, seeds `0xA5`/`0x5A`
- Higher dimensional attractor (harder to predict)
- Output: `x[7] ^ y[7]` (decorrelated XOR of MSBs)
- `state_out[15:0] = {y, x}`

---

### 3. `src/cond_logistic.v` — Logistic Map
**Estimated area:** ~400–600 cells | **Throughput:** 1 bit/clock (pipelined) or 1 bit/N clocks (iterative)

**Algorithm (fixed-point 16-bit):**
```
x_next = r * x * (1 - x)
```
where `r ≈ 3.999` (near-maximum chaos, Lyapunov ≈ ln(2)).

**Implementation options:**
- **Option A — Shift-add multiplier:** Use a sequential multiply unit that computes `x * (1-x)` over multiple clocks, then scales by `r`. ~400 cells, multi-cycle latency per output.
- **Option B — Lookup + interpolation:** Small ROM/LUT for the parabola, interpolated. ~300 cells but less precise.
- **Option C — Approximation:** `x*(1-x)` can be approximated as `x ^ (~x)` followed by bit manipulation. Loses mathematical precision but captures the qualitative nonlinear folding.

**Recommendation:** Option A with a small iterative multiplier. The multiply can be 8-bit × 8-bit → 16-bit in 8 clock cycles using shift-add. This means 1 output bit every ~10 clocks. Still much better than von Neumann's ~25% rate in practice.

- State: 16-bit register `x`, seed `0x6666` (≈ 0.4 in Q0.16)
- Entropy injection: XOR `sampled_bit` into `x[0]` after each iteration
- Output: `x[15]` (MSB)
- `out_valid` pulses once per iteration (every ~10 clocks)
- `state_out[7:0] = x[15:8]`

---

### 4. `src/cond_bernoulli.v` — Bernoulli Shift Map
**Estimated area:** ~40–50 cells | **Throughput:** 1 bit/clock

**Algorithm (fixed-point 8-bit):**
```
x_next = (x << 1) mod 1    // equivalent to: discard MSB, shift left
x_next[0] ^= sampled_bit   // entropy injection
```
This is the simplest possible chaotic map — just a left shift with wrap-around. Lyapunov exponent = ln(2). Without entropy injection it's a trivial shift register; with injection, each bit of physical entropy propagates through the full state via shifts.

- State: 8-bit register `x`, seed `0xA5`
- Output: `x[7]` (the bit being shifted out)
- `state_out[7:0] = x`
- Essentially a "minimal chaos" baseline — any entropy improvement over this is due to the map's nonlinearity

---

### 5. `src/cond_lorenz.v` — Lorenz Attractor (Euler Method)
**Estimated area:** ~800–1200 cells | **Throughput:** 1 bit per ~20 clocks

**Lorenz equations:**
```
dx/dt = σ(y - x)        σ = 10
dy/dt = x(ρ - z) - y    ρ = 28
dz/dt = xy - βz          β = 8/3
```

**Euler discretization (fixed-point 16-bit, Q8.8):**
```
dt = 0.01 (fixed step ≈ 3 in Q8.8 representation)
x_next = x + dt * σ * (y - x)
y_next = y + dt * (x * (ρ - z) - y)
z_next = z + dt * (x * y - β * z)
```

**Implementation:** Sequential — one shared shift-add multiplier processes the three updates over ~20 clock cycles per Euler step. This is the most area-expensive option.

- **Multiplier:** 8×8 → 16-bit shift-add, ~150 cells
- **Three 16-bit state registers (x, y, z):** 48 FFs
- **Control FSM + add/sub/mux:** ~200 cells
- **Constants (σ, ρ, β, dt):** Hardwired shifts/adds (σ=10 ≈ 8+2, ρ=28 ≈ 32-4, β≈3 ≈ 2+1)
- **Entropy injection:** XOR `sampled_bit` into `x[0]` each Euler step

- State: 3 × 16-bit (x, y, z), classic initial point (1.0, 1.0, 1.0)
- Output: `x[15]` (MSB of x variable), `out_valid` pulses once per Euler step
- `state_out[7:0] = x[15:8]`
- **Stuck/overflow guard:** Clamp state variables to prevent fixed-point overflow; re-seed if all three converge to zero

**Research value:** The Lorenz attractor is the iconic chaotic system. Having it on silicon as an entropy conditioner, directly comparable to simpler maps on the same die, is compelling for a paper — even if it's less area-efficient.

---

### 6. `src/cond_lfsr.v` — Fibonacci LFSR
**Estimated area:** ~60 cells | **Throughput:** 1 bit/clock

**Algorithm:**
```
feedback = lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]   // maximal-length polynomial
lfsr_next = {lfsr[14:0], feedback ^ sampled_bit}         // entropy into feedback
```
- State: 16-bit LFSR, seed `0xACE1`
- Polynomial: x^16 + x^14 + x^13 + x^11 + 1 (period 2^16 - 1)
- Output: `lfsr[15]`
- `state_out[7:0] = lfsr[15:8]`
- **Not chaotic** — linear, predictable. Included as a control/baseline to compare against the nonlinear conditioners.

---

## Top-Level Parameters

```verilog
module tt_um_chicagojones_tt09_trng_sky130 #(
    parameter INCLUDE_TENT_MAP     = 1,
    parameter INCLUDE_COUPLED_TENT = 1,
    parameter INCLUDE_LOGISTIC     = 1,
    parameter INCLUDE_BERNOULLI    = 1,
    parameter INCLUDE_LORENZ       = 1,
    parameter INCLUDE_LFSR         = 1
) ( ... );
```

To exclude a module at synthesis: `-PINCLUDE_LORENZ=0` in Makefile COMPILE_ARGS.

## Area Budget

| Component | Est. Cells | Cumulative | Utilization |
|-----------|-----------|------------|-------------|
| Current design | 1,038 | 1,038 | 40.7% |
| Tent map | ~90 | 1,128 | 44.2% |
| Coupled tent | ~200 | 1,328 | 52.1% |
| Logistic map | ~500 | 1,828 | 71.7% |
| Bernoulli shift | ~45 | 1,873 | 73.4% |
| Lorenz (Euler) | ~1000 | 2,873 | 112.7% ⚠️ |
| LFSR | ~60 | 2,933 | 115.0% ⚠️ |
| Mux + SPI decode | ~50 | ~2,983 | 117.0% ⚠️ |

**⚠️ All 6 modules together exceed the 75% target.** Recommended configurations:

| Config | Modules | Est. Cells | Util. |
|--------|---------|-----------|-------|
| **Full minus Lorenz** | Tent + Coupled + Logistic + Bernoulli + LFSR | ~1,983 | ~77% |
| **Chaotic only** | Tent + Coupled + Logistic + Bernoulli | ~1,873 | ~73% |
| **Lightweight** | Tent + Bernoulli + LFSR | ~1,233 | ~48% |
| **Kitchen sink** | All 6 | ~2,983 | ~117% ⚠️ |

The Lorenz module is the most expensive (~1000 cells) and produces output the slowest (~1 bit/20 clocks). It should be the first cut if area is tight, but is the most compelling for the paper. A possible compromise: implement Lorenz with reduced precision (8-bit Q4.4 instead of 16-bit Q8.8) to halve the cell count.

## SPI Register Map Additions

| Address | Content | Access |
|---------|---------|--------|
| 0x14 | tent_state[7:0] | Read-only |
| 0x15 | coupled_state[7:0] (x) | Read-only |
| 0x16 | coupled_state[15:8] (y) | Read-only |
| 0x17 | logistic_state[7:0] | Read-only |
| 0x18 | bernoulli_state[7:0] | Read-only |
| 0x19 | lorenz_state[7:0] (x) | Read-only |
| 0x1A | lorenz_state y[15:8] | Read-only |
| 0x1B | lorenz_state z[15:8] | Read-only |
| 0x1C | lfsr_state[7:0] | Read-only |
| 0x1D | capability bitmask | Read-only |

**Capability register (0x1D):**
```
{1'b0, INCLUDE_LFSR, INCLUDE_LORENZ, INCLUDE_BERNOULLI,
 INCLUDE_LOGISTIC, INCLUDE_COUPLED_TENT, INCLUDE_TENT_MAP, 1'b1}
```
Bit 0 = VN always present. Software reads this to discover which cond_sel values are valid.

## Changes to Existing Files

### `src/tt_um_trng_ro.v`
1. Add 6 `parameter` declarations to module header
2. Add `generate if` blocks for each conditioner instantiation (with tie-offs when excluded)
3. Replace `bypass_vn` logic with `cond_sel[2:0]` case mux
4. Expand SPI register read mux with new addresses
5. Add stuck-state protection wires

### `test/Makefile`
Add all new `.v` files to `PROJECT_SOURCES`.

### `test/test_trng.py`
**New tests:** One per conditioner (verify selection, byte_valid, state readback) + capability register test + switching test + invalid fallback test.

**Updated tests:** `test_ctrl_reg_bypass_vn` (use cond_sel=1 instead of bit 0), `test_spi_ctrl_reg` (new bit layout).

### `CLAUDE.md`
Update SPI register map table and architecture description.

## Implementation Sequence

1. Create the 6 new conditioner source files (independent, parallelizable)
2. Modify `tt_um_trng_ro.v`: parameters, generate blocks, mux, SPI registers
3. Update `test/Makefile`
4. Update `test/test_trng.py`
5. Run RTL sim: `cd test && make clean && make`
6. If area is too large, disable expensive modules via parameters and re-run GDS
7. Update documentation

## Key Design Decisions

- **Tent map state width (8-bit):** Sufficient for proof-of-concept; 16-bit would give longer orbits but costs 2x cells. Can be parameterized later.
- **Lorenz precision trade-off:** Q8.8 (16-bit) gives stable orbits but costs ~1000 cells. Q4.4 (8-bit) halves cost but risks overflow/convergence. Start with Q8.8, cut to Q4.4 if needed.
- **Logistic map multiplier:** Iterative shift-add (8 cycles per multiply) rather than combinational (too many cells). Acceptable throughput trade-off.
- **Entropy injection point:** All maps XOR `sampled_bit` into LSB of state. This is the simplest injection that preserves the map dynamics while ensuring physical entropy enters the system every iteration.
- **Backward compatibility:** `ctrl_reg` bit 0 is no longer `bypass_vn`. Code that wrote `0x01` for bypass must now write `0x20` (cond_sel=1).
