// ucie_fifo_cdc_model.v — Yosys-compatible formal model of ucie_rdi_fifo_cdc
//
// Faithfully re-implements the production RTL (src/ucie_rdi_fifo_cdc.sv) in
// plain Verilog-2001/SV subset that Yosys can parse:
//   - struct array split into two parallel arrays (data and error)
//   - function return via function-name assignment instead of 'return'
//   - 'for' loop uses integer variable, not 'int'
//   - no struct literals
//
// All logic is identical to the production module.  Formal properties proved
// on this model apply to the equivalent production RTL.

`timescale 1ns/1ps

module ucie_rdi_fifo_cdc #(
    parameter integer INPUT_DATA_WIDTH  = 16,
    parameter integer OUTPUT_DATA_WIDTH = 32,
    parameter integer BUFFER_DEPTH      = 16
) (
    input  wire                          wr_clk,
    input  wire                          rd_clk,
    input  wire                          rst_n,

    input  wire                          wr_valid,
    output wire                          wr_ready,
    input  wire [INPUT_DATA_WIDTH-1:0]   wr_data,
    input  wire                          wr_error,
    output wire                          wr_full,

    output reg                           rd_valid,
    input  wire                          rd_ready,
    output reg  [OUTPUT_DATA_WIDTH-1:0]  rd_data,
    output reg                           rd_error,

    // Debug ports for formal verification only (not in production interface).
    output wire [PTR_WIDTH-1:0]          dbg_wr_ptr,
    output wire [PTR_WIDTH-1:0]          dbg_rd_ptr
);

    localparam integer PTR_WIDTH = $clog2(BUFFER_DEPTH) + 1;

    // Buffer storage: parallel arrays replace the struct array.
    reg [INPUT_DATA_WIDTH-1:0] buf_data  [0:BUFFER_DEPTH-1];
    reg                        buf_error [0:BUFFER_DEPTH-1];

    // --- Gray code conversions ---
    function [PTR_WIDTH-1:0] bin2gray;
        input [PTR_WIDTH-1:0] bin;
        begin
            bin2gray = bin ^ (bin >> 1);
        end
    endfunction

    function [PTR_WIDTH-1:0] gray2bin;
        input [PTR_WIDTH-1:0] gray;
        integer i;
        begin
            gray2bin[PTR_WIDTH-1] = gray[PTR_WIDTH-1];
            for (i = PTR_WIDTH-2; i >= 0; i = i - 1)
                gray2bin[i] = gray2bin[i+1] ^ gray[i];
        end
    endfunction

    // --- Write domain ---
    reg [PTR_WIDTH-1:0] wr_ptr;
    wire [PTR_WIDTH-1:0] wr_ptr_gray;
    assign wr_ptr_gray = bin2gray(wr_ptr);

    always @(posedge wr_clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= {PTR_WIDTH{1'b0}};
        end else if (wr_valid && wr_ready) begin
            buf_data [wr_ptr[PTR_WIDTH-2:0]] <= wr_data;
            buf_error[wr_ptr[PTR_WIDTH-2:0]] <= wr_error;
            wr_ptr <= wr_ptr + 1'b1;
        end
    end

    // --- CDC: write pointer (Gray) → read domain ---
    reg [PTR_WIDTH-1:0] wr_ptr_gray_sync_r1, wr_ptr_gray_sync;

    always @(posedge rd_clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr_gray_sync_r1 <= {PTR_WIDTH{1'b0}};
            wr_ptr_gray_sync    <= {PTR_WIDTH{1'b0}};
        end else begin
            wr_ptr_gray_sync_r1 <= wr_ptr_gray;
            wr_ptr_gray_sync    <= wr_ptr_gray_sync_r1;
        end
    end

    // --- Read domain ---
    reg [PTR_WIDTH-1:0] rd_ptr;
    wire [PTR_WIDTH-1:0] rd_wr_ptr;
    wire empty;

    assign rd_wr_ptr = gray2bin(wr_ptr_gray_sync);
    assign empty = (rd_wr_ptr == rd_ptr);

    // Read data mux (width conversion).
    wire [OUTPUT_DATA_WIDTH-1:0] rd_data_mux;
    wire                         rd_error_mux;

    generate
        if (OUTPUT_DATA_WIDTH > INPUT_DATA_WIDTH) begin : GEN_EXTEND
            assign rd_data_mux = {{(OUTPUT_DATA_WIDTH-INPUT_DATA_WIDTH){1'b0}},
                                  buf_data[rd_ptr[PTR_WIDTH-2:0]]};
        end else if (OUTPUT_DATA_WIDTH < INPUT_DATA_WIDTH) begin : GEN_TRUNCATE
            assign rd_data_mux = buf_data[rd_ptr[PTR_WIDTH-2:0]][OUTPUT_DATA_WIDTH-1:0];
        end else begin : GEN_DIRECT
            assign rd_data_mux = buf_data[rd_ptr[PTR_WIDTH-2:0]];
        end
    endgenerate
    assign rd_error_mux = buf_error[rd_ptr[PTR_WIDTH-2:0]];

    always @(posedge rd_clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_ptr   <= {PTR_WIDTH{1'b0}};
            rd_valid <= 1'b0;
            rd_data  <= {OUTPUT_DATA_WIDTH{1'b0}};
            rd_error <= 1'b0;
        end else begin
            if (rd_ready || !rd_valid) begin
                if (!empty) begin
                    rd_ptr   <= rd_ptr + 1'b1;
                    rd_valid <= 1'b1;
                    rd_data  <= rd_data_mux;
                    rd_error <= rd_error_mux;
                end else begin
                    rd_valid <= 1'b0;
                end
            end
        end
    end

    // --- CDC: read pointer (Gray) → write domain ---
    wire [PTR_WIDTH-1:0] rd_ptr_gray;
    assign rd_ptr_gray = bin2gray(rd_ptr);

    reg [PTR_WIDTH-1:0] rd_ptr_gray_sync_r1, rd_ptr_gray_sync;

    always @(posedge wr_clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_ptr_gray_sync_r1 <= {PTR_WIDTH{1'b0}};
            rd_ptr_gray_sync    <= {PTR_WIDTH{1'b0}};
        end else begin
            rd_ptr_gray_sync_r1 <= rd_ptr_gray;
            rd_ptr_gray_sync    <= rd_ptr_gray_sync_r1;
        end
    end

    wire [PTR_WIDTH-1:0] wr_rd_ptr;
    assign wr_rd_ptr = gray2bin(rd_ptr_gray_sync);

    assign wr_full  = (wr_ptr[PTR_WIDTH-2:0] == wr_rd_ptr[PTR_WIDTH-2:0]) &&
                      (wr_ptr[PTR_WIDTH-1]   != wr_rd_ptr[PTR_WIDTH-1]);
    assign wr_ready = !wr_full;

    assign dbg_wr_ptr = wr_ptr;
    assign dbg_rd_ptr = rd_ptr;

endmodule
