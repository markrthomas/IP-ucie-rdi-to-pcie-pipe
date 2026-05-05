
`timescale 1ns/1ps

/**
 * UCIe RDI to PCIe PIPE Bridge with Bidirectional Support
 *
 * Converts UCIe 1.0 RDI (Reduced Die-to-Die Interface) to PCIe Gen 4 PIPE
 * Supports 4 lanes on each interface with dual clock domain handling.
 *
 * Features:
 * - Bidirectional data path (TX: RDI->PIPE, RX: PIPE->RDI)
 * - Dual clock domain crossing (RDI clock <-> PIPE clock)
 * - Elastic buffers for frequency variation support
 * - CRC/error handling on TX path
 * - Parameterized design for extensibility
 */

module ucie_rdi_to_pcie_pipe_bridge #(
    parameter int NUM_LANES = 4,
    parameter int RDI_DATA_WIDTH = 16,
    parameter int PIPE_DATA_WIDTH = 32,
    parameter int BUFFER_DEPTH = 16
) (
    input  logic                                rst_n,
    input  logic                                rdi_clk,

    // RDI TX interface (RDI -> Bridge -> PIPE)
    input  logic [NUM_LANES-1:0]                rdi_valid,
    output logic [NUM_LANES-1:0]                rdi_ready,
    input  logic [NUM_LANES*RDI_DATA_WIDTH-1:0] rdi_data,
    input  logic [NUM_LANES-1:0]                rdi_error,
    output logic [NUM_LANES-1:0]                rdi_flow_ctrl,

    // PIPE TX interface (RDI -> Bridge -> PIPE)
    input  logic                                pipe_clk,
    output logic [NUM_LANES-1:0]                pipe_valid,
    input  logic [NUM_LANES-1:0]                pipe_ready,
    output logic [NUM_LANES*PIPE_DATA_WIDTH-1:0] pipe_data,
    output logic [NUM_LANES-1:0]                pipe_error,

    // RDI RX interface (PIPE -> Bridge -> RDI)
    output logic [NUM_LANES-1:0]                rdi_rx_valid,
    input  logic [NUM_LANES-1:0]                rdi_rx_ready,
    output logic [NUM_LANES*RDI_DATA_WIDTH-1:0] rdi_rx_data,
    output logic [NUM_LANES-1:0]                rdi_rx_error,

    // PIPE RX interface (PIPE -> Bridge -> RDI)
    input  logic [NUM_LANES-1:0]                pipe_rx_valid,
    output logic [NUM_LANES-1:0]                pipe_rx_ready,
    input  logic [NUM_LANES*PIPE_DATA_WIDTH-1:0] pipe_rx_data,
    input  logic [NUM_LANES-1:0]                pipe_rx_error,

    output logic [NUM_LANES-1:0]                crc_error,
    input  logic [NUM_LANES-1:0]                crc_enable
);

    genvar lane;
    generate
        for (lane = 0; lane < NUM_LANES; lane++) begin : BRIDGE_LANE

            // --- Transmit Path (RDI -> PIPE) ---
            logic tx_full;
            assign rdi_flow_ctrl[lane] = tx_full;

            ucie_rdi_fifo_cdc #(
                .INPUT_DATA_WIDTH(RDI_DATA_WIDTH),
                .OUTPUT_DATA_WIDTH(PIPE_DATA_WIDTH),
                .BUFFER_DEPTH(BUFFER_DEPTH)
            ) tx_fifo (
                .rst_n(rst_n),
                .wr_clk(rdi_clk),
                .wr_valid(rdi_valid[lane]),
                .wr_ready(rdi_ready[lane]),
                .wr_data(rdi_data[lane*RDI_DATA_WIDTH +: RDI_DATA_WIDTH]),
                .wr_error(rdi_error[lane]),
                .wr_full(tx_full),
                .rd_clk(pipe_clk),
                .rd_valid(pipe_valid[lane]),
                .rd_ready(pipe_ready[lane]),
                .rd_data(pipe_data[lane*PIPE_DATA_WIDTH +: PIPE_DATA_WIDTH]),
                .rd_error(pipe_error[lane])
            );

            // --- Receive Path (PIPE -> RDI) ---
            /* verilator lint_off UNUSEDSIGNAL */
            logic rx_full;
            /* verilator lint_on UNUSEDSIGNAL */
            ucie_rdi_fifo_cdc #(
                .INPUT_DATA_WIDTH(PIPE_DATA_WIDTH),
                .OUTPUT_DATA_WIDTH(RDI_DATA_WIDTH),
                .BUFFER_DEPTH(BUFFER_DEPTH)
            ) rx_fifo (
                .rst_n(rst_n),
                .wr_clk(pipe_clk),
                .wr_valid(pipe_rx_valid[lane]),
                .wr_ready(pipe_rx_ready[lane]),
                .wr_data(pipe_rx_data[lane*PIPE_DATA_WIDTH +: PIPE_DATA_WIDTH]),
                .wr_error(pipe_rx_error[lane]),
                .wr_full(rx_full), 
                .rd_clk(rdi_clk),
                .rd_valid(rdi_rx_valid[lane]),
                .rd_ready(rdi_rx_ready[lane]),
                .rd_data(rdi_rx_data[lane*RDI_DATA_WIDTH +: RDI_DATA_WIDTH]),
                .rd_error(rdi_rx_error[lane])
            );

            // --- CRC Logic (on TX path) ---
            logic [31:0] crc_result;
            always_ff @(posedge pipe_clk or negedge rst_n) begin
                if (!rst_n) begin
                    crc_result <= 32'hFFFF_FFFF;
                end else if (crc_enable[lane] && pipe_valid[lane] && pipe_ready[lane]) begin
                    crc_result <= compute_crc32(pipe_data[lane*PIPE_DATA_WIDTH +: PIPE_DATA_WIDTH], crc_result);
                end else if (!crc_enable[lane]) begin
                    crc_result <= 32'hFFFF_FFFF;
                end
            end

            assign crc_error[lane] = (crc_result == 32'h1704_7432) ? 1'b0 : (crc_enable[lane] ? 1'b1 : 1'b0);

            function automatic logic [31:0] compute_crc32(
                input logic [PIPE_DATA_WIDTH-1:0] data_in,
                input logic [31:0] crc_in
            );
                logic [31:0] crc_temp;
                logic fb;
                crc_temp = crc_in;
                for (int i = 0; i < PIPE_DATA_WIDTH; i++) begin
                    fb = crc_temp[31] ^ data_in[i];
                    crc_temp = crc_temp << 1;
                    if (fb) crc_temp = crc_temp ^ 32'h04C1_1DB7;
                end
                return crc_temp;
            endfunction

        end : BRIDGE_LANE
    endgenerate

endmodule
