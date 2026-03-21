# Makefile
# See https://docs.cocotb.org/en/stable/quickstart.html for more info

# defaults
SIM ?= icarus
TOPLEVEL_LANG ?= verilog
SRC_DIR = $(PWD)/../src
PROJECT_SOURCES = tt_um_trng_ro.v nist_health_monitor.v auto_tuner.v von_neumann.v uart_tx.v spi_follower.v ro_freq_counter.v

ifneq ($(GATES),yes)

# RTL simulation
COMPILE_ARGS += -DCOCOTB_SIM=1 -DSIM=1
VERILOG_SOURCES += $(addprefix $(SRC_DIR)/,$(PROJECT_SOURCES))

else

# Gate level simulation
# 1. Use USE_POWER_PINS (the official Sky130 macro for this shuttle)
# 2. UNIT_DELAY prevents zero-delay loop stalls
# 3. Include PDK models
COMPILE_ARGS    += -DCOCOTB_SIM=1 -DGL_TEST -DFUNCTIONAL -DUSE_POWER_PINS -DSIM -DUNIT_DELAY=\#1 -DUNIT_DELAY_RISE=1 -DUNIT_DELAY_FALL=1
VERILOG_SOURCES += $(PDK_ROOT)/sky130A/libs.ref/sky130_fd_sc_hd/verilog/primitives.v
VERILOG_SOURCES += $(PDK_ROOT)/sky130A/libs.ref/sky130_fd_sc_hd/verilog/sky130_fd_sc_hd.v
VERILOG_SOURCES += $(PWD)/gate_level_netlist.v

endif

# TOPLEVEL is the name of the toplevel module in your Verilog or VHDL file
TOPLEVEL = tt_um_chicagojones_tt09_trng_sky130

# MODULE is the basename of the Python test file
MODULE = test_trng

# include cocotb's make rules to take care of the simulator setup
include $(shell cocotb-config --makefiles)/Makefile.sim
