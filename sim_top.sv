
`timescale 1ns/1ps

/**
 * Wrapper for simulators that drive clocks with # delays (VCS, Questa, Xcelium).
 * Verilator uses tb_ucie_rdi_to_pcie_pipe_bridge as top with C++ clock/reset.
 */
module sim_top;

    logic rdi_clk;
    logic pipe_clk;
    logic rst_n;

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

    initial begin
        rst_n = 1'b0;
        #100ns;
        rst_n = 1'b1;
    end

    tb_ucie_rdi_to_pcie_pipe_bridge tb (
        .rdi_clk(rdi_clk),
        .pipe_clk(pipe_clk),
        .rst_n(rst_n)
    );

endmodule
