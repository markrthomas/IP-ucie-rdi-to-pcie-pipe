# Verification plan — UCIe RDI → PCIe PIPE bridge

## Goals

- Prove correct CDC (Gray pointers, full/empty, no overflow).
- Prove RDI valid/ready and PIPE valid/ready behavior under backpressure.
- Keep regressions fast and reproducible (Verilator smoke + lint in CI).

## Regression commands (local / CI)

```bash
make regress      # lint + Verilator smoke (CI release gate)
make regress_cov  # lint + coverage build/run (+ coverage.info if verilator_coverage exists)
make lint         # Verilator -Wall: RTL + assertions + TB (-Wno-SYNCASYNCNET on TB pass)
make verilator    # Smoke simulation only
make verilator_cov # Coverage sim only (uses obj_dir_cov; writes coverage.dat)
make clean        # Remove obj_dir, obj_dir_cov, coverage.info, …
```

GitHub Actions runs **`make regress`** on `main` / `master` (see `.github/workflows/verilator.yml`).

## Smoke testbench

Source: `tb_ucie_rdi_to_pcie_pipe_bridge` (root `.sv` files), clocks from `sim_main.cpp`.

Scenarios:

1. Single-beat transfer on lane 0  
2. All-lane simultaneous transfer  
3. PIPE backpressure (`pipe_ready` deasserted)  
4. `rdi_error` on one lane  
5. Sustained multi-lane traffic  
6. **FIFO stress** — Multi-lane push while **`pipe_ready = 0`** until **`rdi_flow_ctrl` / `rdi_ready`** show full-handling; then **`pipe_ready`** restored and FIFOs drain (scoreboard checks data/order).  
7. **CRC lane 0** — **`crc_enable[0]`** with two pulsed beats; TB mirrors **`compute_crc32`** and checks **`crc_error[0]`** vs residue **`0x17047432`** on each **`negedge pipe_clk`** while CRC is enabled.

Monitor module: `ucie_rdi_to_pcie_pipe_bridge_assertions` — RDI data/error stability while valid, per-lane handshake statistics (`print_statistics()`).

Reference scoreboard: `tb_ucie_rdi_to_pcie_pipe_scoreboard` — queues expected beats from `rdi_valid && rdi_ready`, pops on `pipe_valid && pipe_ready`, compares zero-extended data and error on **`negedge pipe_clk`** after each handshake so registered PIPE outputs match nonblocking updates.

**Statistics caveat:** `rdi_error_count` / `pipe_error_count` increment on **every cycle** the respective `*_error` is asserted, not only on completed beats. RDI and PIPE error counts can differ when the error indication is held for different numbers of cycles in the two domains.

## Assertion / monitoring policy

- **RDI:** Data and per-lane `rdi_error` are expected stable while `rdi_valid` stays asserted (matches typical source behavior).
- **PIPE:** The bridge may update registered `pipe_data` / `pipe_error` while `pipe_valid && !pipe_ready` (see DUT `always_ff`). There is **no** “stable while valid” check on PIPE data in the monitor so simulation stays aligned with the RTL.

## Recent verification-related changes (maintenance log)

| Area | Change |
|------|--------|
| FIFO read path | PIPE-side buffer read mux indexes `pipe_rd_ptr` (read pointer), not the synchronized write pointer. |
| CRC gating | CRC advances only on accepted PIPE beats: `pipe_lane_valid && pipe_lane_ready` (placeholder CRC vs residue, not packet-qualified PCIe). |
| Lint | Three passes: RTL top, assertions top, TB top + full file list (`-Wno-SYNCASYNCNET` on TB pass only). |
| Scoreboard | Reference module compares PIPE accepts to RDI queue per lane; CI/regress fails on mismatch (`$fatal`). |
| CI | Workflow runs `make regress`. |
| TB | Tests 6–7: FIFO fill under stalled PIPE + CRC mirror vs `crc_error`; simulation ends `rdi_cycle == 400`. |
| Coverage | `make regress_cov` / `obj_dir_cov`; `sim_main.cpp` calls `VerilatedCov::write` when `VM_COVERAGE=1`. |

## Verilator coverage

- **`make verilator_cov`** / **`make regress_cov`** build into **`obj_dir_cov/`** (default **`obj_dir/`** unchanged).
- **`sim_main.cpp`** calls **`VerilatedCov::write()`** when **`VM_COVERAGE`** is defined at compile time (`g++ -DVM_COVERAGE=1`), producing **`obj_dir_cov/coverage.dat`**.
- With **`verilator_coverage`** on **`PATH`**, the Makefile emits **`coverage.info`** at the repo root.

## Coverage and formal (recommended next steps)

Priorities for higher confidence:

1. **Corner cases** — Dedicated **`NUM_LANES=1`** TB variant or compile sweep; deeper pointer-wrap stimulus.  
2. **Coverage closure** — Publish thresholds / reviewed **`coverage.info`** summaries (replace README `%` placeholders).  
3. **Formal** — Async FIFO invariants + handshake properties (tool-specific).  
4. **PIPE policy (optional)** — Strict **`valid`⇒data hold** RTL + monitor if integrators require it.

**Delivered in-tree:** Scoreboard; FIFO stress + CRC checker in TB; **`regress_cov`** flow.

## Exit criteria (smoke + lint)

- `make lint` completes with no Verilator warnings promoted to errors (TB pass waives `SYNCASYNCNET` only).  
- `make regress` (or `make verilator`) runs to `$finish` with **`[SCOREBOARD] PASS`** and no unexpected CDC `$warning` from monitors.  
- Transfer counts remain consistent between RDI (`valid && ready`) and PIPE (`valid && ready`) sides per lane for the smoke stimulus (modulo error-statistics caveat above).
