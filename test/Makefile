# Makefile
# See https://docs.cocotb.org/en/stable/quickstart.html for more info

# defaults
SIM ?= icarus
TOPLEVEL_LANG ?= verilog
SRC_DIR = $(PWD)/../src
PROJECT_SOURCES = tt_um_trng_ro.v nist_health_monitor.v auto_tuner.v von_neumann.v uart_tx.v spi_follower.v

ifneq ($(GATES),yes)

# RTL simulation
COMPILE_ARGS += -DCOCOTB_SIM=1 -DSIM=1
VERILOG_SOURCES += $(addprefix $(SRC_DIR)/,$(PROJECT_SOURCES))

else

# Gate level simulation
# Use the default pipeline logic, but ensure SIM is defined
COMPILE_ARGS    += -DCOCOTB_SIM=1 -DSIM=1
VERILOG_SOURCES += $(PWD)/gate_level_netlist.v

endif

# TOPLEVEL is the name of the toplevel module in your Verilog or VHDL file
TOPLEVEL = tt_um_chicagojones_trng_ro

# MODULE is the basename of the Python test file
MODULE = test_trng

# include cocotb's make rules to take care of the simulator setup
include $(shell cocotb-config --makefiles)/Makefile.sim
