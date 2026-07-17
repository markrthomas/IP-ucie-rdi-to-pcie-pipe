# Verification plan — UCIe RDI → PCIe PIPE bridge

## Goals

- Prove correct CDC (Gray pointers, full/empty, no overflow).
- Prove RDI valid/ready and PIPE valid/ready behavior under backpressure.
- Keep regressions fast and reproducible (Verilator smoke + lint in CI).

## Regression commands (local / CI)

```bash
make regress      # lint + Verilator smoke (CI release gate)
make regress_cov  # lint + coverage build/run (+ coverage.info if verilator_coverage exists)
make regress_nl1  # lint + NUM_LANES=1 smoke (obj_dir_nl1)
make lint         # Verilator -Wall: RTL + assertions + TB (-Wno-SYNCASYNCNET on TB pass)
make verilator    # Smoke simulation only
make verilator_cov # Coverage sim only (uses obj_dir_cov; writes coverage.dat)
make verilator_nl1 # NUM_LANES=1 smoke only (after lint)
make clean        # Remove obj_dir, obj_dir_cov, obj_dir_nl1, coverage.info, …
```

GitHub Actions runs **`make regress`** on push/PR to `main` / `master`, then **`make verilator_cov`** (artifact: **`coverage.info`** when `verilator_coverage` is available) and **`make verilator_nl1`**. See `.github/workflows/verilator.yml`.

## Verification environment map

| Environment | Location | Simulator | Current role | Release-gate status |
|-------------|----------|-----------|--------------|---------------------|
| Verilator smoke | Root `Makefile`, `test/tb_ucie_rdi_to_pcie_pipe_bridge.sv` | Verilator | Fast RTL lint, smoke stimulus, scoreboard, CRC lane-0 mirror, FIFO stress | Current CI/release gate |
| NUM_LANES=1 smoke | Root `Makefile`, `test/tb_ucie_rdi_to_pcie_pipe_nl1.sv` | Verilator | Parameter-width smoke with assertion monitor | Current CI side gate |
| UVM | `test/uvm/` | VCS/UVM 1.2 | TX-path UVM smoke, CDC assertions, and extensibility scaffold | Manual, not in open-source CI |

Detailed UVM architecture, component roles, sequence matrix, and closure gaps are documented in `docs/uvm_verification.md`.

## Smoke testbench

Source: `test/tb_ucie_rdi_to_pcie_pipe_bridge.sv`, clocks from `sim_main.cpp`.

Scenarios:

1. Single-beat transfer on lane 0  
2. All-lane simultaneous transfer  
3. PIPE backpressure (`pipe_ready` deasserted)  
4. `rdi_error` on one lane  
5. Sustained multi-lane traffic  
6. **FIFO stress** — Multi-lane push while **`pipe_ready = 0`** until **`rdi_flow_ctrl` / `rdi_ready`** show full-handling; then **`pipe_ready`** restored and FIFOs drain (scoreboard checks data/order).  
7. **CRC lane 0** — **`crc_enable[0]`** with two pulsed beats; TB mirrors **`compute_crc32`** and checks **`crc_error[0]`** vs residue **`0x17047432`** on each **`negedge pipe_clk`** while CRC is enabled.

Monitor module: `test/ucie_rdi_to_pcie_pipe_bridge_assertions.sv` — RDI data/error stability while valid, per-lane handshake statistics (`print_statistics()`).

Reference scoreboard: `test/tb_ucie_rdi_to_pcie_pipe_scoreboard.sv` — queues expected beats from `rdi_valid && rdi_ready`, pops on `pipe_valid && pipe_ready`, compares zero-extended data and error on **`negedge pipe_clk`** after each handshake so registered PIPE outputs match nonblocking updates.

**Statistics caveat:** `rdi_error_count` / `pipe_error_count` increment on **every cycle** the respective `*_error` is asserted, not only on completed beats. RDI and PIPE error counts can differ when the error indication is held for different numbers of cycles in the two domains.

## NUM_LANES=1 smoke

Source: `tb_ucie_rdi_to_pcie_pipe_nl1`, clocks from `sim_main_nl1.cpp` (same coarse stepping as `sim_main.cpp`). **Assertions-only** — verifies **`NUM_LANES == 1`** widths/parameters and CDC monitors without the dual-clock scoreboard (scoreboard remains on the main TB where stimulus aligns with its sampling model). Includes a **deep TX FIFO push** under stalled **`pipe_ready`**, **drain**, and a minimal **PIPE RX → RDI** beat. Ends at **`rdi_cycle == 280`** with **`[TEST NL1]`** messages.

## Assertion / monitoring policy

- **RDI:** Data and per-lane `rdi_error` are expected stable while `rdi_valid` stays asserted (matches typical source behavior).
- **PIPE:** The bridge may update registered `pipe_data` / `pipe_error` while `pipe_valid && !pipe_ready` (see DUT `always_ff`). There is **no** “stable while valid” check on PIPE data in the monitor so simulation stays aligned with the RTL.

## UVM verification focus

The UVM environment is intentionally separated from the Verilator smoke regression because it depends on VCS and UVM 1.2. It should be treated as the path for constrained-random growth, coverage closure, and reusable verification IP.

| UVM area | Present today | Recommended next check |
|----------|---------------|------------------------|
| RDI active agent | Drives fixed-width 4-lane TX transactions | Add parameter/config object for lane and data widths. |
| PIPE passive/active agent | Monitors TX PIPE accepts and can drive `ready` in active mode | Deep backpressure + all-lane FIFO-fill now drive every TX FIFO to full with a scoreboard `SB_FIFO_FULL` check; remaining polish is a cleaner passive/active mode switch. |
| Scoreboard | Per-lane TX queues, **`valid & ready`** gating, lower **and upper (zero)** 16-bit data compare, **error** compare, **`check_phase` queue drain** | Functional coverage; RX path scoreboard; CRC predictor |
| RX path | DUT, interfaces, passive monitors, and an active PIPE RX smoke path are wired | Expand RX stimulus and mirrored scoreboard checks. |
| CRC | Enabled for the UVM smoke sequence | Add a CRC predictor and broader CRC coverage. |
| Functional coverage | Initial RDI/PIPE transaction coverage present | Expand to RX/TX direction, FIFO occupancy, width conversion, and CRC. |

## Recent verification-related changes (maintenance log)

| Area | Change |
|------|--------|
| FIFO read path | PIPE-side buffer read mux indexes `pipe_rd_ptr` (read pointer), not the synchronized write pointer. |
| CRC gating | CRC advances only on accepted PIPE beats: `pipe_lane_valid && pipe_lane_ready` (placeholder CRC vs residue, not packet-qualified PCIe). |
| Lint | Four passes: RTL top, assertions top, main TB top + files, **NUM_LANES=1** TB top + files (`-Wno-SYNCASYNCNET` on TB passes only). |
| Scoreboard | Reference module compares PIPE accepts to RDI queue per lane; CI/regress fails on mismatch (`$fatal`). |
| CI | **`sim`** → `make regress`; **`coverage`** (needs sim) → `make verilator_cov`; **`nl1`** (needs sim) → `make verilator_nl1`; optional **`coverage.info`** artifact. |
| TB | Tests 6–7: FIFO fill under stalled PIPE + CRC mirror vs `crc_error`; simulation ends `rdi_cycle == 400`. |
| Coverage | `make regress_cov` / `obj_dir_cov`; `sim_main.cpp` calls `VerilatedCov::write` when `VM_COVERAGE=1`. |

## Verilator coverage

- **`make verilator_cov`** / **`make regress_cov`** build into **`obj_dir_cov/`** (default **`obj_dir/`** unchanged).
- **`sim_main.cpp`** calls **`VerilatedCov::write()`** when **`VM_COVERAGE`** is defined at compile time (`g++ -DVM_COVERAGE=1`), producing **`obj_dir_cov/coverage.dat`**.
- With **`verilator_coverage`** on **`PATH`**, the Makefile emits **`coverage.info`** at the repo root.

## Coverage and formal (recommended next steps)

Priorities for higher confidence:

1. **Corner cases** — Deeper pointer-wrap stimulus ( **`NUM_LANES=1`** smoke exercises wrap + minimal RX).  
2. **Coverage closure** — Keep **`README.md`** verification metrics aligned with `make regress_cov` / `make coverage_summary`; treat **~95% overall line coverage** on RTL+TB as the current documented baseline until formal or richer stimulus lands.  
3. **UVM closure** — Initial functional coverage, RX smoke path, and CRC-in-UVM (scoreboard strengthening, assertion bind, richer PIPE backpressure, and smoke CRC coverage are delivered — see `docs/uvm_verification.md`).
4. **Formal** — Async FIFO invariants + handshake properties (tool-specific).  
5. **PIPE policy (optional)** — Strict **`valid`⇒data hold** RTL + monitor if integrators require it.

**Delivered in-tree:** Scoreboard; FIFO stress + CRC checker in TB; **`regress_cov`** flow; NL1 deep FIFO + RX pulse; UVM scoreboard drain check, per-lane **`valid & ready`** queueing, zero-extension and **error** compare on PIPE observations; UVM CDC assertions/statistics bind; richer UVM PIPE backpressure sequencing; initial UVM functional coverage collector; initial RX smoke path and mirrored RX queueing; lane-0 CRC smoke sequencing with a mirrored residue check; UVM all-lane TX FIFO-full closure (cycle-accurate flow-control monitor path, deep backpressure + all-lane fill sequences, and an `SB_FIFO_FULL` scoreboard check that proves the full condition was reached with in-order drain).

## Exit criteria (smoke + lint)

- `make lint` completes with no Verilator warnings promoted to errors (TB pass waives `SYNCASYNCNET` only).  
- `make regress` (or `make verilator`) runs to `$finish` with **`[SCOREBOARD] PASS`** and no unexpected CDC `$warning` from monitors.  
- Transfer counts remain consistent between RDI (`valid && ready`) and PIPE (`valid && ready`) sides per lane for the smoke stimulus (modulo error-statistics caveat above).
