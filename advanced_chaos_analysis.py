import numpy as np
import plotly.graph_objects as go
from plotly.subplots import make_subplots
import pandas as pd

class FullSuiteChaos:
    """
    Simulates the full suite of conditioners from tt09-trng-sky130.
    Updated with 24-bit derivative logic for Lorenz.
    """
    
    @staticmethod
    def tent_map(x_int, bits=8, sampled_bit=0):
        mask = (1 << bits) - 1
        msb = 1 << (bits - 1)
        if (x_int & msb):
            x_next = ((~x_int) & mask) << 1
        else:
            x_next = (x_int << 1) & mask
        x_next = (x_next & (mask ^ 1)) | ((x_next & 1) ^ sampled_bit)
        if x_next == 0: return 0xA5A5A5A5 & mask
        return x_next & mask

    @staticmethod
    def logistic_map(x_int, bits=8, sampled_bit=0):
        mask = (1 << bits) - 1
        one_minus_x = mask - x_int
        product = x_int * one_minus_x
        x_next = (product >> (bits - 2)) & mask
        x_next = (x_next & (mask ^ 1)) | ((x_next & 1) ^ sampled_bit)
        if x_next == 0: return 0x66666666 & mask
        return x_next & mask

    @staticmethod
    def lorenz_step(x, y, z, bits=16, sampled_bit=0):
        """
        Bit-accurate simulation of the fixed-point Lorenz implementation.
        Uses 24-bit intermediate derivatives to prevent overflow.
        """
        shift = bits // 2
        mask_state = (1 << bits) - 1
        # Q8.8 State decoding
        def to_s16(v): return (v & 0x7FFF) - (v & 0x8000)
        
        xs, ys, zs = to_s16(x), to_s16(y), to_s16(z)
        
        # dx = 10*(y-x) (24-bit signed)
        dx = 10 * (ys - xs)
        
        # dy = x*(28-z) - y
        # Scale 28 to Q8.8 (0x1C00)
        rho_minus_z = 0x1C00 - zs
        mul_dy = xs * rho_minus_z
        dy_partial = (mul_dy >> 8) - ys
        
        # dz = x*y - 3*z
        mul_dz = xs * ys
        dz_partial = (mul_dz >> 8) - ((zs << 1) + zs)
        
        # Euler Update: dt=3/256 ≈ 0.011
        # Update is: state <= state + ((dvar * 3) >> 8)
        def update(s, dvar):
            inc = ((dvar << 1) + dvar) >> 8
            return (s + inc) & 0xFFFF

        nx = update(xs, dx)
        ny = update(ys, dy_partial)
        nz = update(zs, dz_partial)
        
        # Entropy injection
        nx = (nx & 0xFFFE) | ((nx & 0x01) ^ sampled_bit)
        return nx, ny, nz

def run_analysis(steps=10000, bits=16, entropy=True):
    np.random.seed(42)
    ebits = np.random.randint(0, 2, steps) if entropy else [0]*steps
    
    # States
    t, l, lz_x, lz_y, lz_z = 0xA5, 0x66, 0x0100, 0x0100, 0x0100
    
    data = []
    for i in range(steps):
        t = FullSuiteChaos.tent_map(t, 8, ebits[i])
        l = FullSuiteChaos.logistic_map(l, 8, ebits[i])
        lz_x, lz_y, lz_z = FullSuiteChaos.lorenz_step(lz_x, lz_y, lz_z, 16, ebits[i])
        
        # Convert Lorenz to real for plotting
        lz_real_x = ((lz_x & 0x7FFF) - (lz_x & 0x8000)) / 256.0
        data.append([t/255.0, l/255.0, lz_real_x])
        
    return pd.DataFrame(data, columns=['Tent', 'Logistic', 'Lorenz'])

def plot_advanced_analysis():
    df = run_analysis(10000)
    
    fig = make_subplots(
        rows=2, cols=3,
        subplot_titles=("Tent Trajectory (8-bit)", "Logistic Trajectory (8-bit)", "Lorenz X-Trajectory (16-bit)",
                        "Tent Distribution", "Logistic Distribution", "Lorenz Distribution")
    )

    # Trajectories (first 200 points)
    fig.add_trace(go.Scatter(y=df['Tent'][:200], name="Tent"), row=1, col=1)
    fig.add_trace(go.Scatter(y=df['Logistic'][:200], name="Logistic"), row=1, col=2)
    fig.add_trace(go.Scatter(y=df['Lorenz'][:200], name="Lorenz"), row=1, col=3)

    # Distributions
    fig.add_trace(go.Histogram(x=df['Tent'], nbinsx=50, name="Tent Hist"), row=2, col=1)
    fig.add_trace(go.Histogram(x=df['Logistic'], nbinsx=50, name="Log Hist"), row=2, col=2)
    fig.add_trace(go.Histogram(x=df['Lorenz'], nbinsx=50, name="Lorenz Hist"), row=2, col=3)

    fig.update_layout(height=800, width=1500, title_text="Chaotic Conditioner Performance Analysis (Post-Lorenz Fix)")
    fig.write_html("fixed_chaos_analysis.html")
    print("Fixed analysis saved to fixed_chaos_analysis.html")

if __name__ == "__main__":
    plot_advanced_analysis()
