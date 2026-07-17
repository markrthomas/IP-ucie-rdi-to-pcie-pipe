# UVM verification guide

This guide describes the UVM environment in `test/uvm/` as it exists in this repository. It is intended to help verification owners extend the environment without confusing it with the Verilator smoke testbench, which remains the current release gate.

## Current scope

| Area | Current UVM status | Notes |
|------|--------------------|-------|
| Simulator target | Synopsys VCS | Driven by `test/uvm/Makefile.vcs` with `-ntb_opts uvm-1.2`. |
| DUT parameters | 4 lanes, 16-bit RDI, 32-bit PIPE, FIFO depth 16 | Lane/data geometry is centralized as parameters in `ucie_rdi_pcie_pkg` (`NUM_LANES`, `RDI_DATA_WIDTH`, `PIPE_DATA_WIDTH`, derived `RDI_BUS_WIDTH`/`PIPE_BUS_WIDTH`). Transaction widths, scoreboard loops/slices, and coverage sample ports derive from these, and `uvm_test_top` passes the same values into the interfaces and DUT. Fixed stimulus vectors in `seq_lib` and covergroup bins remain 4-lane specific. |
| TX path (`RDI -> PIPE`) | Stimulated and scoreboarding enabled | Active RDI agent drives requests; passive PIPE monitor observes accepted beats. |
| RX path (`PIPE -> RDI`) | Wired with passive monitors and a smoke RX driver, with basic checking | `uvm_test_top` instantiates RX interfaces, binds passive RX monitors, and the sanity test now runs a small PIPE RX sequence through `pipe_rx_agent`. |
| CRC | Enabled for the smoke sequence | `uvm_test_top` now toggles `crc_enable` for a lane-0 CRC smoke run and mirrors the residue check. |
| Backpressure | PIPE TX ready is agent-controlled in the sanity test | The backpressure sequence now drives `ready` low/high/low/high with longer stalls; FIFO-full behavior is still a future extension because the RDI source driver remains handshake-gated. |
| Assertions | Compiled and active in the UVM top | CDC monitor/statistics now run in both the UVM flow and the non-UVM regression. |

## UVM block diagram

```mermaid
flowchart LR
    subgraph TOP[uvm_test_top]
        RDI_IF[ucie_rdi_if\nTX virtual interface]
        PIPE_IF[pcie_pipe_if\nTX virtual interface]
        RX_RDI_IF[ucie_rdi_if\nRX monitor path]
        RX_PIPE_IF[pcie_pipe_if\nRX smoke path]
        DUT[ucie_rdi_to_pcie_pipe_bridge]
    end

    subgraph UVM[UVM components]
        TEST[ucie_rdi_pcie_sanity_test]
        ENV[ucie_rdi_pcie_env]
        RDI_AGENT[active ucie_rdi_agent]
        RDI_SQR[ucie_rdi_sequencer]
        RDI_DRV[ucie_rdi_driver]
        RDI_MON[ucie_rdi_monitor]
        PIPE_AGENT[configurable pcie_pipe_agent]
        PIPE_MON[pcie_pipe_monitor]
        SB[ucie_rdi_pcie_scoreboard]
    end

    TEST --> ENV
    ENV --> RDI_AGENT
    ENV --> PIPE_AGENT
    ENV --> SB
    RDI_AGENT --> RDI_SQR
    RDI_AGENT --> RDI_DRV
    RDI_AGENT --> RDI_MON
    PIPE_AGENT --> PIPE_MON
    RDI_DRV --> RDI_IF
    RDI_MON --> RDI_IF
    PIPE_MON --> PIPE_IF
    RDI_IF --> DUT
    DUT --> PIPE_IF
    RX_PIPE_IF --> DUT
    DUT --> RX_RDI_IF
    RDI_MON -- accepted RDI beats --> SB
    PIPE_MON -- accepted PIPE beats --> SB
```

## Transaction flow

```mermaid
sequenceDiagram
    participant Seq as RDI sequence
    participant Drv as RDI driver
    participant Dut as DUT TX FIFO
    participant RMon as RDI monitor
    participant PMon as PIPE monitor
    participant Sb as Scoreboard

    Seq->>Drv: ucie_rdi_transaction
    Drv->>Dut: valid/data/error until any requested lane is ready
    RMon->>Sb: push expected beat on valid & ready
    Dut->>PMon: pipe_valid/data/error when FIFO data reaches PIPE domain
    PMon->>Sb: observed PIPE beat on valid & ready
    Sb->>Sb: pop per-lane queue and compare lower 16 data bits
```

The monitor and scoreboard operate per accepted beat, not per raw cycle. Because RDI and PIPE are asynchronous, matching is queue-based by lane rather than cycle-based.

## Component map

| File | Component | Role |
|------|-----------|------|
| `test/uvm/uvm_test_top.sv` | `uvm_test_top` | Generates clocks/reset, instantiates interfaces and DUT, binds virtual interfaces with `uvm_config_db`, starts UVM. |
| `test/uvm/ucie_rdi_if.sv` | `ucie_rdi_if` | RDI TX/RX signal bundle with driver and monitor clocking blocks. |
| `test/uvm/pcie_pipe_if.sv` | `pcie_pipe_if` | PIPE TX/RX signal bundle with driver and monitor clocking blocks. |
| `test/uvm/ucie_rdi_pcie_pkg.sv` | transaction classes | RDI and PIPE sequence items whose widths derive from the package parameters (`NUM_LANES`, `RDI_DATA_WIDTH`, `PIPE_DATA_WIDTH`). |
| `test/uvm/ucie_rdi_pcie_pkg.sv` | `ucie_rdi_driver` | Drives RDI TX `valid`, `data`, and `error` through `ucie_rdi_if.drv_cb`. |
| `test/uvm/ucie_rdi_pcie_pkg.sv` | `ucie_rdi_monitor` | Publishes RDI TX transactions when at least one lane completes `valid & ready`. |
| `test/uvm/ucie_rdi_pcie_pkg.sv` | `pcie_pipe_monitor` | Publishes PIPE TX transactions when at least one lane completes `valid & ready`. |
| `test/uvm/ucie_rdi_pcie_pkg.sv` | `ucie_rdi_pcie_scoreboard` | Maintains one expected queue per lane and compares observed PIPE beats against RDI expectations. |
| `test/uvm/seq_lib/ucie_rdi_seq_lib.sv` | sequence library | Provides single-lane, all-lane, error, and repeated lane-1 traffic sequences. |

## Sequence and coverage intent matrix

| Sequence | Stimulus | Intended check | Current checking strength |
|----------|----------|----------------|---------------------------|
| `ucie_rdi_single_lane_seq` | One lane-0 beat with `data == 64'hDEAD` | Basic lane-0 TX transport | Lower 16 bits and zero-extended upper half on lane 0. |
| `ucie_rdi_multi_lane_seq` | One all-lane beat with lane-specific 16-bit words | Lane packing and independent per-lane queueing | Same per lane with observed PIPE handshake. |
| `ucie_rdi_error_seq` | Lane-2 valid with `error[2] == 1` | Error propagation | **Error bit compared** on observed PIPE beats (with data/zero-extension checks). |
| `ucie_rdi_flow_ctrl_seq` | Thirty-two lane-1 beats | Repeated traffic through FIFO | Data order checked if PIPE accepts all beats; paired with a backpressure sequence in the sanity test. |
| `ucie_rdi_crc_seq` | Two lane-0 beats with CRC enabled | CRC residue smoke | `crc_enable[0]` is asserted around the sequence and the UVM top mirrors the residue compare. |
| `pcie_pipe_backpressure_seq` | PIPE ready low/high/low/high | PIPE stall / release behavior | Drives `ready` low for 48 cycles, releases for 16, reasserts low for 16, then releases for 24. |
| `pcie_pipe_rx_seq` | PIPE RX valid/data/error beats | PIPE -> RDI conversion and ordering | Mirrored RX queueing checks lower-half data and error propagation on accepted RX beats. |

## Scoreboard contract

| Expected behavior | Current implementation | Gap to close |
|-------------------|------------------------|--------------|
| Accepted **RDI** lane handshake creates one expected queue entry | `write_rdi()` pushes when `tr.valid[i] && tr.ready[i]` (monitor emits on full-beat handshakes) | None for TX enqueue semantics. |
| Accepted **PIPE** lane handshake consumes one expected entry | `write_pipe()` pops when `tr.valid[i] && tr.ready[i]` | None for TX dequeue semantics. |
| RDI 16-bit data zero-extends into PIPE 32-bit data | Lower **and upper** 16 PIPE bits checked vs. zero-extension | None for width check on expectations driven from RDI. |
| Error bit propagates from RDI to PIPE | `write_pipe()` compares `tr.error[i]` vs. stored expectation | None for lanes exercised by sequences. |
| End-of-test drains all TX expectation queues | `check_phase` reports `SB_DRAIN` if any `tx_exp_q[i]` non-empty | RX path / system-level closure still open. |

## Recommended UVM closure plan

| Priority | Work item | Why it matters |
|----------|-----------|----------------|
| 1 | Make transaction widths parameter-aware or centralize lane/data constants in a config object | **Delivered (centralization):** lane/data geometry lives in `ucie_rdi_pcie_pkg` parameters that drive the transaction widths, scoreboard slicing, coverage sample ports, and (via `uvm_test_top`) the interface/DUT instantiations. Remaining for a `NUM_LANES` sweep: generalize `seq_lib` stimulus vectors and covergroup bins. |
| 2 | Extend scoreboard for RX path and full-system checks | TX path: **delivered** — per-lane `valid & ready` queueing, upper 16-bit zero check, error compare, and `check_phase` TX queue drain. RX path now has smoke-driver/queueing scaffolding. |
| 3 | Expand PIPE backpressure coverage and decouple passive vs. active ready control | Required to verify FIFO full, `rdi_flow_ctrl`, and hold-under-stall behavior in UVM. |
| 4 | Expand RX path sequences and mirrored RDI RX scoreboard | The RTL includes `PIPE -> RDI`; current UVM now exercises a smoke sequence but still needs deeper RX closure. |
| 5 | Extend functional coverage to RX/TX direction, FIFO occupancy, width conversion, and CRC enable | **RX direction: delivered** — `ucie_rdi_pcie_coverage` now samples the reverse path via `cg_rx_pipe` (PIPE RX stimulus) and `cg_rx_rdi` (RDI RX output), fed from the RX monitors alongside the TX covergroups. Still open: FIFO-occupancy, width-conversion, and CRC-enable coverpoints. |
| 6 | Add a CRC predictor and broaden CRC coverage | Current smoke coverage validates the lane-0 residue path, but the model is still only a top-level checker. |

## Run commands

From `test/uvm/`:

```bash
make -f Makefile.vcs compile
make -f Makefile.vcs run
make -f Makefile.vcs run UVM_TESTNAME=ucie_rdi_pcie_sanity_test
make -f Makefile.vcs pdf
make -f Makefile.vcs clean
```

The UVM flow requires a licensed VCS installation with UVM 1.2 support. The repository's open-source CI path uses Verilator and does not compile UVM.
