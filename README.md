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
