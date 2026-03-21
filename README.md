# TT09 Tunable Ring Oscillator TRNG (IHP SG13G2)

A True Random Number Generator (TRNG) based on tunable ring oscillators, designed for Tiny Tapeout 09 (IHP SG13G2 process).

## Design Goals
- **Tunability:** Adjust the number of inverters in the ring to optimize entropy extraction.
- **Process Robustness:** Ensure the RO oscillates across PVT (Process, Voltage, Temperature) variations.
- **Compactness:** Fit within a single Tiny Tapeout tile (160um x 100um).
- **Interface:** Standard Tiny Tapeout 8x8x8 interface.

## Architecture (Proposed)
1. **Tunable RO Core:** Multiple rings with mux-selectable stages.
2. **Entropy Collector:** XORing the outputs of multiple ROs.
3. **Sampling Logic:** Capturing the jittery RO state with a reference clock.
4. **Post-processor:** von Neumann or simple whitening logic.

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
