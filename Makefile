
.PHONY: clean verilator verilator_debug simv xsim questa wave lint help

VERILATOR ?= $(shell command -v verilator_bin 2>/dev/null || command -v verilator 2>/dev/null)
VERILATOR_ROOT := $(shell if [ -n "$(VERILATOR)" ]; then realpath "$$(dirname "$(VERILATOR)")/../share/verilator"; fi)
VERILATOR_INC := $(VERILATOR_ROOT)/include

VERILOG_RTL = src/ucie_rdi_to_pcie_pipe_bridge.sv test/ucie_rdi_to_pcie_pipe_bridge_assertions.sv test/tb_ucie_rdi_to_pcie_pipe_bridge.sv
VERILOG_FILES = $(VERILOG_RTL)
TOP_MODULE = tb_ucie_rdi_to_pcie_pipe_bridge
TOP_SIMV = sim_top
VERILOG_SIMV = test/sim_top.sv $(VERILOG_RTL)
VERILATOR_DIR = obj_dir

# Default target
all: verilator

# Verilator Simulation
verilator:
	@echo "========== Compiling with Verilator =========="
	@if [ -z "$(VERILATOR)" ] || [ -z "$(VERILATOR_ROOT)" ]; then echo "ERROR: install verilator or ensure verilator_bin is on PATH"; exit 1; fi
	$(VERILATOR) --trace -cc $(VERILOG_FILES) --top-module $(TOP_MODULE) -Wno-INFINITELOOP -Wno-STMTDLY -Wno-WIDTH
	cd $(VERILATOR_DIR) && make -f V$(TOP_MODULE).mk
	cd $(VERILATOR_DIR) && g++ -o $(TOP_MODULE) ../sim_main.cpp V$(TOP_MODULE)__ALL.a \
		-I. -I$(VERILATOR_INC) -I$(VERILATOR_INC)/vltstd \
		$(VERILATOR_INC)/verilated.cpp $(VERILATOR_INC)/verilated_vcd_c.cpp \
		$(VERILATOR_INC)/verilated_threads.cpp -pthread -lm
	@echo "Running Verilator simulation..."
	./$(VERILATOR_DIR)/$(TOP_MODULE)

# Same as verilator with debug-friendly C++ flags
verilator_debug:
	@echo "========== Compiling with Verilator (debug) =========="
	@if [ -z "$(VERILATOR)" ] || [ -z "$(VERILATOR_ROOT)" ]; then echo "ERROR: install verilator or ensure verilator_bin is on PATH"; exit 1; fi
	$(VERILATOR) --trace -cc $(VERILOG_FILES) --top-module $(TOP_MODULE) -Wno-INFINITELOOP -Wno-STMTDLY -Wno-WIDTH
	cd $(VERILATOR_DIR) && make -f V$(TOP_MODULE).mk
	cd $(VERILATOR_DIR) && g++ -g -O0 -o $(TOP_MODULE) ../sim_main.cpp V$(TOP_MODULE)__ALL.a \
		-I. -I$(VERILATOR_INC) -I$(VERILATOR_INC)/vltstd \
		$(VERILATOR_INC)/verilated.cpp $(VERILATOR_INC)/verilated_vcd_c.cpp \
		$(VERILATOR_INC)/verilated_threads.cpp -pthread -lm
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
	$(VERILATOR) --lint-only -Wall src/ucie_rdi_to_pcie_pipe_bridge.sv 2>&1 | head -80; true

# Clean up simulation artifacts
clean:
	@echo "========== Cleaning simulation files =========="
	rm -rf $(VERILATOR_DIR)
	rm -rf csrc simv simv.daidir DVEdir coverage.db *.vcd *.wdb *.fsdb
	rm -rf xsim.dir transcript xsim_*.log
	rm -rf work *.ucdb
	@echo "Clean complete"

help:
	@echo "Available targets:"
	@echo "  make verilator          - Compile and simulate with Verilator (default)"
	@echo "  make verilator_debug    - Verilator with g++ -g -O0"
	@echo "  make wave               - Open GTKWave on obj_dir/dump.vcd"
	@echo "  make lint               - Verilator lint on RTL (best-effort)"
	@echo "  make simv               - VCS"
	@echo "  make questa             - QuestaSim"
	@echo "  make xsim               - Xcelium"
	@echo "  make vivado             - Vivado hints"
	@echo "  make clean              - Remove build artifacts"
	@echo "  make help               - This message"

.DEFAULT_GOAL := all
