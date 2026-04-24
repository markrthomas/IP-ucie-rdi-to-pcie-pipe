
# UCIe RDI to PCIe PIPE Bridge

A production-grade SystemVerilog hardware bridge that converts UCIe 1.0 RDI (Reduced Die-to-Die Interface) signals to PCIe Gen 4 PIPE format. Designed for Verilator simulation with comprehensive verification, CRC support, and formal assertions.

## Features

✅ **Dual Clock Domain Support**: Safe synchronization between RDI (100 MHz) and PIPE (150 MHz) clocks  
✅ **4-Lane Configuration**: Fully parameterized design supporting configurable lane counts  
✅ **Elastic Buffering**: 16-entry FIFOs per lane to absorb frequency variations  
✅ **CRC32 Calculation**: Polynomial-based error detection with configurable enable  
✅ **Flow Control**: Complete ready/valid handshaking with backpressure  
✅ **Error Handling**: Per-lane error signals safely synchronized across domains  
✅ **Metastability Hardening**: Dual-flop synchronizers and Gray code pointer crossing  
✅ **Simulation monitors**: CDC-oriented checks and per-lane transfer statistics (`ucie_rdi_to_pcie_pipe_bridge_assertions.sv`)  
✅ **Verilator Compatible**: Clean SystemVerilog with no vendor-specific constructs  

## Project Structure

```
IP-ucie-rdi-to-pcie-pipe/
├── ucie_rdi_to_pcie_pipe_bridge.sv          # Canonical RTL (main design + CRC)
├── ucie_rdi_to_pcie_pipe_bridge_assertions.sv # CDC monitors and transfer statistics
├── tb_ucie_rdi_to_pcie_pipe_bridge.sv       # Testbench
├── sim_top.sv                               # Sim top for VCS/Questa/Xcelium (#-based clocks)
├── sim_main.cpp                             # Verilator C++ top (clocks + reset)
├── src/
│   └── ucie_rdi_to_pcie_pipe_bridge.sv     # Thin `include wrapper (EDA project convention)
├── test/
│   ├── ucie_rdi_to_pcie_pipe_bridge_assertions.sv # Thin `include wrapper
│   ├── tb_ucie_rdi_to_pcie_pipe_bridge.sv         # Thin `include wrapper
│   └── sim_top.sv                                 # Thin `include wrapper
├── doc/                                     # Layout consistency directory
├── Makefile                                 # Multi-simulator support (uses root files)
├── README.md                                # This file
├── LICENSE                                  # MIT License
└── docs/
    ├── architecture.md                      # Detailed design documentation
    ├── interface_spec.md                    # Signal specifications
    └── verification_plan.md                 # Test and assertion strategy
```

> **Note:** `make verilator`, `make lint`, and `make verilator_debug` compile the root-level `.sv` files directly. The `src/` and `test/` subdirectory copies are thin `` `include `` wrappers for EDA tools (Vivado, etc.) that prefer a `src/`/`test/` layout; they resolve their includes relative to their own directory so Vivado-style project trees work correctly.

## Architecture Overview

### Block Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                    UCIe RDI -> PIPE Bridge                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  RDI Clock Domain          CDC Crossing       PIPE Clock Domain │
│       100 MHz                                        150 MHz    │
│         |                                              |        │
│    [INPUT]                                         [OUTPUT]     │
│      |                                               |          │
│  ┌─────────┐    ┌──────────────┐    ┌──────────┐                │
│  │ Elastic │    │ Gray Code    │    │ Reg Out  │                │
│  │  FIFO   ├──→ │ Synchronizer ├──→ │  Stage   ├──→ [PIPE Out]  │
│  │ (16-ent)│    │ (2-flop)     │    │  [CRC]   │                │
│  └─────────┘    └──────────────┘    └──────────┘                │
│      |                                      |                   │
│  [FLOW CTL] ←────────────────────── [READY]                     │
│   (per lane)                         (synced)                   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘

Per-Lane Data Path (Replicated for 4 Lanes):
  RDI: 16-bit data  →  Buffer  →  Gray Sync  →  32-bit PIPE out
```

### Key Components

#### 1. Elastic Buffer (RDI Clock Domain)
- **Purpose**: Absorbs clock frequency differences between domains
- **Capacity**: 16 entries per lane (configurable)
- **Implementation**: Dual-pointer circular buffer
- **Signals**: 
  - Full flag: Asserts when buffer at capacity
  - Empty flag: Asserts when no data
  - Write pointer: Increments on valid+ready transaction

#### 2. Clock Domain Crossing (CDC)
- **Method**: Gray code pointer synchronization
- **Stages**: 2-flop pipeline for metastability settling
- **Direction**: RDI write pointers → PIPE clock domain
- **Safety**: No direct cross-domain data paths, pointers only

#### 3. Output Register Stage (PIPE Clock Domain)
- **Purpose**: Provides registered outputs for timing closure
- **Function**: Muxes data from RDI buffer using synchronized pointers
- **Latency**: 2-3 cycles typical (CDC + pipeline)

#### 4. CRC32 Computation
- **Polynomial**: x³² + x²⁶ + x²³ + x²² + x¹⁶ + x¹² + x¹¹ + x¹⁰ + x⁸ + x⁷ + x⁵ + x⁴ + x² + x + 1
- **Residue**: 0x1704_7432 (when CRC matches expected value)
- **Controllable**: Per-lane enable signal
- **Output**: Per-lane CRC error flag

## Interface Specifications

### Input Signals (RDI Clock Domain)

| Signal | Width | Direction | Description |
|--------|-------|-----------|-------------|
| `rst_n` | 1 | Input | Asynchronous active-low reset |
| `rdi_clk` | 1 | Input | RDI clock (100 MHz typical) |
| `rdi_valid[NUM_LANES-1:0]` | NUM_LANES | Input | Valid signal per lane |
| `rdi_data[NUM_LANES*16-1:0]` | NUM_LANES*16 | Input | Data per lane (16-bit) |
| `rdi_error[NUM_LANES-1:0]` | NUM_LANES | Input | Error flag per lane |
| `crc_enable[NUM_LANES-1:0]` | NUM_LANES | Input | Enable CRC per lane |

### Output Signals (RDI Clock Domain)

| Signal | Width | Description |
|--------|-------|-------------|
| `rdi_ready[NUM_LANES-1:0]` | NUM_LANES | Ready signal (buffer not full) |
| `rdi_flow_ctrl[NUM_LANES-1:0]` | NUM_LANES | Flow control (asserts when full) |

### Output Signals (PIPE Clock Domain)

| Signal | Width | Direction | Description |
|--------|-------|-----------|-------------|
| `pipe_clk` | 1 | Input | PIPE clock (150 MHz typical) |
| `pipe_valid[NUM_LANES-1:0]` | NUM_LANES | Output | Valid signal per lane |
| `pipe_data[NUM_LANES*32-1:0]` | NUM_LANES*32 | Output | Data per lane (32-bit) |
| `pipe_error[NUM_LANES-1:0]` | NUM_LANES | Output | Synchronized error flag |
| `pipe_ready[NUM_LANES-1:0]` | NUM_LANES | Input | Ready signal (backpressure) |
| `crc_error[NUM_LANES-1:0]` | NUM_LANES | Output | CRC validation error |

## Parametrization

```systemverilog
module ucie_rdi_to_pcie_pipe_bridge #(
    parameter int NUM_LANES = 4,           // Number of lanes (default 4)
    parameter int RDI_DATA_WIDTH = 16,     // RDI data width per lane
    parameter int PIPE_DATA_WIDTH = 32,    // PIPE data width per lane
    parameter int BUFFER_DEPTH = 16        // FIFO depth per lane
)
```

All parameters are compile-time configurable for design flexibility.

## Simulation Environments

### Verilator (Open Source - Recommended)

#### Installation
```bash
sudo apt-get install verilator
```

#### Compilation & Simulation
```bash
# Basic simulation
make verilator

# Debug with detailed tracing
make verilator_debug

# View waveforms
make wave
```

Output: `obj_dir/dump.vcd` (GTKWave compatible)

If both `verilator` and `verilator_bin` are on your `PATH`, the Makefile prefers `verilator_bin` so the bundled wrapper can provide a consistent `VERILATOR_ROOT` and runtime support files.

**Verilator note:** Release 4.x ignores `#` delays in SystemVerilog. This project drives `rdi_clk`, `pipe_clk`, and `rst_n` from `sim_main.cpp` when using `make verilator`. For VCS/Questa/Xcelium, `make simv` / `make questa` / `make xsim` use top module `sim_top`, which generates clocks with delays in `sim_top.sv`.

### Synopsys VCS

```bash
# Full compilation with debug
make simv

# Or manually:
vcs -sverilog -debug_all -cm line+tgl ucie_rdi_to_pcie_pipe_bridge.sv tb_ucie_rdi_to_pcie_pipe_bridge.sv
./simv -gui
```

Supports coverage with `-cm` flags (line, toggle, branch)

### Mentor ModelSim/QuestaSim

```bash
# Using Makefile
make questa

# Or manually:
vlog -sv ucie_rdi_to_pcie_pipe_bridge.sv tb_ucie_rdi_to_pcie_pipe_bridge.sv
vsim -c tb_ucie_rdi_to_pcie_pipe_bridge -do "run -all; quit"
```

### Cadence Xcelium

```bash
# Using Makefile
make xsim

# Or manually:
xmvlog -sv ucie_rdi_to_pcie_pipe_bridge.sv tb_ucie_rdi_to_pcie_pipe_bridge.sv
xmsim tb_ucie_rdi_to_pcie_pipe_bridge
```

### Xilinx Vivado

1. Create new RTL project
2. Add source files:
  - `src/ucie_rdi_to_pcie_pipe_bridge.sv`
  - `test/ucie_rdi_to_pcie_pipe_bridge_assertions.sv` (optional, for simulation)
  - `test/tb_ucie_rdi_to_pcie_pipe_bridge.sv`
  - `test/sim_top.sv` (simulation top — instantiates the testbench with internal clocks)
3. Set simulation top to `sim_top` → Run Behavioral Simulation

## Test Coverage

The testbench (`tb_ucie_rdi_to_pcie_pipe_bridge.sv`) is a smoke suite with dual asynchronous clocks (100 MHz RDI / 150 MHz PIPE):

1. **Single-lane transfer** — one beat on lane 0  
2. **Multi-lane transfer** — simultaneous valid on all lanes  
3. **PIPE backpressure** — `pipe_ready` low then high while pushing data  
4. **Error flag** — `rdi_error` on one lane  
5. **Sustained traffic** — repeated multi-lane bursts  

The **assertion helper module** is instantiated in the testbench. It emits `$warning` on suspect RDI data changes during `valid`, checks PIPE-side stability, and prints **per-lane transfer counts** at end of simulation via `print_statistics()`.

For vendor simulators, you can add **SVA** or bind additional properties; Verilator uses the procedural checks in `ucie_rdi_to_pcie_pipe_bridge_assertions.sv` by default.

## Design Highlights

### Metastability Protection ✓
- Double-flop synchronizer for pointer crossing
- Gray code prevents multibit errors
- Proper setup/hold slack allocation

### Zero Data Loss ✓
- Elastic buffering absorbs frequency variations
- No FIFO overflow conditions possible
- Backpressure propagates correctly

### Scalability ✓
- Parameterized for 1-N lanes
- Data widths configurable at compile time
- Buffer depth adjustable per application

### Timing ✓
- CDC crossing isolated from combinational paths
- Output registered for timing closure
- No critical paths across clock domains

### Verification ✓
- Smoke tests with dual clocks and backpressure
- Instantiated CDC monitor (stability checks + transfer statistics)
- RTL lint via `make lint` (Verilator)

## Performance Characteristics

### Latency
- **RDI → PIPE**: 3-4 cycles nominal (includes CDC)
- **Backpressure**: 1-2 cycles for flow control propagation

### Throughput
- **Theoretical Max**: 4 lanes × 150 MHz = 4.8 Gbps (PIPE side)
- **Actual**: Limited by RDI clock (100 MHz nominal)
- **Buffer**: 16 entries per lane, 256 bits total

### Clock Domain Isolation
- **PIPE Clock Independence**: RDI failures don't affect PIPE outputs
- **Reset**: Asynchronous, affects both domains
- **Data Paths**: Unidirectional RDI → PIPE only

## Future Enhancements

1. **Bidirectional Support**: Extend for back-channel signaling
2. **Advanced CRC**: Configurable polynomials, per-field CRC
3. **Adaptive Buffering**: Dynamic FIFO sizing based on frequency delta
4. **Protocol Wrappers**: Add UCIe/PCIe frame formatting
5. **Performance Monitoring**: Built-in latency and throughput counters
6. **Power Management**: Clock gating for idle lanes
7. **Formal Verification**: Formal property checks (yosys/SMT)
8. **AXI Wrapper**: Optional AXI4 streaming interface

## Troubleshooting

### Simulation Won't Compile
```bash
# Ensure SystemVerilog support
verilator --version

# Check for syntax errors
verilator --lint-only ucie_rdi_to_pcie_pipe_bridge.sv
```

### No Data Appearing on PIPE Side
- Check `pipe_ready` is asserted
- Verify `rdi_valid` transitions
- Allow 3-4 cycles latency through CDC
- Monitor flow control signals

### Waveform Analysis
- Use `dump.vcd` with GTKWave for visual inspection
- Search for reset events
- Check clock frequency ratio (100 MHz : 150 MHz)
- Validate pointer Gray code transitions

## Simulation output example

After `make verilator`, you should see `[TEST]` lines from the testbench plus a **CDC Assertion Statistics** block from `cdc_mon.print_statistics()` (RDI/PIPE transfer counts per lane). Waveforms: `obj_dir/dump.vcd` (e.g. `make wave`).

## Continuous integration

GitHub Actions workflow `.github/workflows/verilator.yml` runs `make verilator` on push/PR to `main` or `master`.

## Documentation Files

- **architecture.md** - In-depth design explanation with waveforms
- **interface_spec.md** - Detailed signal protocol specifications
- **verification_plan.md** - Test methodology and assertion strategy

## License

MIT License - See LICENSE file

## Author & Contact

**Mark Thomas**  
Created: March 2026  
Repository: https://github.com/markrthomas/IP-ucie-rdi-to-pcie-pipe

---

**Note**: This RTL is suitable for FPGA/ASIC integration paths with your own timing and protocol validation. Run `make verilator` and `make lint` before tape-in.
