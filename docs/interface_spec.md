
# Interface Specifications

## Signal Details

### RDI Clock Domain Signals

All signals are in RDI clock domain (100 MHz typical).

#### Inputs
- `rdi_valid[3:0]`: Lane valid indicators (4 bits, one per lane)
- `rdi_data[63:0]`: Lane data bus (64 bits = 4 lanes × 16 bits)
- `rdi_error[3:0]`: Lane error flags (4 bits)
- `crc_enable[3:0]`: CRC enable per lane (4 bits)

#### Outputs  
- `rdi_ready[3:0]`: Lane ready (buffer not full)
- `rdi_flow_ctrl[3:0]`: Flow control (buffer full indicator)

### PIPE Clock Domain Signals

All signals are in PIPE clock domain (150 MHz typical).

#### Inputs
- `pipe_ready[3:0]`: Lane ready from downstream (backpressure)
- `pipe_clk`: PIPE clock input

#### Outputs
- `pipe_valid[3:0]`: Lane valid indicators
- `pipe_data[127:0]`: Lane data bus (128 bits = 4 lanes × 32 bits)
- `pipe_error[3:0]`: Synchronized error flags
- `crc_error[3:0]`: CRC validation errors

## Timing Specifications

| Parameter | Value | Notes |
|-----------|-------|-------|
| RDI Clock | 100 MHz | Typical frequency |
| PIPE Clock | 150 MHz | Typical frequency |
| CDC Latency | 2-3 cycles | Includes synchronization |
| Output Latency | 1 cycle | From FIFO read |
| Setup Time | 0.5 ns | Data to clock |
| Hold Time | 0.2 ns | Data to clock |
| CDC Settling | 3 ns @ PIPE clk | Min for metastability |

## Protocol Rules

### Valid/Ready Handshaking
- Data transfers only when both valid and ready asserted
- Data must be stable during entire valid pulse
- Ready can be asserted/deasserted asynchronously
- Backpressure propagates within 2 cycles

### Error Handling
- Errors synchronized using double-flop
- Error flag valid same cycle as error data
- CRC error computed combinationally from output
- Errors do not block data transmission

### CRC Operation
- Enable CRC32 computation with `crc_enable`
- CRC is updated on PIPE clock when `crc_enable` and output-side activity apply (see RTL)
- **Note:** The current RTL uses a **demo** residue check (`0x1704_7432`) against a running CRC register, not a full PCIe packet CRC contract. Replace with protocol-specific checking for production use.

