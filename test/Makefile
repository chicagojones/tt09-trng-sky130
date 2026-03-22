# Makefile
# Unified testing for tt09-trng-sky130

SIM ?= icarus
TOPLEVEL_LANG ?= verilog
SRC_DIR = $(PWD)/../src

# ---------------------------------------------------------------------------
# UNIT TEST MODE: make UNIT=1 DUT_NAME=cond_tent_map WIDTH=16
# ---------------------------------------------------------------------------
ifeq ($(UNIT),1)
    DUT_NAME ?= cond_tent_map
    WIDTH    ?= 8
    
    TOPLEVEL = $(DUT_NAME)
    MODULE   = unit_test_conditioners
    
    VERILOG_SOURCES = $(SRC_DIR)/$(DUT_NAME).v
    COMPILE_ARGS += -DCOCOTB_SIM=1 -DSIM=1 -P$(DUT_NAME).WIDTH=$(WIDTH)
    
# ---------------------------------------------------------------------------
# FULL CHIP MODE (Standard)
# ---------------------------------------------------------------------------
else
    PROJECT_SOURCES = tt_um_trng_ro.v nist_health_monitor.v auto_tuner.v von_neumann.v uart_tx.v uart_rx.v spi_follower.v ro_freq_counter.v \
                      cond_tent_map.v cond_coupled_tent.v cond_logistic.v cond_bernoulli.v cond_lorenz.v cond_lfsr.v

    TOPLEVEL = tt_um_chicagojones_sky26a_trng
    MODULE   = test_trng

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
endif

# include cocotb's make rules
include $(shell cocotb-config --makefiles)/Makefile.sim
