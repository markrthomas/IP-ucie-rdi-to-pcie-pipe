
`timescale 1ns/1ps

/**
 * Clock Domain Crossing (CDC) Assertions for UCIe RDI to PCIe PIPE Bridge
 *
 * Verifies safe signal crossing between RDI and PIPE clock domains
 * for both Transmit and Receive paths.
 */
module ucie_rdi_to_pcie_pipe_bridge_assertions #(
    parameter int NUM_LANES = 4,
    parameter int RDI_DATA_WIDTH = 16,
    parameter int PIPE_DATA_WIDTH = 32
) (
    input logic                                rst_n,
    input logic                                rdi_clk,
    input logic                                pipe_clk,

    // Transmit Path (RDI -> Bridge -> PIPE)
    input logic [NUM_LANES-1:0]                rdi_valid,
    input logic [NUM_LANES-1:0]                rdi_ready,
    input logic [NUM_LANES*RDI_DATA_WIDTH-1:0] rdi_data,
    input logic [NUM_LANES-1:0]                rdi_error,
    input logic [NUM_LANES-1:0]                pipe_valid,
    input logic [NUM_LANES-1:0]                pipe_ready,
    input logic [NUM_LANES*PIPE_DATA_WIDTH-1:0] pipe_data,
    input logic [NUM_LANES-1:0]                pipe_error,

    // Receive Path (PIPE -> Bridge -> RDI)
    input logic [NUM_LANES-1:0]                pipe_rx_valid,
    input logic [NUM_LANES-1:0]                pipe_rx_ready,
    input logic [NUM_LANES*PIPE_DATA_WIDTH-1:0] pipe_rx_data,
    input logic [NUM_LANES-1:0]                pipe_rx_error,
    input logic [NUM_LANES-1:0]                rdi_rx_valid,
    input logic [NUM_LANES-1:0]                rdi_rx_ready,
    input logic [NUM_LANES*RDI_DATA_WIDTH-1:0] rdi_rx_data,
    input logic [NUM_LANES-1:0]                rdi_rx_error
);

    // ========== Transmit Path Stability Checking ==========

    logic [NUM_LANES*RDI_DATA_WIDTH-1:0] rdi_data_d1;
    logic [NUM_LANES-1:0] rdi_valid_d1, rdi_error_d1;

    always_ff @(posedge rdi_clk or negedge rst_n) begin
        if (!rst_n) begin
            rdi_data_d1 <= '0;
            rdi_valid_d1 <= '0;
            rdi_error_d1 <= '0;
        end else begin
            rdi_data_d1 <= rdi_data;
            rdi_valid_d1 <= rdi_valid;
            rdi_error_d1 <= rdi_error;
        end
    end

    generate
        for (genvar i = 0; i < NUM_LANES; i++) begin : TX_RDI_STABILITY
            always_ff @(posedge rdi_clk or negedge rst_n) begin
                if (!rst_n) begin
                end else if (rdi_valid[i] && rdi_valid_d1[i]) begin
                    if (rdi_data[i*RDI_DATA_WIDTH +: RDI_DATA_WIDTH] != rdi_data_d1[i*RDI_DATA_WIDTH +: RDI_DATA_WIDTH]) begin
                        $warning("[CDC_WARNING] TX RDI Lane %0d data changed while valid", i);
                    end
                    if (rdi_error[i] != rdi_error_d1[i]) begin
                        $warning("[CDC_WARNING] TX RDI Lane %0d error flag changed while valid", i);
                    end
                end
            end
        end
    endgenerate

    logic [NUM_LANES*PIPE_DATA_WIDTH-1:0] pipe_data_d1;
    logic [NUM_LANES-1:0] pipe_valid_d1, pipe_valid_d2, pipe_error_d1, pipe_ready_d1;

    always_ff @(posedge pipe_clk or negedge rst_n) begin
        if (!rst_n) begin
            pipe_data_d1 <= '0;
            pipe_valid_d1 <= '0;
            pipe_valid_d2 <= '0;
            pipe_error_d1 <= '0;
            pipe_ready_d1 <= '0;
        end else begin
            pipe_data_d1 <= pipe_data;
            pipe_valid_d1 <= pipe_valid;
            pipe_valid_d2 <= pipe_valid_d1;
            pipe_error_d1 <= pipe_error;
            pipe_ready_d1 <= pipe_ready;
        end
    end

    generate
        for (genvar i = 0; i < NUM_LANES; i++) begin : TX_PIPE_STABILITY
            always_ff @(posedge pipe_clk or negedge rst_n) begin
                if (!rst_n) begin
                end else if (pipe_valid[i] && pipe_valid_d1[i] && pipe_valid_d2[i] && !pipe_ready_d1[i]) begin
                    if (pipe_data[i*PIPE_DATA_WIDTH +: PIPE_DATA_WIDTH] != pipe_data_d1[i*PIPE_DATA_WIDTH +: PIPE_DATA_WIDTH]) begin
                        $warning("[CDC_WARNING] TX PIPE Lane %0d data changed while valid and stalled", i);
                    end
                    if (pipe_error[i] != pipe_error_d1[i]) begin
                        $warning("[CDC_WARNING] TX PIPE Lane %0d error flag changed while valid and stalled", i);
                    end
                end
            end
        end
    endgenerate

    // ========== Receive Path Stability Checking ==========

    logic [NUM_LANES*PIPE_DATA_WIDTH-1:0] pipe_rx_data_d1;
    logic [NUM_LANES-1:0] pipe_rx_valid_d1, pipe_rx_error_d1;

    always_ff @(posedge pipe_clk or negedge rst_n) begin
        if (!rst_n) begin
            pipe_rx_data_d1 <= '0;
            pipe_rx_valid_d1 <= '0;
            pipe_rx_error_d1 <= '0;
        end else begin
            pipe_rx_data_d1 <= pipe_rx_data;
            pipe_rx_valid_d1 <= pipe_rx_valid;
            pipe_rx_error_d1 <= pipe_rx_error;
        end
    end

    generate
        for (genvar i = 0; i < NUM_LANES; i++) begin : RX_PIPE_STABILITY
            always_ff @(posedge pipe_clk or negedge rst_n) begin
                if (!rst_n) begin
                end else if (pipe_rx_valid[i] && pipe_rx_valid_d1[i]) begin
                    if (pipe_rx_data[i*PIPE_DATA_WIDTH +: PIPE_DATA_WIDTH] != pipe_rx_data_d1[i*PIPE_DATA_WIDTH +: PIPE_DATA_WIDTH]) begin
                        $warning("[CDC_WARNING] RX PIPE Lane %0d data changed while valid", i);
                    end
                    if (pipe_rx_error[i] != pipe_rx_error_d1[i]) begin
                        $warning("[CDC_WARNING] RX PIPE Lane %0d error flag changed while valid", i);
                    end
                end
            end
        end
    endgenerate

    logic [NUM_LANES*RDI_DATA_WIDTH-1:0] rdi_rx_data_d1;
    logic [NUM_LANES-1:0] rdi_rx_valid_d1, rdi_rx_valid_d2, rdi_rx_error_d1, rdi_rx_ready_d1;

    always_ff @(posedge rdi_clk or negedge rst_n) begin
        if (!rst_n) begin
            rdi_rx_data_d1 <= '0;
            rdi_rx_valid_d1 <= '0;
            rdi_rx_valid_d2 <= '0;
            rdi_rx_error_d1 <= '0;
            rdi_rx_ready_d1 <= '0;
        end else begin
            rdi_rx_data_d1 <= rdi_rx_data;
            rdi_rx_valid_d1 <= rdi_rx_valid;
            rdi_rx_valid_d2 <= rdi_rx_valid_d1;
            rdi_rx_error_d1 <= rdi_rx_error;
            rdi_rx_ready_d1 <= rdi_rx_ready;
        end
    end

    generate
        for (genvar i = 0; i < NUM_LANES; i++) begin : RX_RDI_STABILITY
            always_ff @(posedge rdi_clk or negedge rst_n) begin
                if (!rst_n) begin
                end else if (rdi_rx_valid[i] && rdi_rx_valid_d1[i] && rdi_rx_valid_d2[i] && !rdi_rx_ready_d1[i]) begin
                    if (rdi_rx_data[i*RDI_DATA_WIDTH +: RDI_DATA_WIDTH] != rdi_rx_data_d1[i*RDI_DATA_WIDTH +: RDI_DATA_WIDTH]) begin
                        $warning("[CDC_WARNING] RX RDI Lane %0d data changed while valid and stalled", i);
                    end
                    if (rdi_rx_error[i] != rdi_rx_error_d1[i]) begin
                        $warning("[CDC_WARNING] RX RDI Lane %0d error flag changed while valid and stalled", i);
                    end
                end
            end
        end
    endgenerate

    // ========== Transfer Counting and Statistics ==========

    int tx_rdi_count [NUM_LANES];
    int tx_pipe_count [NUM_LANES];
    int rx_pipe_count [NUM_LANES];
    int rx_rdi_count [NUM_LANES];

    always_ff @(posedge rdi_clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < NUM_LANES; i++) begin
                tx_rdi_count[i] <= 0;
                rx_rdi_count[i] <= 0;
            end
        end else begin
            for (int i = 0; i < NUM_LANES; i++) begin
                if (rdi_valid[i] && rdi_ready[i]) tx_rdi_count[i] <= tx_rdi_count[i] + 1;
                if (rdi_rx_valid[i] && rdi_rx_ready[i]) rx_rdi_count[i] <= rx_rdi_count[i] + 1;
            end
        end
    end

    always_ff @(posedge pipe_clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < NUM_LANES; i++) begin
                tx_pipe_count[i] <= 0;
                rx_pipe_count[i] <= 0;
            end
        end else begin
            for (int i = 0; i < NUM_LANES; i++) begin
                if (pipe_valid[i] && pipe_ready[i]) tx_pipe_count[i] <= tx_pipe_count[i] + 1;
                if (pipe_rx_valid[i] && pipe_rx_ready[i]) rx_pipe_count[i] <= rx_pipe_count[i] + 1;
            end
        end
    end

    task automatic print_statistics();
        $display("\n========== CDC Assertion Statistics ==========");
        for (int lane = 0; lane < NUM_LANES; lane++) begin
            $display("Lane %0d:", lane);
            $display("  TX: RDI Transfers: %0d, PIPE Transfers: %0d", tx_rdi_count[lane], tx_pipe_count[lane]);
            $display("  RX: PIPE Transfers: %0d, RDI Transfers: %0d", rx_pipe_count[lane], rx_rdi_count[lane]);
        end
        $display("==========================================\n");
    endtask

endmodule
