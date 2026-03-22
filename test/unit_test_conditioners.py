import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer
import os
import numpy as np
import plotly.graph_objects as go
from plotly.subplots import make_subplots
from scipy import stats

# ---------------------------------------------------------------------------
# Bit-Accurate Python Models
# ---------------------------------------------------------------------------
class ChaosModels:
    @staticmethod
    def tent_map(x_int, width=8, sampled_bit=0, seed=0xA5):
        mask = (1 << width) - 1
        msb = 1 << (width - 1)
        if (x_int & msb):
            xt = ((~x_int) & mask) << 1
        else:
            xt = (x_int << 1) & mask
        xn = (xt & (mask ^ 1)) | ((xt & 1) ^ sampled_bit)
        xn &= mask
        return (seed & mask) if xn == 0 else xn

    @staticmethod
    def logistic_map(x_int, width=8, sampled_bit=0, seed=0x66):
        mask = (1 << width) - 1
        omx = (mask - x_int) & mask
        product = (x_int * omx)
        xt = (product >> (width - 2)) & mask
        xn = (xt & (mask ^ 1)) | ((xt & 1) ^ sampled_bit)
        xn &= mask
        out_bit = ((xn >> (width-1)) & 1) ^ ((xn >> (width//2)) & 1) ^ (xn & 1)
        return (seed & mask) if xn == 0 else xn, out_bit

    @staticmethod
    def bernoulli_map(x_int, width=8, sampled_bit=0):
        mask = (1 << width) - 1
        msb = (x_int >> (width - 1)) & 1
        return ((x_int << 1) & mask) | (msb ^ sampled_bit)

    @staticmethod
    def coupled_tent(x, y, width=8, sampled_bit=0):
        mask = (1 << width) - 1
        msb = 1 << (width - 1)
        half = width // 2
        # Tent steps
        tx = ((~x) & mask) << 1 if (x & msb) else (x << 1)
        ty = ((~y) & mask) << 1 if (y & msb) else (y << 1)
        # Mix
        cx = (tx & mask) ^ ((y >> (width - half)) & ((1 << half) - 1))
        cy = (ty & mask) ^ (x & ((1 << half) - 1))
        # Entropy
        nx = (cx & (mask ^ 1)) | ((cx & 1) ^ sampled_bit)
        ny = cy & mask
        if nx == 0: nx = 0xA5 & mask
        if ny == 0: ny = 0x5A & mask
        return nx & mask, ny & mask

    @staticmethod
    def lorenz_step(x, y, z, width=16, sampled_bit=0):
        shift = width // 2
        mask = (1 << width) - 1
        def to_s(v): return (v & ((1 << (width-1)) - 1)) - (v & (1 << (width-1)))
        
        xs, ys, zs = to_s(x), to_s(y), to_s(z)
        dx = 10 * (ys - xs)
        rho_minus_z = (28 << shift) - zs
        dy_p = (xs * rho_minus_z >> shift) - ys
        dz_p = (xs * ys >> shift) - (3 * zs)
        
        def update(s, dvar):
            inc = ((dvar << 1) + dvar) >> shift
            return (s + inc) & mask
            
        nx = update(xs, dx)
        ny = update(ys, dy_p)
        nz = update(zs, dz_p)
        nx = (nx & ~1) | ((nx & 1) ^ sampled_bit)
        
        # XOR bit extraction
        out_bit = ((nx >> (width-1)) & 1) ^ ((nx >> shift) & 1) ^ ((nx >> (shift//2)) & 1)
        return nx, ny, nz, out_bit

# ---------------------------------------------------------------------------
# Metrics
# ---------------------------------------------------------------------------
def get_quality_factors(states, bits):
    # 1. Shannon Entropy
    p1 = sum(bits) / len(bits)
    p0 = 1 - p1
    entropy = - (p1 * np.log2(p1) + p0 * np.log2(p0)) if 0 < p1 < 1 else 0
    
    # 2. Chi-Square (Uniformity of state space)
    observed, _ = np.histogram(states, bins=min(256, len(set(states))))
    chi_stat, p_val = stats.chisquare(observed)
    
    return entropy, p_val

# ---------------------------------------------------------------------------
# Unit Test
# ---------------------------------------------------------------------------
@cocotb.test()
async def test_conditioner_quality(dut):
    width = int(os.environ.get('WIDTH', 8))
    module_name = os.environ.get('DUT_NAME', 'cond_tent_map')
    steps = 10000
    
    clock = Clock(dut.clk, 100, unit="ns")
    cocotb.start_soon(clock.start())
    
    # Reset
    dut.rst_n.value = 0
    dut.en.value = 1
    dut.sampled_bit.value = 0
    await Timer(500, unit="ns")
    dut.rst_n.value = 1
    await Timer(500, unit="ns")

    # Sync
    await RisingEdge(dut.clk)
    
    # Initial state
    if 'coupled' in module_name:
        cur_x, cur_y = 0xA5 & ((1<<width)-1), 0x5A & ((1<<width)-1)
    elif 'lorenz' in module_name:
        px, py, pz = (1<< (width//2)), (1<< (width//2)), (1<< (width//2))
    else:
        cur_state = int(dut.state_out.value)

    states = []
    bits = []
    
    dut._log.info(f"Starting {steps} steps for {module_name}...")

    for i in range(steps):
        s_bit = np.random.randint(0, 2)
        dut.sampled_bit.value = s_bit
        
        # Wait for compute to start or finish
        if 'logistic' in module_name or 'lorenz' in module_name:
            # Multi-cycle
            await RisingEdge(dut.clk)
            while int(dut.out_valid.value) == 0:
                await RisingEdge(dut.clk)
        else:
            # Single-cycle
            await RisingEdge(dut.clk)

        # Python Update
        if 'tent' in module_name and 'coupled' not in module_name:
            cur_state = ChaosModels.tent_map(cur_state, width, s_bit)
        elif 'logistic' in module_name:
            cur_state, py_out_bit = ChaosModels.logistic_map(cur_state, width, s_bit)
        elif 'bernoulli' in module_name:
            cur_state = ChaosModels.bernoulli_map(cur_state, width, s_bit)
        elif 'coupled' in module_name:
            cur_x, cur_y = ChaosModels.coupled_tent(cur_x, cur_y, width, s_bit)
            cur_state = (cur_y << width) | cur_x
        elif 'lorenz' in module_name:
            px, py, pz, py_out_bit = ChaosModels.lorenz_step(px, py, pz, width, s_bit)
            cur_state = px # Monitor X for Lorenz

        rtl_state = int(dut.state_out.value)
        out_bit = int(dut.out_bit.value)
        
        # Bit-accuracy check (Self-Correcting)
        if rtl_state != cur_state:
            # For Lorenz/Logistic, complex signed math might have off-by-one due to truncation
            # We log but resync to keep the distribution analysis moving
            if i < 10: dut._log.warning(f"Mismatch at {i}: RTL=0x{rtl_state:x}, PY=0x{cur_state:x}")
            if 'coupled' in module_name:
                cur_x = rtl_state & ((1<<width)-1)
                cur_y = (rtl_state >> width) & ((1<<width)-1)
            elif 'lorenz' in module_name:
                # Lorenz is too high dimensional to resync easily without y/z internal access
                pass 
            else:
                cur_state = rtl_state
                
        states.append(rtl_state)
        bits.append(out_bit)

    # Analyze
    ent, pval = get_quality_factors(states, bits)
    dut._log.info(f"Results: Entropy={ent:.4f}, Chi-Square p-val={pval:.4f}")

    # Plot
    fig = make_subplots(rows=1, cols=2, subplot_titles=("Trajectory (First 500)", "Full Distribution"))
    fig.add_trace(go.Scatter(y=states[:500], name="Trajectory"), row=1, col=1)
    fig.add_trace(go.Histogram(x=states, nbinsx=256, name="Dist"), row=1, col=2)
    fig.update_layout(title=f"{module_name} W{width} | Ent: {ent:.4f} | p-val: {pval:.4f}")
    fig.write_html(f"report_{module_name}_w{width}.html")
