
`timescale 1ns/1ps

/**
 * Testbench top — clocks and reset driven from sim_main.cpp (Verilator 4 ignores # delays).
 * Stimulus is cycle-counted on posedge rdi_clk (one @ region per initial/always).
 */
module tb_ucie_rdi_to_pcie_pipe_bridge (
    input logic rdi_clk,
    input logic pipe_clk,
    input logic rst_n
);

    localparam int NUM_LANES = 4;
    localparam int RDI_DATA_WIDTH = 16;
    localparam int PIPE_DATA_WIDTH = 32;
    localparam int BUFFER_DEPTH = 16;

    logic [NUM_LANES-1:0] rdi_valid, rdi_error, rdi_flow_ctrl;
    wire [NUM_LANES-1:0] rdi_ready;
    logic [NUM_LANES*RDI_DATA_WIDTH-1:0] rdi_data;
    logic [NUM_LANES-1:0] pipe_valid, pipe_ready, pipe_error, crc_error, crc_enable;
    logic [NUM_LANES*PIPE_DATA_WIDTH-1:0] pipe_data;

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
        .crc_error(crc_error),
        .crc_enable(crc_enable)
    );

    ucie_rdi_to_pcie_pipe_bridge_assertions #(
        .NUM_LANES(NUM_LANES),
        .RDI_DATA_WIDTH(RDI_DATA_WIDTH),
        .PIPE_DATA_WIDTH(PIPE_DATA_WIDTH),
        .BUFFER_DEPTH(BUFFER_DEPTH)
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
        .pipe_error(pipe_error)
    );

    // RDI cycle counter, stimulus, and clean shutdown (single always_ff for Verilator 4)
    always_ff @(posedge rdi_clk or negedge rst_n) begin
        if (!rst_n) begin
            rdi_cycle <= '0;
            rdi_valid <= '0;
            rdi_data <= '0;
            rdi_error <= '0;
            crc_enable <= '0;
            pipe_ready <= '1;
        end else if (rdi_cycle == 32'd280) begin
            cdc_mon.print_statistics();
            $display("[TEST] Testbench complete");
            $finish;
        end else begin
            unique case (rdi_cycle)
                // First rdi_cycle after reset release is 1 (0 held during reset)
                32'd1: begin
                    $display("[TEST] Starting UCIe RDI to PCIe PIPE Bridge Testbench");
                end
                32'd6: begin
                    $display("[TEST] Test 1: Single transfer on lane 0");
                    rdi_valid[0] <= 1'b1;
                    rdi_data[15:0] <= 16'hDEAD;
                    rdi_error[0] <= 1'b0;
                end
                32'd8: begin
                    rdi_valid[0] <= 1'b0;
                    rdi_data[15:0] <= 16'h0000;
                end
                32'd21: begin
                    $display("[TEST] Test 2: Multi-lane transfer");
                    rdi_valid <= 4'b1111;
                    rdi_data[15:0] <= 16'hAAAA;
                    rdi_data[31:16] <= 16'hBBBB;
                    rdi_data[47:32] <= 16'hCCCC;
                    rdi_data[63:48] <= 16'hDDDD;
                end
                32'd23: begin
                    rdi_valid <= 4'b0000;
                    rdi_data <= '0;
                end
                32'd36: begin
                    $display("[TEST] Test 3: Flow control test");
                    pipe_ready <= 4'b0000;
                end
                32'd38: begin
                    rdi_valid[1] <= 1'b1;
                    rdi_data[31:16] <= 16'h1234;
                end
                32'd91: begin
                    pipe_ready <= 4'b1111;
                end
                32'd93: begin
                    rdi_valid[1] <= 1'b0;
                end
                32'd106: begin
                    $display("[TEST] Test 4: Error propagation");
                    rdi_valid[2] <= 1'b1;
                    rdi_error[2] <= 1'b1;
                    rdi_data[47:32] <= 16'hEEEE;
                end
                32'd108: begin
                    rdi_valid[2] <= 1'b0;
                    rdi_error[2] <= 1'b0;
                end
                32'd121: begin
                    $display("[TEST] Test 5: Sustained traffic");
                end
                default: begin
                    // Hold data stable while valid (avoid false CDC stability warnings)
                    if (rdi_cycle >= 32'd122 && rdi_cycle < 32'd172) begin
                        rdi_valid <= 4'b1111;
                        rdi_data <= 64'hAAA0_BBB0_CCC0_DDD0;
                    end else if (rdi_cycle == 32'd172) begin
                        rdi_valid <= '0;
                    end
                end
            endcase
            rdi_cycle <= rdi_cycle + 1;
        end
    end

    // Monitors
    always_ff @(posedge rdi_clk) begin
        if (rst_n && rdi_valid != '0) begin
            $display("[RDI] Time=%0t: valid=%b ready=%b data=%h error=%b flow_ctrl=%b",
                     $time, rdi_valid, rdi_ready, rdi_data, rdi_error, rdi_flow_ctrl);
        end
    end

    always_ff @(posedge pipe_clk) begin
        if (rst_n && pipe_valid != '0) begin
            $display("[PIPE] Time=%0t: valid=%b, data=%h, error=%b",
                     $time, pipe_valid, pipe_data, pipe_error);
        end
    end

endmodule
