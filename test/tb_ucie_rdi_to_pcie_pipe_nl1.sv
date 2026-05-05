
`timescale 1ns/1ps

/**
 * Minimal smoke testbench with NUM_LANES=1 (parameter compile check).
 * Uses assertions only — dual-clock scoreboard checks stay on the main TB (same eval stepping).
 */
module tb_ucie_rdi_to_pcie_pipe_nl1 (
    input logic rdi_clk,
    input logic pipe_clk,
    input logic rst_n
);

    localparam int NUM_LANES = 1;
    localparam int RDI_DATA_WIDTH = 16;
    localparam int PIPE_DATA_WIDTH = 32;
    localparam int BUFFER_DEPTH = 16;

    /* verilator lint_off UNUSEDSIGNAL */
    logic [NUM_LANES-1:0] rdi_valid, rdi_error, rdi_flow_ctrl;
    wire [NUM_LANES-1:0] rdi_ready;
    logic [NUM_LANES*RDI_DATA_WIDTH-1:0] rdi_data;
    logic [NUM_LANES-1:0] pipe_valid, pipe_ready, pipe_error, crc_error, crc_enable;
    logic [NUM_LANES*PIPE_DATA_WIDTH-1:0] pipe_data;

    // Receive path signals
    logic [NUM_LANES-1:0] rdi_rx_valid, rdi_rx_error, rdi_rx_ready;
    logic [NUM_LANES*RDI_DATA_WIDTH-1:0] rdi_rx_data;
    logic [NUM_LANES-1:0] pipe_rx_valid, pipe_rx_error;
    wire [NUM_LANES-1:0] pipe_rx_ready;
    logic [NUM_LANES*PIPE_DATA_WIDTH-1:0] pipe_rx_data;
    /* verilator lint_on UNUSEDSIGNAL */

    logic [31:0] rdi_cycle;

    ucie_rdi_to_pcie_pipe_bridge #(
        .NUM_LANES(NUM_LANES),
        .RDI_DATA_WIDTH(RDI_DATA_WIDTH),
        .PIPE_DATA_WIDTH(PIPE_DATA_WIDTH),
        .BUFFER_DEPTH(BUFFER_DEPTH)
    ) dut (
        .rst_n(rst_n),
        .rdi_clk(rdi_clk),
        .rdi_valid(rdi_valid),
        .rdi_ready(rdi_ready),
        .rdi_data(rdi_data),
        .rdi_error(rdi_error),
        .rdi_flow_ctrl(rdi_flow_ctrl),
        .pipe_clk(pipe_clk),
        .pipe_valid(pipe_valid),
        .pipe_ready(pipe_ready),
        .pipe_data(pipe_data),
        .pipe_error(pipe_error),
        .rdi_rx_valid(rdi_rx_valid),
        .rdi_rx_ready(rdi_rx_ready),
        .rdi_rx_data(rdi_rx_data),
        .rdi_rx_error(rdi_rx_error),
        .pipe_rx_valid(pipe_rx_valid),
        .pipe_rx_ready(pipe_rx_ready),
        .pipe_rx_data(pipe_rx_data),
        .pipe_rx_error(pipe_rx_error),
        .crc_error(crc_error),
        .crc_enable(crc_enable)
    );

    ucie_rdi_to_pcie_pipe_bridge_assertions #(
        .NUM_LANES(NUM_LANES),
        .RDI_DATA_WIDTH(RDI_DATA_WIDTH),
        .PIPE_DATA_WIDTH(PIPE_DATA_WIDTH)
    ) cdc_mon (
        .rst_n(rst_n),
        .rdi_clk(rdi_clk),
        .pipe_clk(pipe_clk),
        .rdi_valid(rdi_valid),
        .rdi_ready(rdi_ready),
        .rdi_data(rdi_data),
        .rdi_error(rdi_error),
        .pipe_valid(pipe_valid),
        .pipe_ready(pipe_ready),
        .pipe_data(pipe_data),
        .pipe_error(pipe_error),
        .pipe_rx_valid(pipe_rx_valid),
        .pipe_rx_ready(pipe_rx_ready),
        .pipe_rx_data(pipe_rx_data),
        .pipe_rx_error(pipe_rx_error),
        .rdi_rx_valid(rdi_rx_valid),
        .rdi_rx_ready(rdi_rx_ready),
        .rdi_rx_data(rdi_rx_data),
        .rdi_rx_error(rdi_rx_error)
    );

    always_ff @(posedge rdi_clk or negedge rst_n) begin
        if (!rst_n) begin
            rdi_cycle <= '0;
            rdi_valid <= '0;
            rdi_data <= '0;
            rdi_error <= '0;
            crc_enable <= '0;
            pipe_ready <= '1;
            // RX path defaults
            rdi_rx_ready <= '1;
            pipe_rx_valid <= '0;
            pipe_rx_data <= '0;
            pipe_rx_error <= '0;
        end else if (rdi_cycle == 32'd200) begin
            cdc_mon.print_statistics();
            $display("[TEST NL1] NUM_LANES=1 smoke complete (assertions-only; no scoreboard)");
            $finish;
        end else begin
            unique case (rdi_cycle)
                32'd1: $display("[TEST NL1] Starting NUM_LANES=1 smoke");
                32'd8: begin
                    rdi_valid <= 1'b1;
                    rdi_data[RDI_DATA_WIDTH-1:0] <= 16'hBEEF;
                end
                32'd10: rdi_valid <= 1'b0;
                32'd22: begin
                    rdi_valid <= 1'b1;
                    rdi_data[RDI_DATA_WIDTH-1:0] <= 16'h1234;
                end
                32'd24: rdi_valid <= 1'b0;
                
                // Deep push / wrap-around test
                32'd40: begin
                    $display("[TEST NL1] Starting deep push (wrap-around test)");
                    pipe_ready <= 1'b0;
                end
                32'd42: begin
                    rdi_valid <= 1'b1;
                    rdi_data[RDI_DATA_WIDTH-1:0] <= 16'hAAAA;
                end
                // Push until rdi_cycle 80 (approx 38 items, BUFFER_DEPTH=16)
                32'd80: begin
                    rdi_valid <= 1'b0;
                end
                32'd90: begin
                    $display("[TEST NL1] Draining FIFO");
                    pipe_ready <= 1'b1;
                end
                default: ;
            endcase
            rdi_cycle <= rdi_cycle + 1;
        end
    end

    always_ff @(posedge pipe_clk or negedge rst_n) begin
        if (!rst_n) begin
        end
    end

endmodule
