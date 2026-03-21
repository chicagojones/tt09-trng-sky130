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
# The Tiny Tapeout pipeline handles library linking and delays automatically.
# We only include the netlist and define SIM so our testbench bypass works.
COMPILE_ARGS    += -DCOCOTB_SIM=1 -DSIM=1
VERILOG_SOURCES += $(PWD)/gate_level_netlist.v

endif

# TOPLEVEL is the name of the toplevel module in your Verilog or VHDL file
TOPLEVEL = tt_um_chicagojones_tt09_trng_sky130

# MODULE is the basename of the Python test file
MODULE = test_trng

# include cocotb's make rules to take care of the simulator setup
include $(shell cocotb-config --makefiles)/Makefile.sim
