# Makefile
# See https://docs.cocotb.org/en/stable/quickstart.html for more info

# defaults
SIM ?= icarus
TOPLEVEL_LANG ?= verilog
SRC_DIR = $(PWD)/../src
PROJECT_SOURCES = tt_um_trng_ro.v nist_health_monitor.v auto_tuner.v von_neumann.v uart_tx.v spi_follower.v ro_freq_counter.v cond_tent_map.v cond_coupled_tent.v cond_logistic.v cond_bernoulli.v cond_lorenz.v cond_lfsr.v

ifneq ($(GATES),yes)

# RTL simulation
COMPILE_ARGS += -DCOCOTB_SIM=1 -DSIM=1
VERILOG_SOURCES += $(addprefix $(SRC_DIR)/,$(PROJECT_SOURCES))

else

# Gate level simulation
COMPILE_ARGS    += -DCOCOTB_SIM=1 -DSIM=1 -DUSE_POWER_PINS -DUNIT_DELAY=\#1 -DUNIT_DELAY_RISE=1 -DUNIT_DELAY_FALL=1
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
