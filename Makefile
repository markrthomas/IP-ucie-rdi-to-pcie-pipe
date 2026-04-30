
.PHONY: clean verilator verilator_nl1 verilator_cov verilator_debug simv xsim questa wave lint regress regress_cov regress_nl1 help

VERILATOR ?= $(shell command -v verilator_bin 2>/dev/null || command -v verilator 2>/dev/null)
VERILATOR_ROOT := $(shell if [ -n "$(VERILATOR)" ]; then realpath "$$(dirname "$(VERILATOR)")/../share/verilator"; fi)
VERILATOR_INC := $(VERILATOR_ROOT)/include
VERILATOR_CPP_CORE = $(VERILATOR_INC)/verilated.cpp $(VERILATOR_INC)/verilated_vcd_c.cpp \
	$(VERILATOR_INC)/verilated_threads.cpp

VERILOG_RTL = ucie_rdi_to_pcie_pipe_bridge.sv ucie_rdi_to_pcie_pipe_bridge_assertions.sv tb_ucie_rdi_to_pcie_pipe_scoreboard.sv tb_ucie_rdi_to_pcie_pipe_bridge.sv
VERILOG_FILES = $(VERILOG_RTL)
TOP_MODULE = tb_ucie_rdi_to_pcie_pipe_bridge
TOP_SIMV = sim_top
VERILOG_SIMV = sim_top.sv $(VERILOG_RTL)
VERILATOR_DIR = obj_dir
COV_DIR = obj_dir_cov
NL1_TOP = tb_ucie_rdi_to_pcie_pipe_nl1
NL1_DIR = obj_dir_nl1
NL1_FILES = ucie_rdi_to_pcie_pipe_bridge.sv ucie_rdi_to_pcie_pipe_bridge_assertions.sv tb_ucie_rdi_to_pcie_pipe_nl1.sv

# Default target
all: verilator

# Release regression (lint + Verilator smoke); CI runs this target.
regress: lint verilator

# Lint + Verilator with coverage (writes obj_dir_cov/coverage.dat; optional coverage.info).
regress_cov: lint verilator_cov

# NUM_LANES=1 compile + minimal smoke (lint includes nl1 TB pass).
regress_nl1: lint verilator_nl1

# Verilator Simulation
verilator:
	@echo "========== Compiling with Verilator =========="
	@if [ -z "$(VERILATOR)" ] || [ -z "$(VERILATOR_ROOT)" ]; then echo "ERROR: install verilator or ensure verilator_bin is on PATH"; exit 1; fi
	$(VERILATOR) --trace -cc $(VERILOG_FILES) --top-module $(TOP_MODULE) -Wno-INFINITELOOP -Wno-STMTDLY -Wno-WIDTH
	cd $(VERILATOR_DIR) && make -f V$(TOP_MODULE).mk
	cd $(VERILATOR_DIR) && g++ -o $(TOP_MODULE) ../sim_main.cpp V$(TOP_MODULE)__ALL.a \
		-I. -I$(VERILATOR_INC) -I$(VERILATOR_INC)/vltstd \
		$(VERILATOR_CPP_CORE) -pthread -lm
	@echo "Running Verilator simulation..."
	./$(VERILATOR_DIR)/$(TOP_MODULE)

# NUM_LANES=1 parameter sanity (obj_dir_nl1/, sim_main_nl1.cpp).
verilator_nl1:
	@echo "========== Verilator NUM_LANES=1 smoke =========="
	@if [ -z "$(VERILATOR)" ] || [ -z "$(VERILATOR_ROOT)" ]; then echo "ERROR: install verilator or ensure verilator_bin is on PATH"; exit 1; fi
	rm -rf $(NL1_DIR)
	$(VERILATOR) --trace -cc $(NL1_FILES) --top-module $(NL1_TOP) \
		-Wno-INFINITELOOP -Wno-STMTDLY -Wno-WIDTH --Mdir $(NL1_DIR)
	cd $(NL1_DIR) && make -f V$(NL1_TOP).mk
	cd $(NL1_DIR) && g++ -o $(NL1_TOP) ../sim_main_nl1.cpp V$(NL1_TOP)__ALL.a \
		-I. -I$(VERILATOR_INC) -I$(VERILATOR_INC)/vltstd \
		$(VERILATOR_CPP_CORE) -pthread -lm
	@echo "Running Verilator NL1 simulation..."
	cd $(NL1_DIR) && ./$(NL1_TOP)

# Verilator with coverage: separate build dir so normal obj_dir stays unchanged.
verilator_cov:
	@echo "========== Verilator with coverage =========="
	@if [ -z "$(VERILATOR)" ] || [ -z "$(VERILATOR_ROOT)" ]; then echo "ERROR: install verilator or ensure verilator_bin is on PATH"; exit 1; fi
	rm -rf $(COV_DIR)
	$(VERILATOR) --coverage --trace -cc $(VERILOG_FILES) --top-module $(TOP_MODULE) \
		-Wno-INFINITELOOP -Wno-STMTDLY -Wno-WIDTH --Mdir $(COV_DIR)
	cd $(COV_DIR) && make -f V$(TOP_MODULE).mk
	cd $(COV_DIR) && g++ -DVM_COVERAGE=1 -o $(TOP_MODULE) ../sim_main.cpp V$(TOP_MODULE)__ALL.a \
		-I. -I$(VERILATOR_INC) -I$(VERILATOR_INC)/vltstd \
		$(VERILATOR_CPP_CORE) $(VERILATOR_INC)/verilated_cov.cpp -pthread -lm
	@echo "Running Verilator simulation (coverage)..."
	cd $(COV_DIR) && ./$(TOP_MODULE)
	@echo "Coverage raw data: $(COV_DIR)/coverage.dat"
	@if command -v verilator_coverage >/dev/null 2>&1; then \
		cd $(COV_DIR) && verilator_coverage --write-info ../coverage.info coverage.dat && \
		echo "Wrote coverage.info (Verilator: merge/report per manual)"; \
	else \
		echo "Tip: verilator_coverage --write-info coverage.info $(COV_DIR)/coverage.dat"; \
	fi

# Same as verilator with debug-friendly C++ flags
verilator_debug:
	@echo "========== Compiling with Verilator (debug) =========="
	@if [ -z "$(VERILATOR)" ] || [ -z "$(VERILATOR_ROOT)" ]; then echo "ERROR: install verilator or ensure verilator_bin is on PATH"; exit 1; fi
	$(VERILATOR) --trace -cc $(VERILOG_FILES) --top-module $(TOP_MODULE) -Wno-INFINITELOOP -Wno-STMTDLY -Wno-WIDTH
	cd $(VERILATOR_DIR) && make -f V$(TOP_MODULE).mk
	cd $(VERILATOR_DIR) && g++ -g -O0 -o $(TOP_MODULE) ../sim_main.cpp V$(TOP_MODULE)__ALL.a \
		-I. -I$(VERILATOR_INC) -I$(VERILATOR_INC)/vltstd \
		$(VERILATOR_CPP_CORE) -pthread -lm
	@echo "Running Verilator simulation..."
	./$(VERILATOR_DIR)/$(TOP_MODULE)

# View waveforms (GTKWave; VCD from sim_main.cpp)
wave:
	@echo "Opening GTKWave..."
	gtkwave $(VERILATOR_DIR)/dump.vcd &

# VCS Simulation (requires Synopsys VCS)
simv:
	@echo "========== Compiling with VCS =========="
	vcs -sverilog -debug_all -cm line+tgl -top $(TOP_SIMV) $(VERILOG_SIMV)
	@echo "Running VCS simulation..."
	./simv -gui &

# Mentor ModelSim/QuestaSim
questa:
	@echo "========== Compiling with QuestaSim =========="
	vlog -sv $(VERILOG_SIMV)
	vsim -c $(TOP_SIMV) -do "run -all; quit"

# Cadence Xcelium
xsim:
	@echo "========== Compiling with Cadence Xcelium =========="
	xmvlog -sv $(VERILOG_SIMV)
	xmsim $(TOP_SIMV)

# Vivado Simulation (Xilinx)
vivado:
	@echo "========== Setting up Vivado Simulation =========="
	@echo "Note: Add files manually to Vivado project"
	@echo "Source files: $(VERILOG_FILES)"

lint:
	@if [ -z "$(VERILATOR)" ]; then echo "ERROR: install verilator or ensure verilator_bin is on PATH"; exit 1; fi
	$(VERILATOR) --lint-only -Wall --top-module ucie_rdi_to_pcie_pipe_bridge ucie_rdi_to_pcie_pipe_bridge.sv
	$(VERILATOR) --lint-only -Wall --top-module ucie_rdi_to_pcie_pipe_bridge_assertions ucie_rdi_to_pcie_pipe_bridge_assertions.sv
	$(VERILATOR) --lint-only -Wall -Wno-SYNCASYNCNET --top-module $(TOP_MODULE) $(VERILOG_FILES)
	$(VERILATOR) --lint-only -Wall -Wno-SYNCASYNCNET --top-module $(NL1_TOP) $(NL1_FILES)

# Clean up simulation artifacts
clean:
	@echo "========== Cleaning simulation files =========="
	rm -rf $(VERILATOR_DIR) $(COV_DIR) $(NL1_DIR)
	rm -f coverage.info
	rm -rf csrc simv simv.daidir DVEdir coverage.db *.vcd *.wdb *.fsdb
	rm -rf xsim.dir transcript xsim_*.log
	rm -rf work *.ucdb
	@echo "Clean complete"

help:
	@echo "Available targets:"
	@echo "  make regress             - lint + Verilator smoke (release gate)"
	@echo "  make regress_cov         - lint + Verilator sim with coverage (+ coverage.info if tool present)"
	@echo "  make regress_nl1         - lint + NUM_LANES=1 Verilator smoke"
	@echo "  make verilator_nl1       - NUM_LANES=1 build/run only (after lint)"
	@echo "  make verilator          - Compile and simulate with Verilator (default)"
	@echo "  make verilator_debug    - Verilator with g++ -g -O0"
	@echo "  make wave               - Open GTKWave on obj_dir/dump.vcd"
	@echo "  make lint               - Verilator -Wall (RTL + assertions + TB/scoreboard)"
	@echo "  make simv               - VCS"
	@echo "  make questa             - QuestaSim"
	@echo "  make xsim               - Xcelium"
	@echo "  make vivado             - Vivado hints"
	@echo "  make clean              - Remove build artifacts"
	@echo "  make help               - This message"

.DEFAULT_GOAL := all
