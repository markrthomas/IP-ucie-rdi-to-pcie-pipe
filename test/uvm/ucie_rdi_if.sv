
`timescale 1ns/1ps

interface ucie_rdi_if #(
    parameter int DATA_WIDTH = 16,
    parameter int NUM_LANES = 4
) (
    input logic clk,
    input logic rst_n
);
    logic [NUM_LANES-1:0]      valid;
    logic [NUM_LANES-1:0]      ready;
    logic [NUM_LANES*DATA_WIDTH-1:0] data;
    logic [NUM_LANES-1:0]      error;
    logic [NUM_LANES-1:0]      flow_ctrl;

    // Driver Clocking Block
    clocking drv_cb @(posedge clk);
        default input #1ns output #1ns;
        output valid;
        input  ready;
        output data;
        output error;
        input  flow_ctrl;
    endclocking

    // Ready control clocking block (for RX backpressure testing)
    clocking ctrl_cb @(posedge clk);
        default input #1ns output #1ns;
        output ready;
        input  valid;
        input  data;
        input  error;
        input  flow_ctrl;
    endclocking

    // Monitor Clocking Block
    clocking mon_cb @(posedge clk);
        default input #1ns output #1ns;
        input valid;
        input ready;
        input data;
        input error;
        input flow_ctrl;
    endclocking

    modport drv (clocking drv_cb, input clk, rst_n);
    modport ctrl (clocking ctrl_cb, input clk, rst_n);
    modport mon (clocking mon_cb, input clk, rst_n);

endinterface
