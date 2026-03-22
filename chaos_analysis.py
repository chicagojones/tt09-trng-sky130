import numpy as np
import plotly.graph_objects as go
from plotly.subplots import make_subplots
import pandas as pd

class FixedPointChaos:
    """
    Simulates chaotic maps using bit-accurate fixed-point logic
    mirrored from the tt09-trng-sky130 Verilog implementation.
    """
    
    @staticmethod
    def tent_map(x_int, sampled_bit=0):
        """Mirror of cond_tent_map.v (8-bit)"""
        # wire [7:0] x_tent = x[7] ? (~x << 1) : (x << 1);
        if (x_int & 0x80):
            x_tent = ((~x_int) & 0xFF) << 1
        else:
            x_tent = (x_int << 1) & 0xFF
            
        # wire [7:0] x_next = {x_tent[7:1], x_tent[0] ^ sampled_bit};
        x_next = (x_tent & 0xFE) | ((x_tent & 0x01) ^ sampled_bit)
        
        # x <= (x_next == 8'h00) ? SEED : x_next;
        if x_next == 0:
            return 0xA5 # SEED
        return x_next & 0xFF

    @staticmethod
    def logistic_map(x_int, sampled_bit=0):
        """Mirror of cond_logistic.v (8-bit Q0.8)"""
        # one_minus_x = 8'hFF - x;
        # product = x * (255 - x)
        product = x_int * (0xFF - x_int)
        
        # x <= {product[13:8], product[7] ^ sampled_bit, product[6]};
        upper = (product >> 8) & 0x3F
        bit7 = ((product >> 7) & 1) ^ sampled_bit
        bit6 = (product >> 6) & 1
        
        x_next = (upper << 2) | (bit7 << 1) | bit6
        if x_next == 0:
            return 0x66 # SEED
        return x_next & 0xFF

    @staticmethod
    def lorenz_step(x, y, z, dt_val=3, sampled_bit=0):
        """
        Mirror of cond_lorenz.v (16-bit Q8.8 signed)
        Uses Euler method with bit-accurate shifts.
        """
        def to_signed(val):
            return (val & 0x7FFF) - (val & 0x8000)
        
        def clamp16(val):
            return val & 0xFFFF

        # dx = 10*(y-x) = (y-x)<<3 + (y-x)<<1
        diff_yx = to_signed(y) - to_signed(x)
        dx = (diff_yx << 3) + (diff_yx << 1)
        
        # dy = x*(28-z) - y
        # mul_result is Q16.16, take [23:8] for Q8.8
        rho_minus_z = 0x1C00 - to_signed(z)
        mul_dy = to_signed(x) * rho_minus_z
        dy_partial = (mul_dy >> 8) - to_signed(y)
        
        # dz = x*y - 3*z
        mul_dz = to_signed(x) * to_signed(y)
        dz_partial = (mul_dz >> 8) - ((to_signed(z) << 1) + to_signed(z))
        
        # Update: var += (dvar * 3) >> 8
        x_next = to_signed(x) + (((dx << 1) + dx) >> 8)
        y_next = to_signed(y) + (((dy_partial << 1) + dy_partial) >> 8)
        z_next = to_signed(z) + (((dz_partial << 1) + dz_partial) >> 8)
        
        # Entropy injection: x[0] <= x[0] ^ sampled_bit
        x_final = clamp16(x_next)
        x_final = (x_final & 0xFFFE) | ((x_final & 0x01) ^ sampled_bit)
        
        return x_final, clamp16(y_next), clamp16(z_next)

def run_simulation(steps=1000):
    # Initial States
    t_val = 0xA5
    l_val = 0x66
    lx, ly, lz = 0x0100, 0x0100, 0x0100
    
    data = []
    
    for i in range(steps):
        # 1. Tent Map
        t_val = FixedPointChaos.tent_map(t_val)
        # 2. Logistic Map
        l_val = FixedPointChaos.logistic_map(l_val)
        # 3. Lorenz step
        lx, ly, lz = FixedPointChaos.lorenz_step(lx, ly, lz)
        
        data.append({
            'step': i,
            'tent': t_val / 255.0,
            'logistic': l_val / 255.0,
            'lorenz_x': ((lx & 0x7FFF) - (lx & 0x8000)) / 256.0,
            'lorenz_y': ((ly & 0x7FFF) - (ly & 0x8000)) / 256.0,
            'lorenz_z': ((lz & 0x7FFF) - (lz & 0x8000)) / 256.0
        })
        
    return pd.DataFrame(data)

def plot_chaos(df):
    fig = make_subplots(
        rows=2, cols=2,
        specs=[[{"type": "xy"}, {"type": "scene"}],
               [{"type": "xy"}, {"type": "xy"}]],
        subplot_titles=("Tent Map Trajectory", "Lorenz Attractor (3D)", 
                        "Logistic Map Trajectory", "Lorenz X-Y Phase Plane")
    )

    # 1. Tent Map
    fig.add_trace(go.Scatter(x=df['step'][:200], y=df['tent'][:200], name="Tent"), row=1, col=1)
    
    # 2. Lorenz 3D
    fig.add_trace(go.Scatter3d(x=df['lorenz_x'], y=df['lorenz_y'], z=df['lorenz_z'],
                               mode='lines', line=dict(width=2, color='royalblue'),
                               name="Lorenz 3D"), row=1, col=2)
    
    # 3. Logistic Map
    fig.add_trace(go.Scatter(x=df['step'][:200], y=df['logistic'], name="Logistic"), row=2, col=1)
    
    # 4. Lorenz Phase Plane
    fig.add_trace(go.Scatter(x=df['lorenz_x'], y=df['lorenz_y'], mode='lines', name="Lorenz XY"), row=2, col=2)

    fig.update_layout(height=900, width=1200, title_text="Fixed-Point Chaotic Map Analysis (tt09-trng-sky130)")
    fig.write_html("chaos_analysis.html")
    print("Analysis saved to chaos_analysis.html")

if __name__ == "__main__":
    print("Running Bit-Accurate Chaos Simulation...")
    df = run_simulation(5000)
    plot_chaos(df)
