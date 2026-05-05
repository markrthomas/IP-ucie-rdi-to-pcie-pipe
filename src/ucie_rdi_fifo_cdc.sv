
`timescale 1ns/1ps

/**
 * Parameterized Dual-Clock FIFO with Gray-coded CDC and stable output registers.
 * Designed for UCIe RDI and PCIe PIPE clock domain crossing.
 */
module ucie_rdi_fifo_cdc #(
    parameter int INPUT_DATA_WIDTH  = 16,
    parameter int OUTPUT_DATA_WIDTH = 32,
    parameter int BUFFER_DEPTH      = 16
) (
    input  logic                          wr_clk,
    input  logic                          rd_clk,
    input  logic                          rst_n,

    // Write Domain (UCIe RDI TX side or PIPE RX side)
    input  logic                          wr_valid,
    output logic                          wr_ready,
    input  logic [INPUT_DATA_WIDTH-1:0]   wr_data,
    input  logic                          wr_error,
    output logic                          wr_full,

    // Read Domain (PIPE TX side or UCIe RDI RX side)
    output logic                          rd_valid,
    input  logic                          rd_ready,
    output logic [OUTPUT_DATA_WIDTH-1:0]  rd_data,
    output logic                          rd_error
);

    localparam int PTR_WIDTH = $clog2(BUFFER_DEPTH) + 1;

    typedef struct packed {
        logic [INPUT_DATA_WIDTH-1:0] data;
        logic error;
    } entry_t;

    entry_t buffer [BUFFER_DEPTH];

    // --- Gray Code Conversions ---
    function automatic logic [PTR_WIDTH-1:0] bin2gray(input logic [PTR_WIDTH-1:0] bin);
        return bin ^ (bin >> 1);
    endfunction

    function automatic logic [PTR_WIDTH-1:0] gray2bin(input logic [PTR_WIDTH-1:0] gray);
        logic [PTR_WIDTH-1:0] bin;
        bin[PTR_WIDTH-1] = gray[PTR_WIDTH-1];
        for (int i = PTR_WIDTH-2; i >= 0; i--) begin
            bin[i] = bin[i+1] ^ gray[i];
        end
        return bin;
    endfunction

    // --- Write Domain ---
    logic [PTR_WIDTH-1:0] wr_ptr;
    logic [PTR_WIDTH-1:0] wr_ptr_gray;
    assign wr_ptr_gray = bin2gray(wr_ptr);

    always_ff @(posedge wr_clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= '0;
        end else if (wr_valid && wr_ready) begin
            buffer[wr_ptr[PTR_WIDTH-2:0]] <= '{
                data: wr_data,
                error: wr_error
            };
            wr_ptr <= wr_ptr + 1'b1;
        end
    end

    // --- CDC: Write pointer (gray) to Read Domain ---
    logic [PTR_WIDTH-1:0] wr_ptr_gray_sync_r1, wr_ptr_gray_sync;

    always_ff @(posedge rd_clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr_gray_sync_r1 <= '0;
            wr_ptr_gray_sync <= '0;
        end else begin
            wr_ptr_gray_sync_r1 <= wr_ptr_gray;
            wr_ptr_gray_sync <= wr_ptr_gray_sync_r1;
        end
    end

    // --- Read Domain ---
    logic [PTR_WIDTH-1:0] rd_wr_ptr, rd_ptr;
    logic empty;

    assign rd_wr_ptr = gray2bin(wr_ptr_gray_sync);
    assign empty = (rd_wr_ptr == rd_ptr);

    logic [OUTPUT_DATA_WIDTH-1:0] rd_data_mux;
    logic rd_error_mux;

    generate
        if (OUTPUT_DATA_WIDTH > INPUT_DATA_WIDTH) begin : GEN_EXTEND
            assign rd_data_mux = {{(OUTPUT_DATA_WIDTH-INPUT_DATA_WIDTH){1'b0}},
                                  buffer[rd_ptr[PTR_WIDTH-2:0]].data};
        end else if (OUTPUT_DATA_WIDTH < INPUT_DATA_WIDTH) begin : GEN_TRUNCATE
            assign rd_data_mux = buffer[rd_ptr[PTR_WIDTH-2:0]].data[OUTPUT_DATA_WIDTH-1:0];
        end else begin : GEN_DIRECT
            assign rd_data_mux = buffer[rd_ptr[PTR_WIDTH-2:0]].data;
        end
    endgenerate
    assign rd_error_mux = buffer[rd_ptr[PTR_WIDTH-2:0]].error;

    // Standard registered output FIFO logic
    always_ff @(posedge rd_clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_ptr   <= '0;
            rd_valid <= 1'b0;
            rd_data  <= '0;
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

    // --- CDC: Read pointer (gray) back to Write Domain ---
    logic [PTR_WIDTH-1:0] rd_ptr_gray;
    assign rd_ptr_gray = bin2gray(rd_ptr);

    logic [PTR_WIDTH-1:0] rd_ptr_gray_sync_r1, rd_ptr_gray_sync;

    always_ff @(posedge wr_clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_ptr_gray_sync_r1 <= '0;
            rd_ptr_gray_sync <= '0;
        end else begin
            rd_ptr_gray_sync_r1 <= rd_ptr_gray;
            rd_ptr_gray_sync <= rd_ptr_gray_sync_r1;
        end
    end

    logic [PTR_WIDTH-1:0] wr_rd_ptr;
    assign wr_rd_ptr = gray2bin(rd_ptr_gray_sync);

    assign wr_full = (wr_ptr[PTR_WIDTH-2:0] == wr_rd_ptr[PTR_WIDTH-2:0]) &&
                     (wr_ptr[PTR_WIDTH-1] != wr_rd_ptr[PTR_WIDTH-1]);
    assign wr_ready = !wr_full;

endmodule
