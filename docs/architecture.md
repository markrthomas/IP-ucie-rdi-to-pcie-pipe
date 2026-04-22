
# Architecture Documentation

## Detailed Design Overview

### Clock Domains

The bridge manages two independent clock domains:

- **RDI Clock Domain**: 100 MHz (typical), includes write-side elastic buffer
- **PIPE Clock Domain**: 150 MHz (typical), includes read-side output registers

### Data Flow Pipeline

1. **RDI Input Stage** (RDI CLK)
   - Valid signal indicates incoming data
   - Data latched into elastic FIFO
   - Ready output indicates buffer availability

2. **CDC Synchronization** (Async)
   - Gray-coded **write** pointer (RDI → PIPE) synchronized via double flops on `pipe_clk`
   - Gray-coded **read** pointer (PIPE → RDI) synchronized via double flops on `rdi_clk`, converted to binary for **full** / `rdi_ready` on the writer side
   - No combinational data paths across domains (pointer synchronization only)

3. **PIPE Output Stage** (PIPE CLK)
   - Data multiplexed from synchronized pointer
   - CRC32 computed on output data
   - Error flags from RDI domain propagated

### Per-Lane Isolation

Each of the 4 lanes operates independently:
- Dedicated FIFO per lane (no cross-lane interference)
- Isolated ready/valid handshaking
- Independent error and CRC flags
- Parallel data paths for full throughput

