# Verification plan — UCIe RDI → PCIe PIPE bridge

## Goals

- Prove correct CDC (Gray pointers, full/empty, no overflow).
- Prove RDI valid/ready and PIPE valid/ready behavior under backpressure.
- Keep regressions fast and reproducible (Verilator smoke + lint in CI).

## Regression commands (local / CI)

```bash
make lint      # Verilator -Wall lint, separate tops: RTL + assertion module
make verilator # Build + run smoke testbench (dual clocks from sim_main.cpp)
make clean     # Remove obj_dir and common simulator artifacts
```

GitHub Actions runs `make lint` then `make verilator` on `main` / `master` (see `.github/workflows/verilator.yml`).

## Smoke testbench

Source: `tb_ucie_rdi_to_pcie_pipe_bridge` (root `.sv` files), clocks from `sim_main.cpp`.

Scenarios:

1. Single-beat transfer on lane 0  
2. All-lane simultaneous transfer  
3. PIPE backpressure (`pipe_ready` deasserted)  
4. `rdi_error` on one lane  
5. Sustained multi-lane traffic  

Monitor module: `ucie_rdi_to_pcie_pipe_bridge_assertions` — RDI data/error stability while valid, per-lane handshake statistics (`print_statistics()`).

**Statistics caveat:** `rdi_error_count` / `pipe_error_count` increment on **every cycle** the respective `*_error` is asserted, not only on completed beats. RDI and PIPE error counts can differ when the error indication is held for different numbers of cycles in the two domains.

## Assertion / monitoring policy

- **RDI:** Data and per-lane `rdi_error` are expected stable while `rdi_valid` stays asserted (matches typical source behavior).
- **PIPE:** The bridge may update registered `pipe_data` / `pipe_error` while `pipe_valid && !pipe_ready` (see DUT `always_ff`). There is **no** “stable while valid” check on PIPE data in the monitor so simulation stays aligned with the RTL.

## Recent verification-related changes (maintenance log)

| Area | Change |
|------|--------|
| FIFO read path | PIPE-side buffer read mux indexes `pipe_rd_ptr` (read pointer), not the synchronized write pointer. |
| CRC gating | CRC advances only on accepted PIPE beats: `pipe_lane_valid && pipe_lane_ready` (placeholder CRC vs residue, not packet-qualified PCIe). |
| Lint | `make lint` runs two passes with explicit `--top-module` (no truncation, exit code propagates). Assertions: `BUFFER_DEPTH` sanity generate, RDI checks use async-reset-safe `always_ff`, `pipe_data` kept referenced for lint-only builds. |
| CI | Workflow runs `make lint` before `make verilator`. |

## Coverage and formal (recommended next steps)

Priorities for higher confidence:

1. **Self-checking scoreboard** — Expected data per lane per beat (avoid relying only on prints and transfer counts).  
2. **Corner cases** — FIFOalmost-full/full, pointer wrap, single-lane `NUM_LANES=1`, min `BUFFER_DEPTH` if supported.  
3. **CRC tests** — With `crc_enable` asserted: known vectors vs expected residue; reset/disable behavior.  
4. **Coverage** — Line/FSM/toggle (Verilator coverage or vendor sim) with explicit goals; current README `%` figures remain aspirational until measured.  
5. **Formal** — Async FIFO inductive invariants + handshake properties (requires appropriate tooling).  
6. **PIPE policy (optional)** — If strict PIPE hold is required, align RTL (hold data until handshake) and reintroduce PIPE stability checks in the monitor.

## Exit criteria (smoke + lint)

- `make lint` completes with no Verilator warnings promoted to errors.  
- `make verilator` runs to `$finish` with no unexpected `$warning` from CDC monitors.  
- Transfer counts remain consistent between RDI (`valid && ready`) and PIPE (`valid && ready`) sides per lane for the smoke stimulus (modulo error-statistics caveat above).
