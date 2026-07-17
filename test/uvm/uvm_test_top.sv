
`timescale 1ns/1ps

module uvm_test_top;

    import uvm_pkg::*;
    import ucie_rdi_pcie_pkg::*;
    import ucie_rdi_seq_lib::*;

    logic rdi_clk;
    logic pipe_clk;
    logic rst_n;

    // --- Clock Generation ---
    initial begin
        rdi_clk = 0;
        forever #5ns rdi_clk = ~rdi_clk; // 100 MHz
    end

    initial begin
        pipe_clk = 0;
        forever #3.333ns pipe_clk = ~pipe_clk; // 150 MHz
    end

    // --- Reset Generation ---
    initial begin
        rst_n = 0;
        #100ns rst_n = 1;
    end

    // --- Interfaces ---
    ucie_rdi_if #(.DATA_WIDTH(16), .NUM_LANES(4)) rdi_tx_if (.clk(rdi_clk), .rst_n(rst_n));
    pcie_pipe_if #(.DATA_WIDTH(32), .NUM_LANES(4)) pipe_tx_if (.clk(pipe_clk), .rst_n(rst_n));
    
    ucie_rdi_if #(.DATA_WIDTH(16), .NUM_LANES(4)) rdi_rx_if (.clk(rdi_clk), .rst_n(rst_n));
    pcie_pipe_if #(.DATA_WIDTH(32), .NUM_LANES(4)) pipe_rx_if (.clk(pipe_clk), .rst_n(rst_n));

    // --- DUT Instantiation ---
    ucie_rdi_to_pcie_pipe_bridge #(
        .NUM_LANES(4),
        .RDI_DATA_WIDTH(16),
        .PIPE_DATA_WIDTH(32),
        .BUFFER_DEPTH(16)
    ) dut (
        .rst_n(rst_n),
        .rdi_clk(rdi_clk),
        
        // RDI TX
        .rdi_valid(rdi_tx_if.valid),
        .rdi_ready(rdi_tx_if.ready),
        .rdi_data(rdi_tx_if.data),
        .rdi_error(rdi_tx_if.error),
        .rdi_flow_ctrl(rdi_tx_if.flow_ctrl),

        // PIPE TX
        .pipe_clk(pipe_clk),
        .pipe_valid(pipe_tx_if.valid),
        .pipe_ready(pipe_tx_if.ready),
        .pipe_data(pipe_tx_if.data),
        .pipe_error(pipe_tx_if.error),

        // RDI RX
        .rdi_rx_valid(rdi_rx_if.valid),
        .rdi_rx_ready(rdi_rx_if.ready),
        .rdi_rx_data(rdi_rx_if.data),
        .rdi_rx_error(rdi_rx_if.error),

        // PIPE RX
        .pipe_rx_valid(pipe_rx_if.valid),
        .pipe_rx_ready(pipe_rx_if.ready),
        .pipe_rx_data(pipe_rx_if.data),
        .pipe_rx_error(pipe_rx_if.error),

        .crc_error(),
        .crc_enable(4'b0)
    );

    ucie_rdi_to_pcie_pipe_bridge_assertions #(
        .NUM_LANES(4),
        .RDI_DATA_WIDTH(16),
        .PIPE_DATA_WIDTH(32)
    ) cdc_mon (
        .rst_n(rst_n),
        .rdi_clk(rdi_clk),
        .pipe_clk(pipe_clk),
        .rdi_valid(rdi_tx_if.valid),
        .rdi_ready(rdi_tx_if.ready),
        .rdi_data(rdi_tx_if.data),
        .rdi_error(rdi_tx_if.error),
        .pipe_valid(pipe_tx_if.valid),
        .pipe_ready(pipe_tx_if.ready),
        .pipe_data(pipe_tx_if.data),
        .pipe_error(pipe_tx_if.error),
        .pipe_rx_valid(pipe_rx_if.valid),
        .pipe_rx_ready(pipe_rx_if.ready),
        .pipe_rx_data(pipe_rx_if.data),
        .pipe_rx_error(pipe_rx_if.error),
        .rdi_rx_valid(rdi_rx_if.valid),
        .rdi_rx_ready(rdi_rx_if.ready),
        .rdi_rx_data(rdi_rx_if.data),
        .rdi_rx_error(rdi_rx_if.error)
    );

    // --- UVM Setup ---
    initial begin
        uvm_config_db#(virtual ucie_rdi_if)::set(null, "*.env.rdi_agent*", "vif", rdi_tx_if);
        uvm_config_db#(virtual pcie_pipe_if)::set(null, "*.env.pipe_agent*", "vif", pipe_tx_if);
        uvm_config_db#(virtual ucie_rdi_if)::set(null, "*.env.rdi_rx_mon*", "vif", rdi_rx_if);
        uvm_config_db#(virtual pcie_pipe_if)::set(null, "*.env.pipe_rx_mon*", "vif", pipe_rx_if);
        
        // Default ready signals
        pipe_tx_if.ready = 4'b1111;
        rdi_rx_if.ready = 4'b1111;
        pipe_rx_if.valid = 4'b0000;

        run_test();
    end

    final begin
        cdc_mon.print_statistics();
    end

endmodule
