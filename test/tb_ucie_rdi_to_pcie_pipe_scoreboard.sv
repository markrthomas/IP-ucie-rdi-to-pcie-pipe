
`timescale 1ns/1ps

/**
 * Reference scoreboard for Bidirectional UCIe RDI to PCIe PIPE Bridge.
 * 
 * Each RDI/PIPE accepted beat (per lane, per direction) is queued and matched.
 */
module tb_ucie_rdi_to_pcie_pipe_scoreboard #(
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
    /* verilator lint_off UNUSEDSIGNAL */
    input logic [NUM_LANES*PIPE_DATA_WIDTH-1:0] pipe_rx_data,
    /* verilator lint_on UNUSEDSIGNAL */
    input logic [NUM_LANES-1:0]                pipe_rx_error,
    input logic [NUM_LANES-1:0]                rdi_rx_valid,
    input logic [NUM_LANES-1:0]                rdi_rx_ready,
    input logic [NUM_LANES*RDI_DATA_WIDTH-1:0] rdi_rx_data,
    input logic [NUM_LANES-1:0]                rdi_rx_error
);

    typedef struct packed {
        logic [PIPE_DATA_WIDTH-1:0] data;
        logic error;
    } score_entry_t;

    // Queues for Tx (Forward) path and Rx (Reverse) path
    score_entry_t tx_exp_q[NUM_LANES][$];
    score_entry_t rx_exp_q[NUM_LANES][$];

    genvar lane;
    generate
        for (lane = 0; lane < NUM_LANES; lane++) begin : LANE_SB

            // --- Transmit Path Queueing (RDI CLK posedge) ---
            always_ff @(posedge rdi_clk) begin
                if (!rst_n) begin
                    tx_exp_q[lane].delete();
                end else begin
                    if (rdi_valid[lane] && rdi_ready[lane]) begin
                        automatic score_entry_t entry = '{
                            data: {{(PIPE_DATA_WIDTH-RDI_DATA_WIDTH){1'b0}}, 
                                   rdi_data[lane*RDI_DATA_WIDTH +: RDI_DATA_WIDTH]},
                            error: rdi_error[lane]
                        };
                        tx_exp_q[lane].push_back(entry);
                    end
                end
            end

            // --- Transmit Path Comparison (PIPE CLK posedge) ---
            // Note: Since hardware outputs are registered, we sample at posedge
            // and Verilog ensures we see the value from the PREVIOUS cycle.
            always_ff @(posedge pipe_clk) begin
                if (rst_n) begin
                    if (pipe_valid[lane] && pipe_ready[lane]) begin
                        automatic score_entry_t got = '{
                            data: pipe_data[lane*PIPE_DATA_WIDTH +: PIPE_DATA_WIDTH],
                            error: pipe_error[lane]
                        };
                        if (tx_exp_q[lane].size() == 0) begin
                            $fatal(1, "[SCOREBOARD] TX Lane %0d unexpected PIPE beat at time %0t", lane, $time);
                        end else begin
                            automatic score_entry_t exp = tx_exp_q[lane].pop_front();
                            if (got !== exp) begin
                                $fatal(1, "[SCOREBOARD] TX Lane %0d data mismatch exp=%h got=%h (err_exp=%b got=%b) at time %0t",
                                       lane, exp.data, got.data, exp.error, got.error, $time);
                            end
                        end
                    end
                end
            end

            // --- Receive Path Queueing (PIPE CLK posedge) ---
            always_ff @(posedge pipe_clk) begin
                if (!rst_n) begin
                    rx_exp_q[lane].delete();
                end else begin
                    if (pipe_rx_valid[lane] && pipe_rx_ready[lane]) begin
                        automatic score_entry_t entry = '{
                            data: {{(PIPE_DATA_WIDTH-RDI_DATA_WIDTH){1'b0}},
                                   pipe_rx_data[lane*PIPE_DATA_WIDTH +: RDI_DATA_WIDTH]},
                            error: pipe_rx_error[lane]
                        };
                        rx_exp_q[lane].push_back(entry);
                    end
                end
            end

            // --- Receive Path Comparison (RDI CLK posedge) ---
            always_ff @(posedge rdi_clk) begin
                if (rst_n) begin
                    if (rdi_rx_valid[lane] && rdi_rx_ready[lane]) begin
                        automatic score_entry_t got = '{
                            data: {{(PIPE_DATA_WIDTH-RDI_DATA_WIDTH){1'b0}},
                                   rdi_rx_data[lane*RDI_DATA_WIDTH +: RDI_DATA_WIDTH]},
                            error: rdi_rx_error[lane]
                        };
                        if (rx_exp_q[lane].size() == 0) begin
                            $fatal(1, "[SCOREBOARD] RX Lane %0d unexpected RDI beat at time %0t", lane, $time);
                        end else begin
                            automatic score_entry_t exp = rx_exp_q[lane].pop_front();
                            if (got !== exp) begin
                                $fatal(1, "[SCOREBOARD] RX Lane %0d data mismatch exp=%h got=%h (err_exp=%b got=%b) at time %0t",
                                       lane, exp.data, got.data, exp.error, got.error, $time);
                            end
                        end
                    end
                end
            end

        end
    endgenerate

    task automatic final_check();
        for (int ln = 0; ln < NUM_LANES; ln++) begin
            if (tx_exp_q[ln].size() != 0) begin
                $fatal(1, "[SCOREBOARD] TX Lane %0d failed to drain: %0d beats left",
                       ln, tx_exp_q[ln].size());
            end
            if (rx_exp_q[ln].size() != 0) begin
                $fatal(1, "[SCOREBOARD] RX Lane %0d failed to drain: %0d beats left",
                       ln, rx_exp_q[ln].size());
            end
        end
        $display("[SCOREBOARD] PASS — all lanes and directions drained; data and error matched.");
    endtask

endmodule
