# Changelog

All notable changes to this project are documented here. Version tags follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
