
.PHONY: clean verilator simv xsim questa

# Variables
VERILOG_FILES = ucie_rdi_to_pcie_pipe_bridge.sv ucie_rdi_to_pcie_pipe_bridge_assertions.sv tb_ucie_rdi_to_pcie_pipe_bridge.sv
TOP_MODULE = tb_ucie_rdi_to_pcie_pipe_bridge
SIM_TIME = 10ms
VERILATOR_DIR = obj_dir

# Default target
all: verilator

# Verilator Simulation
verilator:
	@echo "========== Compiling with Verilator =========="
	verilator --trace -cc $(VERILOG_FILES) --top-module $(TOP_MODULE) -Wno-INFINITELOOP -Wno-STMTDLY -Wno-WIDTH
	cd obj_dir && make -f Vtb_ucie_rdi_to_pcie_pipe_bridge.mk
	cd obj_dir && g++ -o Vtb_ucie_rdi_to_pcie_pipe_bridge ../sim_main.cpp Vtb_ucie_rdi_to_pcie_pipe_bridge__ALL.a -I. -I/usr/share/verilator/include -I/usr/share/verilator/include/vltstd /usr/share/verilator/include/verilated.cpp /usr/share/verilator/include/verilated_vcd_c.cpp -lm
	@echo "Running Verilator simulation..."
	./obj_dir/Vtb_ucie_rdi_to_pcie_pipe_bridge

# Verilator with detailed tracing
verilator_debug:
	@echo "========== Compiling with Verilator (Debug Mode) =========="
	verilator --trace --trace-fst -cc $(VERILOG_FILES) --top-module $(TOP_MODULE)
	cd $(VERILATOR_DIR) && make -f V$(TOP_MODULE).mk
	./$(VERILATOR_DIR)/V$(TOP_MODULE)

# View Waveforms (requires GTKWave)
wave:
	@echo "Opening GTKWave..."
	gtkwave $(VERILATOR_DIR)/dump.vcd &

# VCS Simulation (requires Synopsys VCS)
simv:
	@echo "========== Compiling with VCS =========="
	vcs -sverilog -debug_all -cm line+tgl $(VERILOG_FILES)
	@echo "Running VCS simulation..."
	./simv -gui &

# Mentor ModelSim/QuestaSim
questa:
	@echo "========== Compiling with QuestaSim =========="
	vlog -sv $(VERILOG_FILES)
	vsim -c $(TOP_MODULE) -do "run -all; quit"

# Cadence Xcelium
xsim:
	@echo "========== Compiling with Cadence Xcelium =========="
	xmvlog -sv $(VERILOG_FILES)
	xmsim $(TOP_MODULE)

# Vivado Simulation (Xilinx)
vivado:
	@echo "========== Setting up Vivado Simulation =========="
	@echo "Note: Add files manually to Vivado project"
	@echo "Source files: $(VERILOG_FILES)"

# Clean up simulation artifacts
clean:
	@echo "========== Cleaning simulation files =========="
	rm -rf $(VERILATOR_DIR)
	rm -rf csrc simv simv.daidir DVEdir coverage.db *.vcd *.wdb *.fsdb
	rm -rf xsim.dir transcript xsim_*.log
	rm -rf work *.ucdb
	@echo "Clean complete"

# Help target
help:
	@echo "Available targets:"
	@echo "  make verilator          - Compile and simulate with Verilator (default)"
	@echo "  make verilator_debug    - Compile with detailed tracing"
	@echo "  make wave               - Open GTKWave viewer"
	@echo "  make simv               - Compile and simulate with VCS"
	@echo "  make questa             - Compile and simulate with QuestaSim"
	@echo "  make xsim               - Compile and simulate with Xcelium"
	@echo "  make vivado             - Prepare for Vivado simulation"
	@echo "  make clean              - Remove all simulation artifacts"
	@echo "  make help               - Display this help message"

.DEFAULT_GOAL := all


