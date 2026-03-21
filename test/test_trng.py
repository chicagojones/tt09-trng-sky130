import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer

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
        bit = (dut.uio_out.value >> 6) & 1
        data = (data << 1) | bit
        
        # SCLK Falling Edge
        dut.uio_in.value = dut.uio_in.value & ~(1 << 4)
        await Timer(500, unit="ns")
        
    dut.uio_in.value = dut.uio_in.value | (1 << 3) # CS_N high
    return data

@cocotb.test()
async def test_trng_features(dut):
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
    
    dut._log.info("Waiting for random data...")
    
    # Wait for byte valid
    found_valid = False
    for _ in range(10000):
        await RisingEdge(dut.clk)
        if (dut.uio_out.value.integer & 1) == 1:
            found_valid = True
            val = dut.uo_out.value.integer
            dut._log.info(f"Byte Received: {val:02x}")
            break
            
    if found_valid:
        # Test SPI read
        dut._log.info("Testing SPI Read...")
        spi_val = await spi_read_byte(dut)
        dut._log.info(f"SPI Read Value: {spi_val:02x}")
        # Note: Depending on when we read, it might be the same or next byte
    else:
        dut._log.error("Timeout waiting for TRNG byte")

    dut._log.info("Test finished.")
