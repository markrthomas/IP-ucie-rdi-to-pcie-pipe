
`timescale 1ns/1ps

module tb_ucie_rdi_to_pcie_pipe_bridge;

    localparam int NUM_LANES = 4;
    localparam int RDI_DATA_WIDTH = 16;
    localparam int PIPE_DATA_WIDTH = 32;
    localparam int BUFFER_DEPTH = 16;
    localparam realtime RDI_CLK_PERIOD = 10ns;
    localparam realtime PIPE_CLK_PERIOD = 6.667ns;

    logic rst_n;
    logic rdi_clk, pipe_clk;
    logic [NUM_LANES-1:0] rdi_valid, rdi_ready, rdi_error, rdi_flow_ctrl;
    logic [NUM_LANES*RDI_DATA_WIDTH-1:0] rdi_data;
    logic [NUM_LANES-1:0] pipe_valid, pipe_ready, pipe_error, crc_error, crc_enable;
    logic [NUM_LANES*PIPE_DATA_WIDTH-1:0] pipe_data;

    // DUT instantiation
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

    // Clock generation
    // Clock generation - use always blocks instead of forever
    always begin
        rdi_clk = 1'b0;
        #5ns;
        rdi_clk = 1'b1;
        #5ns;
    end

    always begin
        pipe_clk = 1'b0;
        #3.3335ns;
        pipe_clk = 1'b1;
        #3.3335ns;
    end

    // Reset generation
    initial begin
        rst_n = 1'b0;
        #100ns;
        rst_n = 1'b1;
    end

    // Test stimulus (using only # delays, no @)
    initial begin
        $display("[TEST] Starting UCIe RDI to PCIe PIPE Bridge Testbench");

        // Initialize signals
        rdi_valid = '0;
        rdi_data = '0;
        rdi_error = '0;
        crc_enable = '0;
        pipe_ready = '1;

        // Wait for reset
        #200ns;

        // Test 1: Basic single transfer on lane 0
        $display("[TEST] Test 1: Single transfer on lane 0");
        #10ns;
        rdi_valid[0] = 1'b1;
        rdi_data[15:0] = 16'hDEAD;
        rdi_error[0] = 1'b0;

        #10ns;
        rdi_valid[0] = 1'b0;
        rdi_data[15:0] = 16'h0000;

        // Test 2: Multi-lane transfer
        $display("[TEST] Test 2: Multi-lane transfer");
        #100ns;
        rdi_valid = 4'b1111;
        rdi_data[15:0] = 16'hAAAA;
        rdi_data[31:16] = 16'hBBBB;
        rdi_data[47:32] = 16'hCCCC;
        rdi_data[63:48] = 16'hDDDD;

        #10ns;
        rdi_valid = 4'b0000;
        rdi_data = '0;

        // Test 3: Flow control (backpressure)
        $display("[TEST] Test 3: Flow control test");
        #100ns;
        pipe_ready = 1'b0;

        rdi_valid[1] = 1'b1;
        rdi_data[31:16] = 16'h1234;

        #500ns;
        pipe_ready = 1'b1;
        rdi_valid[1] = 1'b0;

        // Test 4: Error propagation
        $display("[TEST] Test 4: Error propagation");
        #100ns;
        rdi_valid[2] = 1'b1;
        rdi_error[2] = 1'b1;
        rdi_data[47:32] = 16'hEEEE;

        #10ns;
        rdi_valid[2] = 1'b0;
        rdi_error[2] = 1'b0;

        // Test 5: Sustained traffic
        $display("[TEST] Test 5: Sustained traffic");
        #200ns;
        repeat (50) begin
            #10ns;
            rdi_valid = 4'b1111;
            rdi_data = {$random, $random};
        end

        rdi_valid = '0;

        // Final wait and finish
        #500ns;
        $display("[TEST] Testbench complete");
        $finish;
    end

    // Monitor on RDI side
    always begin
        #(RDI_CLK_PERIOD);
        if (rst_n && rdi_valid != '0) begin
            $display("[RDI] Time=%0t: valid=%b, data=%h, error=%b, flow_ctrl=%b",
                     $time, rdi_valid, rdi_data, rdi_error, rdi_flow_ctrl);
        end
    end

    // Monitor on PIPE side
    always begin
        #(PIPE_CLK_PERIOD);
        if (rst_n && pipe_valid != '0) begin
            $display("[PIPE] Time=%0t: valid=%b, data=%h, error=%b",
                     $time, pipe_valid, pipe_data, pipe_error);
        end
    end

endmodule

