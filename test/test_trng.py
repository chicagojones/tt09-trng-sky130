import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer
import os

# ---------------------------------------------------------------------------
# Register Map (b867440 version)
# ---------------------------------------------------------------------------
# 0x00: freq_count[7:0]     (read-only, multiplexed by freq_mux_sel)
# 0x01: freq_count[15:8]
# 0x02: freq_count[23:16]
# 0x10: {3'b0, alarm, 1'b0, freq_mux_sel[2:0]}  (freq_mux_sel writable)
# 0x11: out_reg              (read-only, last random byte)
# 0x12: {5'b0, ro_sel[2:0]} (read-only)
# 0x13: ctrl_reg             (read/write)
#       bit 0: bypass_vn, bit 1: force_manual, bit 2: mask_alarm, bits[4:3]: uo_sel
# 0x20: scratch_reg          (read/write)

# ---------------------------------------------------------------------------
# SPI helpers (Mode 0: sample on rising edge, shift on falling edge)
# ---------------------------------------------------------------------------

async def spi_transfer_byte(dut, data_out):
    """Sends 8 bits on MOSI and captures 8 bits from MISO simultaneously."""
    data_in = 0
    for i in range(8):
        bit_to_send = (data_out >> (7 - i)) & 1

        # 1. Setup MOSI (uio[5])
        val = int(dut.uio_in.value)
        dut.uio_in.value = (val & ~(1 << 5)) | (bit_to_send << 5)
        await Timer(1000, unit="ns")

        # 2. Rising Edge – slave samples MOSI
        dut.uio_in.value = int(dut.uio_in.value) | (1 << 4)
        await Timer(1000, unit="ns")

        # 3. Sample MISO (uio[6])
        miso_val = dut.uio_out.value
        bit_captured = 0
        if miso_val.is_resolvable:
            bit_captured = (int(miso_val) >> 6) & 1
        data_in = (data_in << 1) | bit_captured

        # 4. Falling Edge – slave shifts next bit out
        dut.uio_in.value = int(dut.uio_in.value) & ~(1 << 4)
        await Timer(1000, unit="ns")

    return data_in


async def spi_read_byte(dut, addr):
    """SPI read: command byte (addr, R/W=1) then dummy data byte."""
    dut.uio_in.value = int(dut.uio_in.value) & ~(1 << 3)   # CS_N low
    await Timer(2000, unit="ns")
    await spi_transfer_byte(dut, (addr << 1) | 1)           # command
    await Timer(2000, unit="ns")
    data = await spi_transfer_byte(dut, 0x00)               # data
    await Timer(2000, unit="ns")
    dut.uio_in.value = int(dut.uio_in.value) | (1 << 3)     # CS_N high
    await Timer(2000, unit="ns")
    return data


async def spi_write_byte(dut, addr, data_val):
    """SPI write: command byte (addr, R/W=0) then data byte."""
    dut.uio_in.value = int(dut.uio_in.value) & ~(1 << 3)   # CS_N low
    await Timer(2000, unit="ns")
    await spi_transfer_byte(dut, (addr << 1) | 0)           # command
    await Timer(2000, unit="ns")
    await spi_transfer_byte(dut, data_val)                   # data
    await Timer(2000, unit="ns")
    dut.uio_in.value = int(dut.uio_in.value) | (1 << 3)     # CS_N high
    await Timer(2000, unit="ns")


async def spi_read_freq_count(dut):
    """Read the 24-bit multiplexed frequency counter (regs 0x00-0x02)."""
    lo  = await spi_read_byte(dut, 0x00)
    mid = await spi_read_byte(dut, 0x01)
    hi  = await spi_read_byte(dut, 0x02)
    return (hi << 16) | (mid << 8) | lo

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

async def reset_dut(dut):
    """Standard power-on reset sequence."""
    dut.ui_in.value = 0
    dut.uio_in.value = (1 << 3)   # CS_N high
    dut.rst_n.value = 0
    dut.ena.value = 1
    await Timer(500, unit="ns")
    dut.rst_n.value = 1
    await Timer(500, unit="ns")


async def wait_clocks(dut, n):
    """Wait for *n* rising edges of clk."""
    for _ in range(n):
        await RisingEdge(dut.clk)

# ===========================================================================
# Tests
# ===========================================================================

@cocotb.test()
async def test_spi_scratchpad(dut):
    """Write/read scratchpad with complementary patterns (0xAA, 0x55)."""
    if os.environ.get('GATES') == 'yes':
        dut._log.info("GLS – skipping"); return

    clock = Clock(dut.clk, 100, unit="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)
    dut.ui_in.value = (1 << 3)  # en=1

    for pattern in [0xAA, 0x55, 0x01, 0xFE]:
        await spi_write_byte(dut, 0x20, pattern)
        val = await spi_read_byte(dut, 0x20)
        dut._log.info(f"Scratchpad write 0x{pattern:02x} -> read 0x{val:02x}")
        assert val == pattern, f"Scratchpad mismatch: expected 0x{pattern:02x}, got 0x{val:02x}"

    dut._log.info("PASS – scratchpad read/write verified with 4 patterns")


@cocotb.test()
async def test_spi_ctrl_reg(dut):
    """Control register (0x13) write/readback."""
    if os.environ.get('GATES') == 'yes':
        dut._log.info("GLS – skipping"); return

    clock = Clock(dut.clk, 100, unit="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)
    dut.ui_in.value = (1 << 3)

    # Write 0x18 = uo_sel=11, mask_alarm=0, force_manual=0, bypass_vn=0
    await spi_write_byte(dut, 0x13, 0x18)
    read_ctrl = await spi_read_byte(dut, 0x13)
    dut._log.info(f"Control Reg write 0x18 -> read 0x{read_ctrl:02x}")
    assert read_ctrl == 0x18, f"Expected 0x18, got 0x{read_ctrl:02x}"

    # Write 0x07 = bypass_vn=1, force_manual=1, mask_alarm=1
    await spi_write_byte(dut, 0x13, 0x07)
    read_ctrl = await spi_read_byte(dut, 0x13)
    dut._log.info(f"Control Reg write 0x07 -> read 0x{read_ctrl:02x}")
    assert read_ctrl == 0x07, f"Expected 0x07, got 0x{read_ctrl:02x}"

    dut._log.info("PASS – ctrl_reg read/write verified")


@cocotb.test()
async def test_spi_freq_mux_sel(dut):
    """Freq mux select (0x10 bits[2:0]) write/readback."""
    if os.environ.get('GATES') == 'yes':
        dut._log.info("GLS – skipping"); return

    clock = Clock(dut.clk, 100, unit="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)
    dut.ui_in.value = (1 << 3)

    for mux_val in [5, 3, 7, 0]:
        await spi_write_byte(dut, 0x10, mux_val)
        status = await spi_read_byte(dut, 0x10)
        got_mux = status & 0x07
        dut._log.info(f"Freq mux write {mux_val} -> status 0x{status:02x}, mux={got_mux}")
        assert got_mux == mux_val, f"Expected freq_mux_sel={mux_val}, got {got_mux}"

    dut._log.info("PASS – freq_mux_sel read/write verified")


@cocotb.test()
async def test_spi_readonly_status(dut):
    """Status register (0x10) format bits must stay correct after writes."""
    if os.environ.get('GATES') == 'yes':
        dut._log.info("GLS – skipping"); return

    clock = Clock(dut.clk, 100, unit="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)
    dut.ui_in.value = (1 << 3)

    before = await spi_read_byte(dut, 0x10)
    await spi_write_byte(dut, 0x10, 0xFF)
    after  = await spi_read_byte(dut, 0x10)
    dut._log.info(f"Status before write: 0x{before:02x}, after write: 0x{after:02x}")

    # Hardwired bits must stay 0: bits[7:5]=3'b0, bit[3]=1'b0
    assert (after & 0xE8) == 0x00, f"Status format bits corrupted: 0x{after:02x}"
    # freq_mux_sel should be 0x07 (only 3 bits writable from 0xFF)
    assert (after & 0x07) == 0x07, f"Expected freq_mux_sel=7 after writing 0xFF, got {after & 0x07}"
    dut._log.info("PASS – status register format bits preserved")


@cocotb.test()
async def test_spi_default_register(dut):
    """Unimplemented addresses must read back 0x00."""
    if os.environ.get('GATES') == 'yes':
        dut._log.info("GLS – skipping"); return

    clock = Clock(dut.clk, 100, unit="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)
    dut.ui_in.value = (1 << 3)

    for addr in [0x3F, 0x30, 0x25]:
        val = await spi_read_byte(dut, addr)
        dut._log.info(f"Addr 0x{addr:02x} -> 0x{val:02x}")
        assert val == 0x00, f"Expected 0x00 at unimplemented addr 0x{addr:02x}, got 0x{val:02x}"

    dut._log.info("PASS – unimplemented addresses return 0x00")


@cocotb.test()
async def test_frequency_counter(dut):
    """After 2 measurement windows (~2048 clk), the multiplexed freq counter must be non-zero."""
    if os.environ.get('GATES') == 'yes':
        dut._log.info("GLS – skipping"); return

    clock = Clock(dut.clk, 100, unit="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)
    dut.ui_in.value = (1 << 3)  # en=1

    # Select RO0 for measurement
    await spi_write_byte(dut, 0x10, 0x00)

    # Wait for at least 2 full 1024-cycle measurement windows
    await wait_clocks(dut, 2200)

    count = await spi_read_freq_count(dut)
    dut._log.info(f"RO0 full 24-bit count: {count} (0x{count:06x})")

    # In simulation, ROs toggle every clock -> ~512 edges per 1024-cycle window
    assert count > 0, "RO0 frequency counter stuck at zero"
    dut._log.info(f"PASS – RO0 count = {count} (expected ~512 in sim)")


@cocotb.test()
async def test_frequency_counter_multiple_ros(dut):
    """Verify frequency counter works for multiple RO selections via freq_mux_sel."""
    if os.environ.get('GATES') == 'yes':
        dut._log.info("GLS – skipping"); return

    clock = Clock(dut.clk, 100, unit="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)
    dut.ui_in.value = (1 << 3)

    counts = []
    for ro in [0, 3, 7]:
        # Select RO for measurement
        await spi_write_byte(dut, 0x10, ro)
        # Wait for counter reset + 2 measurement windows
        await wait_clocks(dut, 2200)
        c = await spi_read_freq_count(dut)
        counts.append(c)
        dut._log.info(f"RO{ro} 24-bit count: {c}")

    for i, c in enumerate(counts):
        assert c > 0, f"Frequency counter is zero for RO selection {[0,3,7][i]}"

    # In sim all ROs toggle identically, so counts should be similar
    dut._log.info(f"PASS – frequency counter non-zero for ROs 0, 3, 7: {counts}")


@cocotb.test()
async def test_nist_alarm_detection(dut):
    """In sim, all ROs toggle identically -> XOR=0 -> constant sampled_bit.
    The RCT should fire after ~32 consecutive identical bits."""
    if os.environ.get('GATES') == 'yes':
        dut._log.info("GLS – skipping"); return

    clock = Clock(dut.clk, 100, unit="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    # Manual mode (auto_en=0), man_sel=0, en=1
    dut.ui_in.value = (1 << 3)

    # Wait enough cycles for the 4-stage sync + 32-bit RCT window + 1 alarm reg
    await wait_clocks(dut, 50)

    status = await spi_read_byte(dut, 0x10)
    alarm_bit = (status >> 4) & 1
    freq_mux = status & 0x07
    dut._log.info(f"Status: 0x{status:02x}  alarm={alarm_bit}  freq_mux={freq_mux}")
    assert alarm_bit == 1, f"Expected NIST alarm to be set (constant sampled_bit in sim), got status 0x{status:02x}"
    dut._log.info("PASS – NIST health alarm detected (constant bit stream)")


@cocotb.test()
async def test_manual_mode_ro_select(dut):
    """In manual mode (auto_en=0), ro_sel must track ui_in[7:5]."""
    if os.environ.get('GATES') == 'yes':
        dut._log.info("GLS – skipping"); return

    clock = Clock(dut.clk, 100, unit="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    for sel_val in [0, 3, 5, 7]:
        # auto_en=0, en=1 (bit 3), man_sel in bits [7:5]
        dut.ui_in.value = (1 << 3) | (sel_val << 5)
        await wait_clocks(dut, 10)

        # ro_sel is at register 0x12 bits[2:0]
        ro_sel_reg = await spi_read_byte(dut, 0x12)
        ro_sel = ro_sel_reg & 0x07
        dut._log.info(f"man_sel={sel_val} -> ro_sel={ro_sel}  reg_0x12=0x{ro_sel_reg:02x}")
        assert ro_sel == sel_val, f"Expected ro_sel={sel_val}, got {ro_sel}"

    dut._log.info("PASS – manual mode RO selection works")


@cocotb.test()
async def test_auto_tuner_cycling(dut):
    """In auto mode, the alarm should cause ro_sel to increment."""
    if os.environ.get('GATES') == 'yes':
        dut._log.info("GLS – skipping"); return

    clock = Clock(dut.clk, 100, unit="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    # auto_en=1 (bit 4), en=1 (bit 3)
    dut.ui_in.value = (1 << 3) | (1 << 4)

    # Wait for first alarm + auto-tuner response
    await wait_clocks(dut, 50)

    ro_sel_reg = await spi_read_byte(dut, 0x12)
    ro_sel_first = ro_sel_reg & 0x07
    dut._log.info(f"After first alarm: ro_sel={ro_sel_first}  reg_0x12=0x{ro_sel_reg:02x}")

    # ro_sel should have moved from 0 (auto-tuner increments on alarm)
    assert ro_sel_first > 0, f"Expected auto-tuner to advance ro_sel from 0, got {ro_sel_first}"

    # Wait for more alarm cycles and check that ro_sel has advanced further
    await wait_clocks(dut, 200)

    ro_sel_reg2 = await spi_read_byte(dut, 0x12)
    ro_sel_second = ro_sel_reg2 & 0x07
    dut._log.info(f"After more alarms: ro_sel={ro_sel_second}  reg_0x12=0x{ro_sel_reg2:02x}")

    # In sim, every ~35 cycles produces an alarm, so after 200+ more cycles
    # we should see additional increments
    assert ro_sel_second != ro_sel_first, \
        f"Auto-tuner did not continue cycling: ro_sel stayed at {ro_sel_first}"
    dut._log.info("PASS – auto-tuner cycles ro_sel on repeated alarms")


@cocotb.test()
async def test_enable_disable(dut):
    """When en=0, frequency counter should stop accumulating."""
    if os.environ.get('GATES') == 'yes':
        dut._log.info("GLS – skipping"); return

    clock = Clock(dut.clk, 100, unit="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    # Start with en=1, select RO0, wait for a frequency measurement
    dut.ui_in.value = (1 << 3)
    await spi_write_byte(dut, 0x10, 0x00)
    await wait_clocks(dut, 2200)
    count_enabled = await spi_read_freq_count(dut)
    dut._log.info(f"RO0 count with en=1: {count_enabled}")
    assert count_enabled > 0, "Counter should be non-zero when enabled"

    # Disable: en=0
    dut.ui_in.value = 0
    # Wait for 2 more measurement windows
    await wait_clocks(dut, 2200)
    count_disabled = await spi_read_freq_count(dut)
    dut._log.info(f"RO0 count with en=0: {count_disabled}")

    # The RO is gated by 'en'. In sim, sim_ro only toggles when en=1.
    # After disabling, no new edges -> count in new windows should be 0.
    assert count_disabled == 0, \
        f"Expected freq count = 0 when disabled, got {count_disabled}"
    dut._log.info("PASS – RO frequency counter stops when en=0")


@cocotb.test()
async def test_uart_idle_state(dut):
    """UART TX line (uio_out[1]) should idle high after reset."""
    if os.environ.get('GATES') == 'yes':
        dut._log.info("GLS – skipping"); return

    clock = Clock(dut.clk, 100, unit="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)
    dut.ui_in.value = (1 << 3)

    # Wait a few clocks for any startup transient
    await wait_clocks(dut, 20)

    # uio_out bus may contain high-Z bits (spi_miso when CS is high),
    # so read the internal uart_tx_out signal directly.
    try:
        uart_tx_val = dut.uart_tx_out.value
        if uart_tx_val.is_resolvable:
            uart_tx = int(uart_tx_val)
            dut._log.info(f"UART TX idle state: {uart_tx}")
            assert uart_tx == 1, f"UART TX should idle high, got {uart_tx}"
        else:
            assert False, f"uart_tx_out not resolvable: {uart_tx_val}"
    except AttributeError:
        # Fallback: try reading uio_out bit 1 individually
        uio_val = dut.uio_out.value
        binval = uio_val.binstr
        # binstr is MSB first: bit 7 is index 0, bit 1 is index 6
        uart_bit = binval[6] if len(binval) == 8 else 'x'
        dut._log.info(f"uio_out binstr: {binval}, UART TX (bit 1): {uart_bit}")
        assert uart_bit == '1', f"UART TX should idle high, got '{uart_bit}'"

    dut._log.info("PASS – UART TX idles high")


@cocotb.test()
async def test_byte_valid_and_random_output(dut):
    """In sim, the whitener discards all identical pairs -> byte_valid should
    never fire and the random byte register should remain at its reset value."""
    if os.environ.get('GATES') == 'yes':
        dut._log.info("GLS – skipping"); return

    clock = Clock(dut.clk, 100, unit="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)
    dut.ui_in.value = (1 << 3)

    # Monitor byte_valid (uio_out[0]) for 500 cycles
    byte_valid_seen = False
    for _ in range(500):
        await RisingEdge(dut.clk)
        uio_val = dut.uio_out.value
        if uio_val.is_resolvable and (int(uio_val) & 1) == 1:
            byte_valid_seen = True
            break

    dut._log.info(f"byte_valid observed in 500 cycles: {byte_valid_seen}")

    # In sim, all ROs are in sync -> XOR=0 -> whitener discards everything
    assert not byte_valid_seen, \
        "byte_valid should not fire in sim (whitener discards identical-bit pairs)"

    # Random byte register should be 0x00 (never assembled a byte)
    rand_byte = await spi_read_byte(dut, 0x11)
    dut._log.info(f"Random byte register (0x11): 0x{rand_byte:02x}")
    assert rand_byte == 0x00, f"Expected 0x00 (no assembled bytes), got 0x{rand_byte:02x}"
    dut._log.info("PASS – whitener correctly discards constant bit stream, no bytes produced")


@cocotb.test()
async def test_output_enable_mask(dut):
    """Verify uio_oe is the expected constant (bits 0, 1, 6 are outputs)."""
    if os.environ.get('GATES') == 'yes':
        dut._log.info("GLS – skipping"); return

    clock = Clock(dut.clk, 100, unit="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)
    dut.ui_in.value = (1 << 3)
    await wait_clocks(dut, 5)

    oe = dut.uio_oe.value
    if oe.is_resolvable:
        oe_int = int(oe)
        dut._log.info(f"uio_oe = 0b{oe_int:08b} (0x{oe_int:02x})")
        assert oe_int == 0x43, f"Expected uio_oe=0x43 (bits 0,1,6), got 0x{oe_int:02x}"
    else:
        assert False, f"uio_oe not resolvable: {oe}"

    dut._log.info("PASS – output enable mask correct")


@cocotb.test()
async def test_ctrl_reg_bypass_vn(dut):
    """With bypass_vn=1, raw sampled bits feed the shift register directly,
    so byte_valid should fire (every 8 clocks of en)."""
    if os.environ.get('GATES') == 'yes':
        dut._log.info("GLS – skipping"); return

    clock = Clock(dut.clk, 100, unit="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)
    dut.ui_in.value = (1 << 3)  # en=1

    # Set bypass_vn=1 in ctrl_reg
    await spi_write_byte(dut, 0x13, 0x01)

    # Wait for shift register to fill (8 bits) + some margin
    await wait_clocks(dut, 20)

    # Monitor byte_valid (uio_out[0]) - should fire within a few cycles
    byte_valid_seen = False
    for _ in range(50):
        await RisingEdge(dut.clk)
        uio_val = dut.uio_out.value
        if uio_val.is_resolvable and (int(uio_val) & 1) == 1:
            byte_valid_seen = True
            break

    dut._log.info(f"byte_valid with bypass_vn=1: {byte_valid_seen}")
    assert byte_valid_seen, "byte_valid should fire when bypass_vn=1 (raw bits feed shift register)"

    # Read the random byte - should be non-0x00 (it's all 0-bits from XOR, so 0x00)
    # Actually in sim, sampled_bit is constant 0 (XOR of identical ROs), so out_reg = 0x00
    rand_byte = await spi_read_byte(dut, 0x11)
    dut._log.info(f"Random byte with bypass_vn=1: 0x{rand_byte:02x}")
    dut._log.info("PASS – bypass_vn enables raw bit path, byte_valid fires")
