# Changelog

All notable changes to this project are documented here. Version tags follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
