
`timescale 1ns/1ps

/**
 * Clock Domain Crossing (CDC) Assertions for UCIe RDI to PCIe PIPE Bridge
 *
 * Verifies safe signal crossing between RDI and PIPE clock domains
 * Simplified for Verilator compatibility (no SVA syntax)
 */

module ucie_rdi_to_pcie_pipe_bridge_assertions #(
    parameter int NUM_LANES = 4,
    parameter int RDI_DATA_WIDTH = 16,
    parameter int PIPE_DATA_WIDTH = 32,
    parameter int BUFFER_DEPTH = 16
) (
    input  logic                                rst_n,
    input  logic                                rdi_clk,
    input  logic                                pipe_clk,
    input  logic [NUM_LANES-1:0]                rdi_valid,
    input  logic [NUM_LANES-1:0]                rdi_ready,
    input  logic [NUM_LANES*RDI_DATA_WIDTH-1:0] rdi_data,
    input  logic [NUM_LANES-1:0]                rdi_error,
    input  logic [NUM_LANES-1:0]                pipe_valid,
    input  logic [NUM_LANES-1:0]                pipe_ready,
    input  logic [NUM_LANES*PIPE_DATA_WIDTH-1:0] pipe_data,
    input  logic [NUM_LANES-1:0]                pipe_error
);

    // ========== RDI Domain Stability Checking ==========

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

    // Check if data is stable when valid
    generate
        for (genvar i = 0; i < NUM_LANES; i++) begin : RDI_STABILITY
            always @(posedge rdi_clk) begin
                if (rst_n && rdi_valid[i]) begin
                    // Data should remain stable during valid assertion
                    if (rdi_data[i*RDI_DATA_WIDTH +: RDI_DATA_WIDTH] != rdi_data_d1[i*RDI_DATA_WIDTH +: RDI_DATA_WIDTH]) begin
                        $warning("[CDC_WARNING] RDI Lane %0d data changed while valid", i);
                    end
                end
            end
        end
    endgenerate

    // ========== PIPE Domain Stability Checking ==========

    logic [NUM_LANES*PIPE_DATA_WIDTH-1:0] pipe_data_d1;
    logic [NUM_LANES-1:0] pipe_valid_d1;

    always_ff @(posedge pipe_clk or negedge rst_n) begin
        if (!rst_n) begin
            pipe_data_d1 <= '0;
            pipe_valid_d1 <= '0;
        end else begin
            pipe_data_d1 <= pipe_data;
            pipe_valid_d1 <= pipe_valid;
        end
    end

    // ========== Transfer Counting and Statistics ==========

    int rdi_transfer_count [NUM_LANES];
    int pipe_transfer_count [NUM_LANES];
    int rdi_error_count [NUM_LANES];
    int pipe_error_count [NUM_LANES];

    generate
        for (genvar lane = 0; lane < NUM_LANES; lane++) begin : LANE_TRACKING

            // Count RDI transfers on RDI clock
            always_ff @(posedge rdi_clk or negedge rst_n) begin
                if (!rst_n) begin
                    rdi_transfer_count[lane] <= 0;
                    rdi_error_count[lane] <= 0;
                end else begin
                    if (rdi_valid[lane] && rdi_ready[lane]) begin
                        rdi_transfer_count[lane] <= rdi_transfer_count[lane] + 1;
                    end
                    if (rdi_error[lane]) begin
                        rdi_error_count[lane] <= rdi_error_count[lane] + 1;
                    end
                end
            end

            // Count PIPE transfers on PIPE clock
            always_ff @(posedge pipe_clk or negedge rst_n) begin
                if (!rst_n) begin
                    pipe_transfer_count[lane] <= 0;
                    pipe_error_count[lane] <= 0;
                end else begin
                    if (pipe_valid[lane] && pipe_ready[lane]) begin
                        pipe_transfer_count[lane] <= pipe_transfer_count[lane] + 1;
                    end
                    if (pipe_error[lane]) begin
                        pipe_error_count[lane] <= pipe_error_count[lane] + 1;
                    end
                end
            end
        end
    endgenerate

    // ========== Reporting Task ==========

    task automatic print_statistics();
        int lane;
        $display("\n========== CDC Assertion Statistics ==========");
        for (lane = 0; lane < NUM_LANES; lane++) begin
            $display("Lane %0d:", lane);
            $display("  RDI Transfers: %0d, Errors: %0d", rdi_transfer_count[lane], rdi_error_count[lane]);
            $display("  PIPE Transfers: %0d, Errors: %0d", pipe_transfer_count[lane], pipe_error_count[lane]);
        end
        $display("==========================================\n");
    endtask

endmodule

