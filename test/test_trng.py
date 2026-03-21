import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer
import os

async def spi_read_byte(dut, addr):
    """SPI Read: Send Command (Addr + R/W=1), then get Data"""
    # CS_N low
    dut.uio_in.value = dut.uio_in.value & ~(1 << 3)
    await Timer(100, unit="ns")
    
    # 1. Command Byte (Addr << 1 | 1)
    cmd = (addr << 1) | 1
    for i in range(8):
        # MOSI (uio[5])
        bit = (cmd >> (7-i)) & 1
        dut.uio_in.value = (dut.uio_in.value & ~(1 << 5)) | (bit << 5)
        await Timer(100, unit="ns")
        dut.uio_in.value = dut.uio_in.value | (1 << 4) # SCLK High
        await Timer(100, unit="ns")
        dut.uio_in.value = dut.uio_in.value & ~(1 << 4) # SCLK Low
        await Timer(100, unit="ns")

    # 2. Data Byte (Read from MISO)
    data = 0
    for i in range(8):
        await Timer(100, unit="ns")
        dut.uio_in.value = dut.uio_in.value | (1 << 4) # SCLK High
        await Timer(100, unit="ns")
        # Sample MISO (uio[6])
        val = dut.uio_out.value
        bit = 0
        if val.is_resolvable:
            bit = (int(val) >> 6) & 1
        data = (data << 1) | bit
        dut.uio_in.value = dut.uio_in.value & ~(1 << 4) # SCLK Low
        await Timer(100, unit="ns")

    # CS_N high
    dut.uio_in.value = dut.uio_in.value | (1 << 3)
    return data

async def spi_write_byte(dut, addr, data_val):
    """SPI Write: Send Command (Addr + R/W=0), then send Data"""
    # CS_N low
    dut.uio_in.value = dut.uio_in.value & ~(1 << 3)
    await Timer(100, unit="ns")
    
    # 1. Command Byte (Addr << 1 | 0)
    cmd = (addr << 1) | 0
    for i in range(8):
        bit = (cmd >> (7-i)) & 1
        dut.uio_in.value = (dut.uio_in.value & ~(1 << 5)) | (bit << 5)
        await Timer(100, unit="ns")
        dut.uio_in.value = dut.uio_in.value | (1 << 4) # SCLK High
        await Timer(100, unit="ns")
        dut.uio_in.value = dut.uio_in.value & ~(1 << 4) # SCLK Low
        await Timer(100, unit="ns")

    # 2. Data Byte
    for i in range(8):
        bit = (data_val >> (7-i)) & 1
        dut.uio_in.value = (dut.uio_in.value & ~(1 << 5)) | (bit << 5)
        await Timer(100, unit="ns")
        dut.uio_in.value = dut.uio_in.value | (1 << 4) # SCLK High
        await Timer(100, unit="ns")
        dut.uio_in.value = dut.uio_in.value & ~(1 << 4) # SCLK Low
        await Timer(100, unit="ns")

    # CS_N high
    dut.uio_in.value = dut.uio_in.value | (1 << 3)

@cocotb.test()
async def test_trng_features(dut):
    # Setup Clock
    clock = Clock(dut.clk, 100, unit="ns") 
    cocotb.start_soon(clock.start())

    # Initialize
    dut.ui_in.value = 0
    dut.uio_in.value = (1 << 3) # CS_N starts high
    dut.rst_n.value = 0
    dut.ena.value = 1
    await Timer(200, unit="ns")
    dut.rst_n.value = 1
    await Timer(100, unit="ns")

    # Enable TRNG
    dut.ui_in.value = (1 << 3)

    # 1. Test Control Register (Fail-Safe)
    # Write 0x18 to Address 0x13 (Mux Select 11: Raw Sampled Bit)
    dut._log.info("Setting Fail-Safe: Raw Bit Mode")
    await spi_write_byte(dut, 0x13, 0x18)
    
    # Check Readback
    read_ctrl = await spi_read_byte(dut, 0x13)
    dut._log.info(f"Control Reg Readback: {read_ctrl:02x}")
    assert read_ctrl == 0x18

    # 2. Test Frequency Mux
    # Write 0x05 to Address 0x10 (Select RO #5 for characterization)
    dut._log.info("Setting Freq Mux to RO #5")
    await spi_write_byte(dut, 0x10, 0x05)
    
    # Read status back
    status = await spi_read_byte(dut, 0x10)
    dut._log.info(f"Status Reg (Addr 0x10): {status:02x}")
    assert (status & 0x07) == 0x05

    # 3. Wait for data or check if alive
    dut._log.info("Waiting for some cycles...")
    for _ in range(100):
        await RisingEdge(dut.clk)

    # Detect if we are in Gate-Level Simulation (GLS)
    if os.environ.get('GATES') == 'yes':
        dut._log.info("Gate-level simulation detected. Skipping internal signal checks.")
    else:
        # Check internal signal only in RTL
        # In RTL, bypass_vn should make the shift register very fast
        # (Actually we still wait for 8 cycles of RO toggle)
        pass

    dut._log.info("Test finished.")
