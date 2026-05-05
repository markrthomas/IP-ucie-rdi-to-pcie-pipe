
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

    // Transmit path signals
    logic [NUM_LANES-1:0] rdi_valid, rdi_error, rdi_flow_ctrl;
    wire [NUM_LANES-1:0] rdi_ready;
    logic [NUM_LANES*RDI_DATA_WIDTH-1:0] rdi_data;
    logic [NUM_LANES-1:0] pipe_valid, pipe_ready, pipe_error, crc_error, crc_enable;
    logic [NUM_LANES*PIPE_DATA_WIDTH-1:0] pipe_data;

    // Receive path signals
    /* verilator lint_off UNUSEDSIGNAL */
    logic [NUM_LANES-1:0] rdi_rx_valid, rdi_rx_error;
    logic [NUM_LANES-1:0] rdi_rx_ready;
    logic [NUM_LANES*RDI_DATA_WIDTH-1:0] rdi_rx_data;
    logic [NUM_LANES-1:0] pipe_rx_valid, pipe_rx_error;
    wire [NUM_LANES-1:0] pipe_rx_ready;
    logic [NUM_LANES*PIPE_DATA_WIDTH-1:0] pipe_rx_data;
    /* verilator lint_on UNUSEDSIGNAL */

    logic [31:0] rdi_cycle;

    localparam logic [31:0] CRC_RESIDUE = 32'h1704_7432;

    // Mirror RTL CRC update for lane 0 (same polynomial / bit order as DUT).
    function automatic logic [31:0] tb_crc32_step(
        input logic [31:0] data_in,
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

    logic [31:0] tb_crc_lane0;
    always_ff @(posedge pipe_clk or negedge rst_n) begin
        if (!rst_n) begin
            tb_crc_lane0 <= 32'hFFFF_FFFF;
        end else if (!crc_enable[0]) begin
            tb_crc_lane0 <= 32'hFFFF_FFFF;
        end else if (crc_enable[0] && pipe_valid[0] && pipe_ready[0]) begin
            tb_crc_lane0 <= tb_crc32_step(pipe_data[31:0], tb_crc_lane0);
        end
    end

    // crc_error when crc_enable: 1 iff residue mismatch (matches DUT assign semantics).
    always_ff @(negedge pipe_clk) begin
        if (!rst_n) begin
        end else if (crc_enable[0]) begin
            if (crc_error[0] != (tb_crc_lane0 != CRC_RESIDUE)) begin
                $fatal(1,
                       "[CRC_CHK] Lane 0 crc_error=%b vs model (tb_crc=%h residue_ok=%b)",
                       crc_error[0],
                       tb_crc_lane0,
                       (tb_crc_lane0 == CRC_RESIDUE));
            end
        end
    end

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

    tb_ucie_rdi_to_pcie_pipe_scoreboard #(
        .NUM_LANES(NUM_LANES),
        .RDI_DATA_WIDTH(RDI_DATA_WIDTH),
        .PIPE_DATA_WIDTH(PIPE_DATA_WIDTH)
    ) sb (
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

    // RDI cycle counter, stimulus, and clean shutdown (single always_ff for Verilator 4)
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
        end else if (rdi_cycle == 32'd400) begin
            sb.final_check();
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
                    $display("[TEST] Test 1: Single transfer on lane 0 (TX)");
                    rdi_valid[0] <= 1'b1;
                    rdi_data[15:0] <= 16'hDEAD;
                    rdi_error[0] <= 1'b0;
                end
                32'd8: begin
                    rdi_valid[0] <= 1'b0;
                    rdi_data[15:0] <= 16'h0000;
                end
                32'd21: begin
                    $display("[TEST] Test 2: Multi-lane transfer (TX)");
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
                    $display("[TEST] Test 3: Flow control test (TX)");
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
                    $display("[TEST] Test 4: Error propagation (TX)");
                    rdi_valid[2] <= 1'b1;
                    rdi_error[2] <= 1'b1;
                    rdi_data[47:32] <= 16'hEEEE;
                end
                32'd108: begin
                    rdi_valid[2] <= 1'b0;
                    rdi_error[2] <= 1'b0;
                end
                32'd121: begin
                    $display("[TEST] Test 5: Sustained traffic (TX)");
                end
                default: begin
                    // Hold data stable while valid (avoid false CDC stability warnings)
                    if (rdi_cycle >= 32'd122 && rdi_cycle < 32'd172) begin
                        rdi_valid <= 4'b1111;
                        rdi_data <= 64'hAAA0_BBB0_CCC0_DDD0;
                    end else if (rdi_cycle == 32'd172) begin
                        rdi_valid <= '0;
                    end else if (rdi_cycle == 32'd173) begin
                        $display("[TEST] Test 6: FIFO stress (PIPE stalled, multi-lane push) (TX)");
                    end else if (rdi_cycle == 32'd174) begin
                        pipe_ready <= 4'b0000;
                    end else if (rdi_cycle >= 32'd175 && rdi_cycle <= 32'd210) begin
                        rdi_valid <= 4'b1111;
                        rdi_data <= 64'hACE0_BAD0_CAFE_F00D;
                    end else if (rdi_cycle == 32'd211) begin
                        rdi_valid <= '0;
                    end else if (rdi_cycle == 32'd212) begin
                        pipe_ready <= 4'b1111;
                    end else if (rdi_cycle == 220) begin
                        $display("[TEST] Test 8: Single transfer on lane 1 (RX)");
                    end else if (rdi_cycle == 222) begin
                        pipe_rx_valid[1] <= 1'b1;
                        pipe_rx_data[63:32] <= 32'hBEEF_CAFE;
                    end else if (rdi_cycle == 224) begin
                        pipe_rx_valid[1] <= 1'b0;
                    end else if (rdi_cycle == 240) begin
                        $display("[TEST] Test 9: Multi-lane transfer (RX)");
                        pipe_rx_valid <= 4'b1111;
                        pipe_rx_data[31:0]   <= 32'h0000_1111;
                        pipe_rx_data[63:32]  <= 32'h0000_2222;
                        pipe_rx_data[95:64]  <= 32'h0000_3333;
                        pipe_rx_data[127:96] <= 32'h0000_4444;
                    end else if (rdi_cycle == 242) begin
                        pipe_rx_valid <= 4'b0000;
                    end else if (rdi_cycle == 260) begin
                        $display("[TEST] Test 10: Bidirectional traffic");
                    end else if (rdi_cycle >= 262 && rdi_cycle < 312) begin
                        rdi_valid <= 4'b1010;
                        rdi_data <= 64'hAAAA_0000_CCCC_0000;
                        pipe_rx_valid <= 4'b0101;
                        pipe_rx_data <= 128'h0000_DDDD_0000_0000_0000_BBBB_0000_0000;
                    end else if (rdi_cycle == 312) begin
                        rdi_valid <= '0;
                        pipe_rx_valid <= '0;
                    end else if (rdi_cycle == 32'd340) begin
                        $display("[TEST] Test 7: CRC lane 0 (handshake-gated model vs crc_error) (TX)");
                    end else if (rdi_cycle == 32'd341) begin
                        crc_enable[0] <= 1'b1;
                    end else if (rdi_cycle == 32'd342) begin
                        rdi_valid[0] <= 1'b1;
                        rdi_data[15:0] <= 16'h00_01;
                    end else if (rdi_cycle == 32'd343) begin
                        rdi_valid[0] <= 1'b0;
                    end else if (rdi_cycle == 32'd344) begin
                        rdi_valid[0] <= 1'b1;
                        rdi_data[15:0] <= 16'h00_02;
                    end else if (rdi_cycle == 32'd345) begin
                        rdi_valid[0] <= 1'b0;
                    end else if (rdi_cycle == 32'd380) begin
                        crc_enable[0] <= 1'b0;
                    end
                end
            endcase
            rdi_cycle <= rdi_cycle + 1;
        end
    end

    // Monitors
    always_ff @(posedge rdi_clk or negedge rst_n) begin
        if (!rst_n) begin
        end else begin
            if (rdi_valid != '0) begin
                $display("[RDI TX] Time=%0t: valid=%b ready=%b data=%h error=%b flow_ctrl=%b",
                         $time, rdi_valid, rdi_ready, rdi_data, rdi_error, rdi_flow_ctrl);
            end
            if (rdi_rx_valid != '0) begin
                $display("[RDI RX] Time=%0t: valid=%b ready=%b data=%h error=%b",
                         $time, rdi_rx_valid, rdi_rx_ready, rdi_rx_data, rdi_rx_error);
            end
        end
    end

    always_ff @(posedge pipe_clk or negedge rst_n) begin
        if (!rst_n) begin
        end else begin
            if (pipe_valid != '0) begin
                $display("[PIPE TX] Time=%0t: valid=%b, data=%h, error=%b, crc_err=%b",
                         $time, pipe_valid, pipe_data, pipe_error, crc_error);
            end
            if (pipe_rx_valid != '0) begin
                $display("[PIPE RX] Time=%0t: valid=%b ready=%b data=%h error=%b",
                         $time, pipe_rx_valid, pipe_rx_ready, pipe_rx_data, pipe_rx_error);
            end
        end
    end

endmodule
