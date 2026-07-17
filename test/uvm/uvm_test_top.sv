
`timescale 1ns/1ps

module uvm_test_top;

    import uvm_pkg::*;
    import ucie_rdi_pcie_pkg::*;
    import ucie_rdi_seq_lib::*;

    logic rdi_clk;
    logic pipe_clk;
    logic rst_n;
    logic [NUM_LANES-1:0] crc_enable;
    logic [NUM_LANES-1:0] crc_error;
    localparam logic [31:0] CRC_RESIDUE = 32'h1704_7432;

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
    ucie_rdi_if #(.DATA_WIDTH(RDI_DATA_WIDTH), .NUM_LANES(NUM_LANES)) rdi_tx_if (.clk(rdi_clk), .rst_n(rst_n));
    pcie_pipe_if #(.DATA_WIDTH(PIPE_DATA_WIDTH), .NUM_LANES(NUM_LANES)) pipe_tx_if (.clk(pipe_clk), .rst_n(rst_n));

    ucie_rdi_if #(.DATA_WIDTH(RDI_DATA_WIDTH), .NUM_LANES(NUM_LANES)) rdi_rx_if (.clk(rdi_clk), .rst_n(rst_n));
    pcie_pipe_if #(.DATA_WIDTH(PIPE_DATA_WIDTH), .NUM_LANES(NUM_LANES)) pipe_rx_if (.clk(pipe_clk), .rst_n(rst_n));

    function automatic logic [31:0] tb_crc32_step(
        input logic [31:0] data_in,
        input logic [31:0] crc_in
    );
        logic [31:0] crc_temp;
        logic fb;
        crc_temp = crc_in;
        for (int i = 0; i < 32; i++) begin
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
        end else if (crc_enable[0] && pipe_tx_if.valid[0] && pipe_tx_if.ready[0]) begin
            tb_crc_lane0 <= tb_crc32_step(pipe_tx_if.data[31:0], tb_crc_lane0);
        end
    end

    always_ff @(negedge pipe_clk) begin
        if (!rst_n) begin
        end else if (crc_enable[0]) begin
            if (crc_error[0] != (tb_crc_lane0 != CRC_RESIDUE)) begin
                uvm_error("CRC_CHK",
                          $sformatf("Lane 0 crc_error=%b vs model (tb_crc=%h residue_ok=%b)",
                                    crc_error[0],
                                    tb_crc_lane0,
                                    (tb_crc_lane0 == CRC_RESIDUE)));
            end
        end
    end

    // --- DUT Instantiation ---
    ucie_rdi_to_pcie_pipe_bridge #(
        .NUM_LANES(NUM_LANES),
        .RDI_DATA_WIDTH(RDI_DATA_WIDTH),
        .PIPE_DATA_WIDTH(PIPE_DATA_WIDTH),
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

        .crc_error(crc_error),
        .crc_enable(crc_enable)
    );

    // Mirror CRC status onto the TX PIPE interface so functional coverage
    // can sample crc enable/error alongside the observed PIPE beats.
    assign pipe_tx_if.crc_enable = crc_enable;
    assign pipe_tx_if.crc_error  = crc_error;

    ucie_rdi_to_pcie_pipe_bridge_assertions #(
        .NUM_LANES(NUM_LANES),
        .RDI_DATA_WIDTH(RDI_DATA_WIDTH),
        .PIPE_DATA_WIDTH(PIPE_DATA_WIDTH)
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
        uvm_config_db#(virtual pcie_pipe_if)::set(null, "*.env.pipe_rx_agent*", "vif", pipe_rx_if);
        uvm_config_db#(virtual ucie_rdi_if)::set(null, "*.env.rdi_rx_mon*", "vif", rdi_rx_if);
        uvm_config_db#(virtual pcie_pipe_if)::set(null, "*.env.pipe_rx_mon*", "vif", pipe_rx_if);
        
        // Default ready signals
        pipe_tx_if.ready = '1;
        rdi_rx_if.ready = '1;
        pipe_rx_if.valid = '0;
        crc_enable = '0;

        run_test();
    end

    initial begin
        uvm_event_pool event_pool;
        event_pool = uvm_event_pool::get_global_pool();
        event_pool.get("crc_start").wait_trigger();
        crc_enable[0] = 1'b1;
        event_pool.get("crc_stop").wait_trigger();
        crc_enable[0] = 1'b0;
    end

    final begin
        cdc_mon.print_statistics();
    end

endmodule
