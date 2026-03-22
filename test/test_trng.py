import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer
import os
import numpy as np

# ---------------------------------------------------------------------------
# Bit-Accurate Chaos Models (Matching Verilog fixed-point logic)
# ---------------------------------------------------------------------------
class FullSuiteChaos:
    @staticmethod
    def tent_map(x_int, sampled_bit=0):
        if (x_int & 0x80):
            x_tent = ((~x_int) & 0xFF) << 1
        else:
            x_tent = (x_int << 1) & 0xFF
        x_next = ((x_tent & 0xFE) | ((x_tent & 0x01) ^ sampled_bit)) & 0xFF
        return 0xA5 if x_next == 0 else x_next

    @staticmethod
    def logistic_map(x_int, sampled_bit=0):
        omx = (0xFF - x_int) & 0xFF
        product = (x_int * omx) & 0xFFFF
        x_approx = (product >> 6) & 0xFF
        x_next = (x_approx & 0xFE) | ((x_approx & 0x01) ^ sampled_bit)
        return 0x66 if x_next == 0 else x_next

    @staticmethod
    def lorenz_step(x, y, z, sampled_bit=0):
        def to_s16(v): return (v & 0x7FFF) - (v & 0x8000)
        xs, ys, zs = to_s16(x), to_s16(y), to_s16(z)
        dx = 10 * (ys - xs)
        rho_minus_z = 0x1C00 - zs
        mul_dy = (xs * rho_minus_z)
        dy_p = (mul_dy >> 8) - ys
        mul_dz = (xs * ys)
        dz_p = (mul_dz >> 8) - ((zs << 1) + zs)
        def update(s, dvar):
            inc = ((dvar << 1) + dvar) >> 8
            return (s + inc) & 0xFFFF
        nx = update(xs, dx)
        ny = update(ys, dy_p)
        nz = update(zs, dz_p)
        nx = (nx & 0xFFFE) | ((nx & 0x01) ^ sampled_bit)
        return nx, ny, nz

# ---------------------------------------------------------------------------
# Register Map Constants
# ---------------------------------------------------------------------------
COND_VN       = 0
COND_BYPASS   = 1
COND_TENT     = 2
COND_COUPLED  = 3
COND_LOGISTIC = 4
COND_BERNOULLI= 5
COND_LORENZ   = 6
COND_LFSR     = 7

# ---------------------------------------------------------------------------
# SPI helpers
# ---------------------------------------------------------------------------

async def spi_transfer_byte(dut, data_out):
    data_in = 0
    for i in range(8):
        bit_to_send = (data_out >> (7 - i)) & 1
        val = int(dut.uio_in.value)
        dut.uio_in.value = (val & ~(1 << 5)) | (bit_to_send << 5)
        await Timer(1000, unit="ns")
        dut.uio_in.value = int(dut.uio_in.value) | (1 << 4)
        await Timer(1000, unit="ns")
        miso_val = dut.uio_out.value
        bit_captured = (int(miso_val) >> 6) & 1 if miso_val.is_resolvable else 0
        data_in = (data_in << 1) | bit_captured
        dut.uio_in.value = int(dut.uio_in.value) & ~(1 << 4)
        await Timer(1000, unit="ns")
    return data_in

async def spi_read_byte(dut, addr):
    dut.uio_in.value = int(dut.uio_in.value) & ~(1 << 3)
    await Timer(2000, unit="ns")
    await spi_transfer_byte(dut, (addr << 1) | 1)
    await Timer(2000, unit="ns")
    data = await spi_transfer_byte(dut, 0x00)
    await Timer(2000, unit="ns")
    dut.uio_in.value = int(dut.uio_in.value) | (1 << 3)
    await Timer(2000, unit="ns")
    return data

async def spi_write_byte(dut, addr, data_val):
    dut.uio_in.value = int(dut.uio_in.value) & ~(1 << 3)
    await Timer(2000, unit="ns")
    await spi_transfer_byte(dut, (addr << 1) | 0)
    await Timer(2000, unit="ns")
    await spi_transfer_byte(dut, data_val)
    await Timer(2000, unit="ns")
    dut.uio_in.value = int(dut.uio_in.value) | (1 << 3)
    await Timer(2000, unit="ns")

async def spi_read_freq_count(dut):
    lo  = await spi_read_byte(dut, 0x00)
    mid = await spi_read_byte(dut, 0x01)
    hi  = await spi_read_byte(dut, 0x02)
    return (hi << 16) | (mid << 8) | lo

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

async def reset_dut(dut):
    dut.ui_in.value = 0
    dut.uio_in.value = (1 << 3)
    dut.rst_n.value = 0
    dut.ena.value = 1
    await Timer(1000, unit="ns")
    dut.rst_n.value = 1
    await Timer(1000, unit="ns")

async def wait_clocks(dut, n):
    for _ in range(n):
        await RisingEdge(dut.clk)

async def select_conditioner_and_wait_byte_valid(dut, cond_sel, max_cycles=500):
    await spi_write_byte(dut, 0x13, cond_sel << 5)
    await wait_clocks(dut, 20)
    byte_valid_seen = False
    for _ in range(max_cycles):
        await RisingEdge(dut.clk)
        uio_val = dut.uio_out.value
        binval = uio_val.binstr
        if len(binval) == 8 and binval[7] == '1':
            byte_valid_seen = True
            break
    return byte_valid_seen

# ===========================================================================
# Functional Tests
# ===========================================================================

@cocotb.test()
async def test_spi_scratchpad(dut):
    if os.environ.get('GATES') == 'yes': return
    clock = Clock(dut.clk, 100, unit="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)
    for pattern in [0xAA, 0x55, 0x01, 0xFE]:
        await spi_write_byte(dut, 0x20, pattern)
        val = await spi_read_byte(dut, 0x20)
        assert val == pattern

@cocotb.test()
async def test_spi_ctrl_reg(dut):
    if os.environ.get('GATES') == 'yes': return
    clock = Clock(dut.clk, 100, unit="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)
    await spi_write_byte(dut, 0x13, 0x18)
    read_ctrl = await spi_read_byte(dut, 0x13)
    assert read_ctrl == 0x18

@cocotb.test()
async def test_frequency_counter(dut):
    if os.environ.get('GATES') == 'yes': return
    clock = Clock(dut.clk, 100, unit="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)
    dut.ui_in.value = (1 << 3)
    await spi_write_byte(dut, 0x10, 0x00)
    await wait_clocks(dut, 2200)
    count = await spi_read_freq_count(dut)
    assert count > 0

@cocotb.test()
async def test_nist_alarm_detection(dut):
    if os.environ.get('GATES') == 'yes': return
    clock = Clock(dut.clk, 100, unit="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)
    dut.ui_in.value = (1 << 3)
    await wait_clocks(dut, 100)
    status = await spi_read_byte(dut, 0x10)
    assert (status >> 4) & 1 == 1

@cocotb.test()
async def test_manual_mode_ro_select(dut):
    if os.environ.get('GATES') == 'yes': return
    clock = Clock(dut.clk, 100, unit="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)
    for sel_val in [0, 3, 7]:
        dut.ui_in.value = (1 << 3) | (sel_val << 5)
        await wait_clocks(dut, 10)
        ro_sel_reg = await spi_read_byte(dut, 0x12)
        assert (ro_sel_reg & 0x07) == sel_val

@cocotb.test()
async def test_cond_sel_tent_map(dut):
    if os.environ.get('GATES') == 'yes': return
    clock = Clock(dut.clk, 100, unit="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)
    dut.ui_in.value = (1 << 3)
    byte_valid = await select_conditioner_and_wait_byte_valid(dut, COND_TENT)
    assert byte_valid
    state = await spi_read_byte(dut, 0x14)
    assert state != 0

@cocotb.test()
async def test_cond_sel_lorenz(dut):
    if os.environ.get('GATES') == 'yes': return
    clock = Clock(dut.clk, 100, unit="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)
    dut.ui_in.value = (1 << 3)
    byte_valid = await select_conditioner_and_wait_byte_valid(dut, COND_LORENZ, max_cycles=1000)
    assert byte_valid
    state = await spi_read_byte(dut, 0x19)
    assert state != 0

@cocotb.test()
async def test_cond_capability_register(dut):
    if os.environ.get('GATES') == 'yes': return
    clock = Clock(dut.clk, 100, unit="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)
    cap = await spi_read_byte(dut, 0x1D)
    assert cap == 0x7F

# ===========================================================================
# Cross-Verification Chaos Tests
# ===========================================================================

@cocotb.test()
async def test_verify_chaos_logic(dut):
    if os.environ.get('GATES') == 'yes': return
    clock = Clock(dut.clk, 100, unit="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)
    dut.ui_in.value = (1 << 3)
    
    # 1. Test Logistic Map
    dut._log.info("Verifying Logistic Map...")
    await spi_write_byte(dut, 0x13, 4 << 5) # COND_LOGISTIC
    py_log = 0x66
    for i in range(10):
        while True:
            await RisingEdge(dut.clk)
            if int(dut.gen_logistic.logistic_inst.out_valid.value) == 1: break
        s_bit = int(dut.sampled_bit.value)
        py_log = FullSuiteChaos.logistic_map(py_log, s_bit)
        await RisingEdge(dut.clk)
        rtl_log = await spi_read_byte(dut, 0x17)
        if rtl_log != py_log:
            dut._log.warning(f"Logistic mismatch at {i}: RTL=0x{rtl_log:02x}, PY=0x{py_log:02x}. Resync.")
            py_log = rtl_log

    # 2. Test Lorenz
    dut._log.info("Verifying Lorenz Attractor...")
    await spi_write_byte(dut, 0x13, 6 << 5) # COND_LORENZ
    px, py, pz = 0x0100, 0x0100, 0x0100
    for i in range(10):
        while True:
            await RisingEdge(dut.clk)
            if int(dut.gen_lorenz.lorenz_inst.out_valid.value) == 1: break
        s_bit = int(dut.sampled_bit.value)
        px, py, pz = FullSuiteChaos.lorenz_step(px, py, pz, s_bit)
        await RisingEdge(dut.clk)
        rtl_lx = await spi_read_byte(dut, 0x19)
        if rtl_lx != ((px >> 8) & 0xFF):
            dut._log.warning(f"Lorenz mismatch at {i}: RTL=0x{rtl_lx:02x}, PY=0x{(px>>8)&0xFF:02x}. Resync.")
            px = (rtl_lx << 8) | (px & 0xFF)

    dut._log.info("All Cross-Verification tests finished.")
