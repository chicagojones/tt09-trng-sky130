# TT09 Tunable Ring Oscillator TRNG (Sky130)

A True Random Number Generator (TRNG) based on tunable ring oscillators, designed for Tiny Tapeout 09 (Sky130 sky26a process).

## Design Goals
- **Tunability:** Adjust the number of inverters in the ring to optimize entropy extraction.
- **Process Robustness:** Ensure the RO oscillates across PVT (Process, Voltage, Temperature) variations.
- **Compactness:** Fit within 2x2 Tiny Tapeout tiles (334um x 225um).
- **Interface:** Standard Tiny Tapeout 8x8x8 interface.

## Architecture
1. **Multi-RO Core:** 3 parallel Ring Oscillators (1 tunable, 2 fixed) XORed together.
2. **Entropy Collector:** Sampling logic with a 4-stage synchronizer for metastability mitigation.
3. **Post-processor:** von Neumann whitener to remove bias.
4. **Health Monitor:** 1024-bit window running disparity check with auto-tuning feedback.
5. **UART Output:** Transmits each random byte at 115200 baud on `uio_out[1]`.

## Top Module
The top module is `tt_um_chicagojones_trng_ro`.

## Project Structure
- `src/`: Verilog source files.
- `test/`: Cocotb testbenches and simulations.
- `docs/`: Documentation and simulation results.
- `info.yaml`: Tiny Tapeout configuration.

## Next Steps
1. **Verification:** Install dependencies and run the Cocotb testbench.
   ```bash
   pip install -r requirements.txt
   cd test
   make
   ```
2. **Improve Entropy:** Consider XORing multiple ROs with different lengths to improve the randomness.
3. **Whitening:** Add a von Neumann corrector or a simple LFSR to post-process the output.
4. **Physical Design:** Use the OpenLane flow to harden the design for IHP SG13G2. Pay attention to the RO placement to ensure balanced delays.
5. **Characterization:** Run gate-level simulations with extracted timing to see real RO behavior.
