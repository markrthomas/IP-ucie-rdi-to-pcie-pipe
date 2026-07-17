
`timescale 1ns/1ps

interface pcie_pipe_if #(
    parameter int DATA_WIDTH = 32,
    parameter int NUM_LANES = 4
) (
    input logic clk,
    input logic rst_n
);
    logic [NUM_LANES-1:0]      valid;
    logic [NUM_LANES-1:0]      ready;
    logic [NUM_LANES*DATA_WIDTH-1:0] data;
    logic [NUM_LANES-1:0]      error;

    // Driver Clocking Block (for RX path testing)
    clocking drv_cb @(posedge clk);
        default input #1ns output #1ns;
        output valid;
        input  ready;
        output data;
        output error;
    endclocking

    // Ready control clocking block (for TX backpressure testing)
    clocking ctrl_cb @(posedge clk);
        default input #1ns output #1ns;
        output ready;
        input  valid;
        input  data;
        input  error;
    endclocking

    // Monitor Clocking Block
    clocking mon_cb @(posedge clk);
        default input #1ns output #1ns;
        input valid;
        input ready;
        input data;
        input error;
    endclocking

    modport drv (clocking drv_cb, input clk, rst_n);
    modport ctrl (clocking ctrl_cb, input clk, rst_n);
    modport mon (clocking mon_cb, input clk, rst_n);

endinterface
