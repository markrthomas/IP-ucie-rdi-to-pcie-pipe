
.PHONY: all check ci clean coverage coverage_summary docs_check docs_pdf formal help lint nl1 quick regress regress_all regress_cov regress_nl1 repo_status sim simv smoke test uvm uvm_compile uvm_pdf uvm_run verilator verilator_cov verilator_debug verilator_nl1 vivado wave xsim questa

VERILATOR ?= $(shell command -v verilator_bin 2>/dev/null || command -v verilator 2>/dev/null)
VERILATOR_ROOT := $(shell if [ -n "$(VERILATOR)" ]; then realpath "$$(dirname "$(VERILATOR)")/../share/verilator"; fi)
VERILATOR_INC := $(VERILATOR_ROOT)/include
VERILATOR_CPP_CORE = $(VERILATOR_INC)/verilated.cpp $(VERILATOR_INC)/verilated_vcd_c.cpp \
	$(VERILATOR_INC)/verilated_threads.cpp

VERILOG_RTL = src/ucie_rdi_fifo_cdc.sv src/ucie_rdi_to_pcie_pipe_bridge.sv test/ucie_rdi_to_pcie_pipe_bridge_assertions.sv test/tb_ucie_rdi_to_pcie_pipe_scoreboard.sv test/tb_ucie_rdi_to_pcie_pipe_bridge.sv
VERILOG_FILES = $(VERILOG_RTL)
TOP_MODULE = tb_ucie_rdi_to_pcie_pipe_bridge
TOP_SIMV = sim_top
VERILOG_SIMV = test/sim_top.sv $(VERILOG_RTL)
VERILATOR_DIR = obj_dir
COV_DIR = obj_dir_cov
NL1_TOP = tb_ucie_rdi_to_pcie_pipe_nl1
NL1_DIR = obj_dir_nl1
NL1_FILES = src/ucie_rdi_fifo_cdc.sv src/ucie_rdi_to_pcie_pipe_bridge.sv test/ucie_rdi_to_pcie_pipe_bridge_assertions.sv test/tb_ucie_rdi_to_pcie_pipe_nl1.sv
UVM_MAKE = $(MAKE) -C test/uvm -f Makefile.vcs

# Default target
all: verilator

# Repo workflow aliases
quick: lint

check: regress

smoke: verilator

test: regress

nl1: regress_nl1

# Standard DV gate aliases (consistent with other RTL repos).
# coverage: alias for regress_cov (Verilator line coverage).
coverage: regress_cov

# formal: SymbiYosys formal proofs in verification/formal/.
#         Checks wr_ready/wr_full polarity and output stability (rd_valid,
#         rd_data, rd_error held when rd_ready is low) for ucie_rdi_fifo_cdc.
#         Uses a plain-Verilog model (struct literals / 'return' unsupported by Yosys).
formal:
	@if command -v sby >/dev/null 2>&1; then \
		$(MAKE) -C $(CURDIR)/verification/formal; \
	else \
		echo "[FORMAL] sby not found; install SymbiYosys (OSS CAD Suite) to run formal"; \
		echo "         Properties are in verification/formal/fifo_cdc_props.sv"; \
		exit 0; \
	fi

# Full local confidence run. This is intentionally heavier than CI's first gate.
ci: regress regress_cov regress_nl1 coverage_summary docs_check

regress_all: ci

# Release regression (lint + Verilator smoke); CI runs this target.
regress: lint verilator

# Standard DV alias (DV_STANDARDS.md): sim = Verilator OSS sim.
sim: verilator

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

coverage_summary:
	@if [ ! -f coverage.info ]; then \
		echo "coverage.info not found; run 'make regress_cov' first"; \
		exit 1; \
	fi
	@awk 'BEGIN{lines=0;hit=0} /^DA:/ {split($$0,a,":"); split(a[2],b,","); lines++; if (b[2] > 0) hit++} END{printf "Line coverage: %d/%d = %.2f%%\n", hit, lines, (lines?100*hit/lines:0)}' coverage.info
	@awk 'function flush(){if(file != ""){printf "  %-55s %4d/%-4d %6.2f%%\n", file, hit, lines, (lines?100*hit/lines:0)}} /^SF:/ {flush(); file=substr($$0,4); lines=0; hit=0} /^DA:/ {split($$0,a,":"); split(a[2],b,","); lines++; if (b[2] > 0) hit++} END{flush()}' coverage.info

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
	$(VERILATOR) --lint-only -Wall -Isrc --top-module ucie_rdi_to_pcie_pipe_bridge src/ucie_rdi_fifo_cdc.sv src/ucie_rdi_to_pcie_pipe_bridge.sv
	$(VERILATOR) --lint-only -Wall -Isrc --top-module ucie_rdi_to_pcie_pipe_bridge_assertions test/ucie_rdi_to_pcie_pipe_bridge_assertions.sv
	$(VERILATOR) --lint-only -Wall -Isrc -Wno-SYNCASYNCNET --top-module $(TOP_MODULE) $(VERILOG_FILES)
	$(VERILATOR) --lint-only -Wall -Isrc -Wno-SYNCASYNCNET --top-module $(NL1_TOP) $(NL1_FILES)

uvm_compile:
	$(UVM_MAKE) compile

uvm_run:
	$(UVM_MAKE) run

uvm: uvm_compile uvm_run

uvm_pdf docs_pdf:
	$(UVM_MAKE) pdf

docs_check:
	@echo "========== Checking documentation links and stale claims =========="
	@test -f README.md
	@test -f docs/architecture.md
	@test -f docs/interface_spec.md
	@test -f docs/verification_plan.md
	@test -f docs/uvm_verification.md
	@test -f test/uvm/README.md
	@! grep -R "| \*\*Line Coverage\*\* | 100%" README.md docs test/uvm/README.md >/dev/null
	@! grep -R "mirrors the coverage of the original SystemVerilog testbench" README.md docs test/uvm/README.md >/dev/null
	@echo "Documentation check passed"

repo_status:
	@git status --short

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
	@echo "  make quick              - lint only"
	@echo "  make check              - alias for regress"
	@echo "  make test               - alias for regress"
	@echo "  make ci                 - regress + coverage + NL1 + docs check"
	@echo "  make regress             - lint + Verilator smoke (release gate)"
	@echo "  make regress_cov         - lint + Verilator sim with coverage (+ coverage.info if tool present)"
	@echo "  make regress_nl1         - lint + NUM_LANES=1 Verilator smoke"
	@echo "  make regress_all         - alias for ci"
	@echo "  make coverage_summary    - summarize coverage.info"
	@echo "  make docs_check          - check required docs and stale claims"
	@echo "  make uvm                - VCS/UVM compile + run via test/uvm/Makefile.vcs"
	@echo "  make uvm_compile        - VCS/UVM compile only"
	@echo "  make uvm_run            - VCS/UVM run only"
	@echo "  make uvm_pdf            - build UVM README PDF via pandoc"
	@echo "  make repo_status        - git status --short"
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
