# Advanced TRNG Research Ideas

This document tracks future enhancements and research directions for the Scientist TRNG architecture.

## 1. The Three-Body Problem "Chaos" Engine
- **Concept:** Replace or supplement the Ring Oscillators with a digital simulation of a chaotic three-body system.
- **Implementation:** A small, high-speed fixed-point engine that iterates the equations of motion. The sensitivity to initial conditions (Lyapunov exponent) provides the entropy source.
- **Goal:** Compare structural (RO) entropy with algorithmic (Chaotic) entropy on the same silicon.

## 2. Galois Ring Oscillators (GRO) vs. Fibonacci Ring Oscillators (FRO)
- **Concept:** Implement non-linear feedback structures instead of simple inverter chains.
- **Impact:** GROs and FROs are known to produce much higher entropy density and are less susceptible to injection locking.
- **Goal:** Add a characterization bank to the SPI interface to measure the entropy rate of GRO vs. Standard RO.

## 3. Kolmogorov Complexity Proofs
- **Research Question:** Can we use the on-chip health monitors to provide a real-time lower bound on the Kolmogorov complexity of the generated stream?
- **Direction:** Integrate a small compression-based entropy estimator (like a Ziv-Lempel based sensor) to compare against the NIST APT results.

## 4. Power-Side-Channel Resistance
- **Concept:** Monitor the correlation between random bit generation and current spikes on the `VPWR` rail (if measurable).
- **Goal:** Design a "Balanced RO" that consumes constant power regardless of the bit being generated.
