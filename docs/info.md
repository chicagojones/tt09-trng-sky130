<!---

This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

## How it works

This project implements a True Random Number Generator (TRNG) based on the phase jitter of multiple Ring Oscillators (ROs). 

1. **Entropy Core:** Three separate Ring Oscillators are instantiated. One RO is "tunable," allowing its feedback path length to be selected via external pins or an internal auto-tuner. The other two ROs have fixed lengths.
2. **Mixing:** The outputs of the three ROs are XORed together to produce a combined, highly jittery asynchronous bitstream.
3. **Sampling & Synchronization:** The asynchronous stream is sampled by the 10MHz system clock. A 4-stage synchronizer is used to mitigate potential metastability issues arising from the high-speed RO signals.
4. **Whitening:** The sampled bits pass through a von Neumann whitener, which eliminates bias by processing non-overlapping pairs of bits.
5. **Output:** An 8-bit shift register collects the whitened bits and pulses a `valid` strobe on `uio_out[0]` when a full byte is ready on `uo_out[7:0]`.
6. **Health Monitor:** A 1024-cycle running disparity checker monitors the entropy health. If the balance of 1s and 0s is outside acceptable bounds, it can trigger the auto-tuner to change the RO configuration.

## How to test

1. **Manual Mode:** Set `ui_in[4]` (Auto Mode) to `0`. Set `ui_in[3]` (Enable) to `1`. Select a manual RO length using `ui_in[7:5]`. Monitor `uio_out[0]` for the byte-valid strobe and read the random byte from `uo_out[7:0]`.
2. **Auto Mode:** Set `ui_in[4]` to `1` and `ui_in[3]` to `1`. The internal logic will automatically cycle through RO configurations until the health monitor's running disparity test passes.
3. **Observation:** Due to the von Neumann whitener, the rate of random byte generation will be variable and slower than the system clock.

## External hardware

None required. Standard Tiny Tapeout carrier board.
