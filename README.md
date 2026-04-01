
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
✅ **SVA Assertions**: Comprehensive CDC verification assertions  
✅ **Verilator Compatible**: Clean SystemVerilog with no vendor-specific constructs  

## Project Structure

```
IP-ucie-rdi-to-pcie-pipe/
├── ucie_rdi_to_pcie_pipe_bridge.sv              # Main RTL design with CRC
├── ucie_rdi_to_pcie_pipe_bridge_assertions.sv   # CDC assertions and coverage
├── tb_ucie_rdi_to_pcie_pipe_bridge.sv           # Comprehensive testbench
├── Makefile                                      # Multi-simulator support
├── README.md                                     # This file
├── LICENSE                                       # MIT License
└── docs/
    ├── architecture.md                           # Detailed design documentation
    ├── interface_spec.md                         # Signal specifications
    └── verification_plan.md                      # Test and assertion strategy
```

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
   - `ucie_rdi_to_pcie_pipe_bridge.sv`
   - `ucie_rdi_to_pcie_pipe_bridge_assertions.sv` (optional, for simulation)
   - `tb_ucie_rdi_to_pcie_pipe_bridge.sv` (as simulation source)
3. Run Simulation → Run Behavioral Simulation

## Test Coverage

The comprehensive testbench includes:

### Test 1: Reset Sequence
- Verifies proper initialization of all internal state
- Checks flow control and valid signals post-reset

### Test 2: Basic Single Lane Transfer
- Single lane data transfer validation
- Ready signal assertion verification

### Test 3: Multi-Lane with Flow Control
- Simultaneous 4-lane transfers
- Backpressure handling when PIPE not ready
- Flow control signal assertion

### Test 4: Sustained Traffic (1000 cycles)
- Continuous data flow on all lanes
- Error injection at predetermined cycles
- Transfer count validation per lane

### Test 5: CRC Functionality
- Configurable per-lane CRC enable
- CRC32 polynomial computation
- CRC error flag generation

### Test 6: Error Propagation
- RDI error signal injection
- Cross-domain synchronization verification
- Error flag propagation to PIPE side

### Test 7: Clock Domain Crossing
- Stress testing with frequency difference (100 MHz vs 150 MHz)
- 200-cycle pattern transmission
- Data integrity verification post-CDC

## SVA Assertions

The design includes comprehensive assertions for:

### CDC Safety
- Data stability during valid cycles
- Ready signal proper synchronization
- No direct combinational cross-domain paths
- Pointer Gray code validity

### Protocol Compliance
- Valid/ready handshaking rules
- Error signal synchronization
- Output stability when valid

### Coverage Goals
- Transfer monitoring per lane
- Error injection coverage
- Clock domain crossing coverage

Run assertions with:
```bash
# VCS with assertions
vcs -sverilog +define+ASSERT_ON ucie_rdi_to_pcie_pipe_bridge.sv tb_ucie_rdi_to_pcie_pipe_bridge.sv

# Verilator with SVA
verilator --assert -cc ucie_rdi_to_pcie_pipe_bridge.sv
```

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
- 7 comprehensive test scenarios
- SVA assertions for functional correctness
- Coverage tracking for all signals
- Error injection capability

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

## Simulation Statistics Example

```
========== UCIe RDI to PCIe PIPE Bridge Testbench ==========
[TB] Reset released at t=20000

[TEST 1] Reset Sequence Verification
  [PASS] RDI flow control deasserted after reset
  [PASS] PIPE valid deasserted after reset

[TEST 2] Basic Single Lane Transfer
  [PASS] Lane 0 ready signal asserted

[TEST 3] Multi-lane Transfer with Flow Control
  [INFO] RDI transfers per lane:
    Lane 0: 97 transfers
    Lane 1: 97 transfers
    Lane 2: 97 transfers
    Lane 3: 97 transfers
  [PASS] Flow control signals asserted when PIPE not ready

[TEST 4] Sustained Traffic Pattern (1000 cycles)
  [INFO] Error injected on Lane 0 at cycle 250
  [INFO] Error injected on Lane 0 at cycle 500
  [INFO] Error injected on Lane 0 at cycle 750
  [INFO] RDI transfers per lane:
    Lane 0: 997 transfers, 3 errors
    Lane 1: 997 transfers, 0 errors
    Lane 2: 997 transfers, 0 errors
    Lane 3: 997 transfers, 0 errors

[TEST 7] Clock Domain Crossing Verification
  [INFO] CDC test pattern transmitted and received

========== Test Statistics ==========
Total Simulation Time: 21000000
======================================
```

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

**Note**: This is a production-grade design suitable for implementation in ASICs and FPGAs. All code is synthesizable and follows HDL best practices.

# UCIe RDI to PCIe PIPE Bridge

A high-performance SystemVerilog bridge that converts UCIe 1.0 RDI (Reduced Die-to-Die Interface) signals to PCIe Gen 4 PIPE (Physical Interface) signals.

## Overview

This bridge provides:
- **Unidirectional conversion** from UCIe RDI to PCIe PIPE protocols
- **4-lane support** on both interfaces (configurable via parameters)
- **Dual clock domain** handling with proper synchronization
- **Elastic buffering** to support frequency variations between RDI and PIPE clock domains
- **CRC/Error handling** with proper flow control mechanisms
- **Parameterized design** for flexibility and extensibility
- **Verilator compatible** for simulation and verification

## Architecture

### Key Components

1. **Per-Lane Elastic Buffers**: Independent FIFO buffers for each of the 4 lanes in the RDI clock domain
2. **Clock Domain Crossing**: Gray code pointer synchronization between RDI and PIPE clock domains
3. **Output Buffers**: PIPE clock domain output buffers with ready/valid handshaking
4. **Flow Control**: Backpressure signaling through `rdi_flow_ctrl` when buffers are full
5. **Error Propagation**: CRC and error signals are synchronized across clock domains

### Interface Signals

#### UCIe RDI Side (Source)
- `rdi_clk`: Source clock (100 MHz typical)
- `rdi_valid[NUM_LANES-1:0]`: Valid data on each lane
- `rdi_ready[NUM_LANES-1:0]`: Ready to accept data (from bridge)
- `rdi_data[NUM_LANES*RDI_DATA_WIDTH-1:0]`: 16-bit data per lane
- `rdi_error[NUM_LANES-1:0]`: Error indicator per lane
- `rdi_flow_ctrl[NUM_LANES-1:0]`: Flow control (asserted when buffer full)

#### PCIe PIPE Side (Sink)
- `pipe_clk`: Sink clock (150 MHz typical)
- `pipe_valid[NUM_LANES-1:0]`: Valid data on each lane
- `pipe_ready[NUM_LANES-1:0]`: Downstream ready to accept
- `pipe_data[NUM_LANES*PIPE_DATA_WIDTH-1:0]`: 32-bit data per lane (Gen 4)
- `pipe_error[NUM_LANES-1:0]`: Error indicator per lane

## File Structure

```
IP-ucie-rdi-to-pcie-pipe/
├── ucie_rdi_to_pcie_pipe_bridge.sv    # Main bridge RTL
├── tb_ucie_rdi_to_pcie_pipe_bridge.sv # Testbench
└── README.md                           # This file
```

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `NUM_LANES` | 4 | Number of parallel lanes |
| `RDI_DATA_WIDTH` | 16 | UCIe RDI data width per lane (bits) |
| `PIPE_DATA_WIDTH` | 32 | PCIe PIPE data width per lane (bits) |
| `BUFFER_DEPTH` | 16 | Elastic buffer depth per lane |

## Running the Testbench

### Prerequisites
- Verilator (recommended for simulation)
- SystemVerilog compiler (e.g., Vivado, VCS, QuestaSim)

### Simulation with Verilator
```bash
verilator --cc -sv --trace tb_ucie_rdi_to_pcie_pipe_bridge.sv ucie_rdi_to_pcie_pipe_bridge.sv
cd obj_dir
make -f Vtb_ucie_rdi_to_pcie_pipe_bridge.mk
./Vtb_ucie_rdi_to_pcie_pipe_bridge
```

### Simulation with Other Tools
```bash
# Example with Vivado Simulator (xsim)
xvlog -sv ucie_rdi_to_pcie_pipe_bridge.sv tb_ucie_rdi_to_pcie_pipe_bridge.sv
xelab tb_ucie_rdi_to_pcie_pipe_bridge
xsim tb_ucie_rdi_to_pcie_pipe_bridge -gui
```

## Testbench Features

The basic testbench (`tb_ucie_rdi_to_pcie_pipe_bridge.sv`) includes:

1. **Dual Clock Generation**: Separate clocks for RDI (100 MHz) and PIPE (150 MHz)
2. **Test 1 - Basic Data Transfer**: Sends data on all 4 lanes with proper handshaking
3. **Test 2 - Flow Control**: Tests backpressure by deasserting PIPE ready and injecting errors
4. **Test 3 - Sustained Traffic**: Exercises the bridge with continuous data transfers
5. **Monitoring**: Real-time reporting of transfers and debug information

## Design Highlights

### Clock Domain Crossing
- Gray code pointer synchronization for safe CDC (Clock Domain Crossing)
- Double-flop synchronizers (2-FF) for metastability hardening
- Independent synchronization paths for read and write pointers

### Flow Control
- Ready/valid handshaking on both interfaces
- `rdi_flow_ctrl` asserted when elastic buffer becomes full
- Automatic backpressure propagation

### Error Handling
- Per-lane error indicators
- Error signals synchronized across clock domains
- Errors propagate transparently through the bridge

## Future Enhancements

- [ ] Data width adaptation logic (16-bit to 32-bit conversion with packing)
- [ ] CRC computation and verification
- [ ] Performance counters and statistics
- [ ] Protocol-specific signal mapping (e.g., lane polarity, training signals)
- [ ] Comprehensive verification test suite
- [ ] Power and performance analysis

## License

MIT License - See LICENSE file for details

## Author

markrthomas
