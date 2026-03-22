import numpy as np
import plotly.graph_objects as go
from plotly.subplots import make_subplots
import pandas as pd

class MultiPrecisionChaos:
    """
    Simulates chaotic maps at different bit-widths to study 
    precision collapse and cycle lengths.
    """
    
    @staticmethod
    def tent_map(x_int, bits=8, sampled_bit=0):
        mask = (1 << bits) - 1
        msb = 1 << (bits - 1)
        
        # Tent logic: if x < 0.5, 2x; else 2(1-x)
        if (x_int & msb):
            # 2 * (1-x) approx
            x_tent = ((~x_int) & mask) << 1
        else:
            x_tent = (x_int << 1) & mask
            
        # Entropy injection into LSB
        x_next = (x_tent & (mask ^ 1)) | ((x_tent & 1) ^ sampled_bit)
        
        # Avoid the zero-trap
        if x_next == 0: return 0xA5 & mask
        return x_next & mask

    @staticmethod
    def logistic_map(x_int, bits=8, sampled_bit=0):
        mask = (1 << bits) - 1
        # Logistic: 4 * x * (1-x)
        # In Q0.bits: result = (x * (mask - x)) >> (bits - 2)
        one_minus_x = mask - x_int
        product = x_int * one_minus_x
        
        # Scale back to 'bits' and multiply by 4 (shift left 2)
        # We shift right by (bits-2) to keep it in range
        x_next = (product >> (bits - 2)) & mask
        
        # Entropy injection
        x_next = (x_next & (mask ^ 1)) | ((x_next & 1) ^ sampled_bit)
        
        if x_next == 0: return 0x66 & mask
        return x_next & mask

def run_precision_study(map_type='tent', steps=500, inject_entropy=False):
    precisions = [8, 12, 16]
    results = {}
    
    for p in precisions:
        mask = (1 << p) - 1
        val = 0xA5A5 & mask
        traj = []
        
        # Simple PRNG for entropy injection if requested
        np.random.seed(42)
        entropy_bits = np.random.randint(0, 2, steps) if inject_entropy else [0]*steps
        
        for i in range(steps):
            if map_type == 'tent':
                val = MultiPrecisionChaos.tent_map(val, bits=p, sampled_bit=entropy_bits[i])
            else:
                val = MultiPrecisionChaos.logistic_map(val, bits=p, sampled_bit=entropy_bits[i])
            traj.append(val / mask) # Normalize to 0..1
        results[f"{p}-bit"] = traj
        
    return pd.DataFrame(results)

def plot_comparison():
    fig = make_subplots(
        rows=2, cols=2,
        subplot_titles=("Tent Map: 8-bit vs 16-bit (No Entropy)", 
                        "Tent Map: 8-bit vs 16-bit (WITH RO Entropy)",
                        "Logistic Map: 8-bit vs 16-bit (No Entropy)",
                        "Logistic Map: 8-bit vs 16-bit (WITH RO Entropy)")
    )

    # Row 1: Tent Map
    df_tent_no = run_precision_study('tent', inject_entropy=False)
    df_tent_en = run_precision_study('tent', inject_entropy=True)
    
    fig.add_trace(go.Scatter(y=df_tent_no['8-bit'][:100], name="Tent 8-bit (Dead)", line=dict(color='red')), row=1, col=1)
    fig.add_trace(go.Scatter(y=df_tent_no['16-bit'][:100], name="Tent 16-bit", line=dict(color='blue')), row=1, col=1)
    
    fig.add_trace(go.Scatter(y=df_tent_en['8-bit'][:100], name="Tent 8-bit + RO", line=dict(color='red')), row=1, col=2)
    fig.add_trace(go.Scatter(y=df_tent_en['16-bit'][:100], name="Tent 16-bit + RO", line=dict(color='blue')), row=1, col=2)

    # Row 2: Logistic Map
    df_log_no = run_precision_study('logistic', inject_entropy=False)
    df_log_en = run_precision_study('logistic', inject_entropy=True)
    
    fig.add_trace(go.Scatter(y=df_log_no['8-bit'][:100], name="Log 8-bit (Dead)", line=dict(color='orange')), row=2, col=1)
    fig.add_trace(go.Scatter(y=df_log_no['16-bit'][:100], name="Log 16-bit", line=dict(color='green')), row=2, col=1)
    
    fig.add_trace(go.Scatter(y=df_log_en['8-bit'][:100], name="Log 8-bit + RO", line=dict(color='orange')), row=2, col=2)
    fig.add_trace(go.Scatter(y=df_log_en['16-bit'][:100], name="Log 16-bit + RO", line=dict(color='green')), row=2, col=2)

    fig.update_layout(height=1000, width=1400, title_text="The 'Entropy Fuel' Effect: Precision vs. Stochastic Injection")
    fig.write_html("precision_analysis.html")
    print("Analysis saved to precision_analysis.html")

if __name__ == "__main__":
    plot_comparison()
