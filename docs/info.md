<!---

This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

## How it works

This project implements a research-grade True Random Number Generator (TRNG) based on the phase jitter of an 8-oscillator Ring Oscillator (RO) bank.

1. **Entropy Core:** Eight independent Ring Oscillators are instantiated. One RO is "tunable" (3-31 stages), while seven have fixed prime-number lengths (13, 17, 19, 23, 29, 31, 37 stages) and varied drive strengths to maximize frequency diversity and prevent phase-locking.
2. **Mixing:** The outputs of the eight ROs are XORed together to produce a combined, high-entropy asynchronous bitstream.
3. **Sampling & Synchronization:** The asynchronous stream is sampled by the 10MHz system clock. A 4-stage synchronizer is used to mitigate potential metastability issues.
4. **Health Monitoring:** Real-time NIST SP 800-90B health monitors (Repetition Count Test and Adaptive Proportion Test) continuously track the entropy quality. Failures trigger an "Alarm" that can drive an auto-tuner to cycle RO configurations.
5. **Whitening:** The sampled bits pass through a von Neumann whitener to eliminate bias.
6. **Interface:** 
   - **Parallel:** 8-bit random bytes are available on `uo_out[7:0]` with a valid strobe on `uio_out[0]`.
   - **UART:** Random bytes are transmitted at 115200 baud on `uio_out[1]`.
   - **SPI:** A comprehensive register map allows reading RO frequencies (via a 24-bit counter), NIST status, and configuring fail-safe modes.

## How to test

1. **Basic Operation:** Set `ui_in[3]` (Enable) to `1`. Random data will begin flowing on `uo_out` and the UART TX pin.
2. **SPI Characterization:** Use an SPI master to read registers `0x00-0x02` to see the frequency count of the currently selected RO. Use register `0x10` to cycle through all 8 oscillators.
3. **Fail-Safe Testing:** Write to SPI register `0x13` to bypass the whitener (bit 0) or force manual tuning mode (bit 1). Route raw sampled bits to the output pins for profiling (bits [4:3]).

## External hardware

None required. Standard Tiny Tapeout carrier board. SPI and UART pins are available on the PMOD connectors.
