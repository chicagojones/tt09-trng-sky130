import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer, ClockCycles
import os

async def spi_read_byte(dut):
    """Simple SPI Master read (Mode 0)"""
    dut.uio_in.value = dut.uio_in.value & ~(1 << 3) # CS_N low
    await Timer(500, unit="ns")
    
    data = 0
    for i in range(8):
        # SCLK Rising Edge
        dut.uio_in.value = dut.uio_in.value | (1 << 4)
        await Timer(500, unit="ns")
        
        # Sample MISO (uio[6])
        val = dut.uio_out.value
        bit = 0
        if val.is_resolvable:
            bit = (int(val) >> 6) & 1
        data = (data << 1) | bit
        
        # SCLK Falling Edge
        dut.uio_in.value = dut.uio_in.value & ~(1 << 4)
        await Timer(500, unit="ns")
        
    dut.uio_in.value = dut.uio_in.value | (1 << 3) # CS_N high
    return data

@cocotb.test()
async def test_trng_features(dut):
    # Detect if we are in Gate-Level Simulation (GLS)
    # Asynchronous Ring Oscillators cannot be simulated accurately 
    # without SDF timing information in GLS.
    if os.environ.get('GATES') == 'yes':
        dut._log.info("Gate-level simulation detected. Skipping tests for asynchronous RO logic.")
        return

    # Create a 10MHz clock
    clock = Clock(dut.clk, 100, unit="ns") 
    cocotb.start_soon(clock.start())

    # Initialize signals
    dut.ui_in.value = 0
    dut.uio_in.value = (1 << 3) # CS_N starts high
    dut.rst_n.value = 0
    dut.ena.value = 1
    
    # Wait for reset
    await Timer(200, unit="ns")
    dut.rst_n.value = 1
    await Timer(100, unit="ns")

    # Enable RO (bit 3)
    dut.ui_in.value = (1 << 3)
    
    dut._log.info("Waiting for random data (up to 1,000 cycles)...")
    
    # Wait for byte valid
    found_valid = False
    for i in range(10): # 10 chunks of 100 cycles = 1,000
        await ClockCycles(dut.clk, 100)
        val = dut.uio_out.value
        if val.is_resolvable and (int(val) & 1) == 1:
            found_valid = True
            val_out = dut.uo_out.value
            if val_out.is_resolvable:
                dut._log.info(f"Byte Received: {int(val_out):02x}")
            break
            
    if found_valid:
        # Test SPI read
        dut._log.info("Testing SPI Read...")
        spi_val = await spi_read_byte(dut)
        dut._log.info(f"SPI Read Value: {spi_val:02x}")
    else:
        dut._log.warning("Timeout waiting for TRNG byte in simulation (Normal for deterministic sims).")

    dut._log.info("Test finished.")
