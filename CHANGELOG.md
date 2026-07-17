# Changelog

All notable changes to this project are documented here. Version tags follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **UVM RX-direction functional coverage**: `ucie_rdi_pcie_coverage` now collects the reverse (PIPE -> RDI) path through two new covergroups — `cg_rx_pipe` (PIPE RX stimulus entering the DUT) and `cg_rx_rdi` (RDI RX beats leaving the DUT) — wired from the existing RX monitors via new analysis imports. The report now prints `RX_PIPE`/`RX_RDI` percentages alongside the TX numbers (UVM closure plan item 5, RX direction). FIFO-occupancy, width-conversion, and CRC-enable coverpoints remain open.

### Changed

- **UVM lane/data geometry centralized**: Added `NUM_LANES`, `RDI_DATA_WIDTH`, `PIPE_DATA_WIDTH`, and derived `RDI_BUS_WIDTH`/`PIPE_BUS_WIDTH` parameters to `ucie_rdi_pcie_pkg` as the single source of truth. Transaction field widths, scoreboard per-lane loops and bit slices, and coverage sample ports now derive from these parameters, and `uvm_test_top` passes the same values into the interfaces, DUT, and assertion binder — removing hard-coded `4`/`16`/`32` magic numbers so the UVM environment cannot silently diverge from the RTL parameters (UVM closure plan item 1). Values are unchanged at the default 4-lane configuration; `seq_lib` stimulus vectors and covergroup bins remain 4-lane specific.

## [1.0.5] — 2026-05-02

### Fixed

- **FIFO logic**: Fixed aliasing and Gray code wrap-around bugs by increasing pointer width to $n+1$ for $2^n$ depth; prevents overwriting the FIFO head during deep pushes.
- **PIPE Stability**: Resolved `$warning` regarding data changes while stalled by ensuring strict "hold until handshake" behavior in the PIPE output register.
- **CDC Assertions**: Refined stability monitors to ignore initial data settlement cycles, avoiding false positives.

### Changed

- **Extended NL1 Smoke**: Updated `tb_ucie_rdi_to_pcie_pipe_nl1.sv` with deep pointer-wrap stimulus.
- **Documentation**: Added "Verification Status" table to `README.md` reflecting 100% line coverage and clean regression status.

## [1.0.4] — 2026-04-30

### Added

- **`tb_ucie_rdi_to_pcie_pipe_nl1.sv`** + **`sim_main_nl1.cpp`**: **NUM_LANES=1** Verilator smoke (**assertions-only**; dual-clock scoreboard stays on the main TB). **`make verilator_nl1`** / **`make regress_nl1`** (**`obj_dir_nl1/`**).
- CI **`nl1`** job after **`sim`**: **`make verilator_nl1`**.

## [1.0.3] — 2026-04-30

### Changed

- CI: add **`coverage`** workflow job after **`sim`** running **`make verilator_cov`**, with optional **`verilator-coverage-info`** artifact (`coverage.info` when `verilator_coverage` is installed).

## [1.0.2] — 2026-04-30

### Added

- Testbench **Test 6** (FIFO stress): multi-lane valid while **`pipe_ready`** held low until **`rdi_flow_ctrl`/`rdi_ready`** reflect full buffers; then **`pipe_ready`** restored and queues drain (scoreboard-checked).
- Testbench **Test 7** (**CRC lane 0**): **`crc_enable[0]`** with pulsed beats; mirror **`compute_crc32`** in TB vs **`crc_error[0]`** on **`negedge pipe_clk`** while enabled.
- **`make verilator_cov`** / **`make regress_cov`**: isolated build dir **`obj_dir_cov/`**, links **`verilated_cov.cpp`**, compiles **`sim_main.cpp`** with **`-DVM_COVERAGE=1`**, calls **`VerilatedCov::write()`** at end of simulation; optional **`coverage.info`** via **`verilator_coverage`** when installed.

### Changed

- Simulation ends at **`rdi_cycle == 400`** (extended stimulus).
- **`.gitignore`**: **`obj_dir_cov/`**, **`coverage.info`**.

## [1.0.1] — 2026-04-30

### Fixed

- Scoreboard: replace struct literal `'{data:, error:}` in `push_back` with field-wise assignments for **Verilator 5.020** (Ubuntu CI) compatibility (`UNSUPPORTED` on assignment patterns).

## [1.0.0] — 2026-04-30

### Added

- Reference scoreboard (`tb_ucie_rdi_to_pcie_pipe_scoreboard.sv`): checks PIPE accepted beats against RDI pushes per lane (zero-extended data and error flag); compares on `negedge pipe_clk` after each handshake so registered PIPE outputs are sampled coherently.
- `make regress` target: runs `make lint` then `make verilator` as the release regression gate.
- Verilator TB lint pass includes RTL + assertions + full testbench (`-Wno-SYNCASYNCNET` for testbench-only reset usage).
- Constraint templates under `constraints/` (Xilinx XDC and Synopsys-style SDC placeholders for CDC-related timing; **not** timing-signed-off).
- Expanded reusable-IP documentation in `docs/interface_spec.md`.
- This changelog.

### Changed

- Makefile simulation file list includes the scoreboard for Verilator and vendor flows using `VERILOG_SIMV`.
- README documents reusable IP layout, regression command, and Vivado source list including the scoreboard when running self-checking simulation.
- CI runs `make regress` instead of separate lint/sim steps.

### Notes

- RTL CRC remains a **demo residue check**, not a full PCIe packet CRC contract (see `docs/interface_spec.md`).
- PIPE outputs may change while `pipe_valid && !pipe_ready`; integrators requiring strict hold-until-handshake must constrain their environment or extend the RTL (see interface spec).
