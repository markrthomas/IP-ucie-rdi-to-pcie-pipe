# Interface specification — reusable IP

This document defines the **integration contract** for `ucie_rdi_to_pcie_pipe_bridge`. Numeric widths below use **default** parameters; actual widths scale with parameters (see §Parameters).

## Parameters (compile-time)

| Parameter | Default | Description |
|-----------|---------|-------------|
| `NUM_LANES` | 4 | Per-lane independent datapaths |
| `RDI_DATA_WIDTH` | 16 | RDI data width per lane (bits) |
| `PIPE_DATA_WIDTH` | 32 | PIPE data width per lane (bits); RTL zero-extends RDI into upper bits |
| `BUFFER_DEPTH` | 16 | Elastic buffer entries **per lane**; must be ≥ 1 |

**Supported use:** Any combination where `BUFFER_DEPTH >= 1` and port widths are consistent with the parameterization. Narrow `NUM_LANES` (for example 1) is allowed if indices are wired accordingly.

## Clocking and reset

| Signal | Domain | Description |
|--------|--------|-------------|
| `rdi_clk` | RDI | Rising-edge captures all RDI-domain sequential logic |
| `pipe_clk` | PIPE | Rising-edge captures PIPE-domain sequential logic and CRC regs |
| `rst_n` | Global async | **Active-low asynchronous reset**, deassertion assumed synchronous enough to both clock domains for your flow (standard ASIC/FPGA practice: assert async, deassert after clocks stable, meeting recovery/removal) |

**Integrator guidance**

- Keep both clocks **free-running** during reset deassertion unless your methodology specifies otherwise.
- Release `rst_n` only after power/clocks are valid; apply vendor-specific reset-tree constraints.

## RDI clock domain (source → bridge)

### Data and handshake

| Signal | Width | Direction | Description |
|--------|-------|-----------|-------------|
| `rdi_valid` | `NUM_LANES` | In | Per-lane beat valid |
| `rdi_ready` | `NUM_LANES` | Out | Per-lane accept (buffer not full) |
| `rdi_data` | `NUM_LANES*RDI_DATA_WIDTH` | In | Packed lane data: lane `k` occupies `rdi_data[k*RDI_DATA_WIDTH +: RDI_DATA_WIDTH]` |
| `rdi_error` | `NUM_LANES` | In | Per-lane metadata/error flag sampled into the FIFO with the beat |

**Rules**

- A beat is transferred on lane `k` when `rdi_valid[k] && rdi_ready[k]` on a rising `rdi_clk` edge.
- While `rdi_valid[k]` remains asserted, **`rdi_data[k]` and `rdi_error[k]` must remain stable** (standard valid/ready source behavior).
- `rdi_ready[k]` may glitch per cycle; the source must only treat `rdi_valid[k] && rdi_ready[k]` as a successful transfer.

### Flow control outputs

| Signal | Width | Description |
|--------|-------|-------------|
| `rdi_flow_ctrl` | `NUM_LANES` | Asserted when that lane’s elastic buffer is **full** |
| `rdi_ready` | `NUM_LANES` | Complement of full for simple backpressure (`rdi_ready = ~full` style) |

## PIPE clock domain (bridge → sink)

### Data and handshake

| Signal | Width | Direction | Description |
|--------|-------|-----------|-------------|
| `pipe_valid` | `NUM_LANES` | Out | Per-lane beat valid toward sink |
| `pipe_ready` | `NUM_LANES` | In | Per-lane sink ready |
| `pipe_data` | `NUM_LANES*PIPE_DATA_WIDTH` | Out | Lane `k`: lower `RDI_DATA_WIDTH` bits carry payload; upper bits **zero** (extension) |
| `pipe_error` | `NUM_LANES` | Out | Per-lane flag synchronized through the read path |

**Rules**

- A beat is consumed on lane `k` when `pipe_valid[k] && pipe_ready[k]` rises on `pipe_clk` (sink sampling policy must match your STA/sim assumptions).
- **`pipe_data` / `pipe_error` are not guaranteed stable whenever `pipe_valid && !pipe_ready`.** The RTL may refresh registered PIPE outputs while valid is high and ready is low. If your integration requires strict PIPE “hold until handshake,” treat that as an **extension** (RTL + constraint + verification updates).

### CRC interface

| Signal | Width | Description |
|--------|-------|-------------|
| `crc_enable` | `NUM_LANES` | In (PIPE cd) | Enables running CRC update for that lane |
| `crc_error` | `NUM_LANES` | Out | Indicates residue mismatch when `crc_enable` is active |

**CRC semantics (current RTL)**

- CRC updates **only on accepted PIPE beats**: `pipe_valid && pipe_ready` when `crc_enable` is set.
- Algorithm is a **32-bit linear-feedback shift style** update with polynomial `0x04C11DB7`; the RTL compares against a **demo residue** `32'h1704_7432`. This is **not** a full PCIe TLP/LCRC/DLCRC implementation. Replace for production protocol compliance.

## Latency (typical simulation)

Order-of-magnitude only; validate per configuration:

- CDC pointer synchronization: a few `pipe_clk` cycles from write to visibility on read side.
- Additional registered PIPE stage: **observed PIPE data for an accepted beat is coherent when sampled after the RTL nonblocking updates for that cycle** (reference TB scoreboard uses `negedge pipe_clk` after a handshake).

## Timing placeholders

Example constraint shells (not signed off): `constraints/example.xdc`, `constraints/example.sdc`.

## Reference simulation bundle

Verilator / Makefile flow files (root):

- `ucie_rdi_to_pcie_pipe_bridge.sv` — canonical RTL  
- `tb_ucie_rdi_to_pcie_pipe_bridge.sv` — smoke stimulus  
- `tb_ucie_rdi_to_pcie_pipe_scoreboard.sv` — self-checking reference  
- `ucie_rdi_to_pcie_pipe_bridge_assertions.sv` — monitors / statistics  

Vendor flows that compile `sim_top.sv` should add the scoreboard to the file list when using the root testbench implementation.
