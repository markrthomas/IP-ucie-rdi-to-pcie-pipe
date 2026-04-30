
`timescale 1ns/1ps

/**
 * Reference scoreboard: each RDI accepted beat (per lane) is queued; each PIPE
 * accepted beat must match in order (zero-extended data, error flag).
 *
 * Compare runs on negedge pipe_clk after a handshake on posedge so PIPE data
 * matches NB-updated registered outputs from the DUT.
 */
module tb_ucie_rdi_to_pcie_pipe_scoreboard #(
    parameter int NUM_LANES       = 4,
    parameter int RDI_DATA_WIDTH  = 16,
    parameter int PIPE_DATA_WIDTH = 32
) (
    input logic rst_n,
    input logic rdi_clk,
    input logic pipe_clk,
    input logic [NUM_LANES-1:0] rdi_valid,
    input logic [NUM_LANES-1:0] rdi_ready,
    input logic [NUM_LANES*RDI_DATA_WIDTH-1:0] rdi_data,
    input logic [NUM_LANES-1:0] rdi_error,
    input logic [NUM_LANES-1:0] pipe_valid,
    input logic [NUM_LANES-1:0] pipe_ready,
    input logic [NUM_LANES*PIPE_DATA_WIDTH-1:0] pipe_data,
    input logic [NUM_LANES-1:0] pipe_error
);

    typedef struct packed {
        logic [RDI_DATA_WIDTH-1:0] data;
        logic error;
    } exp_beat_t;

    exp_beat_t exp_q[NUM_LANES][$];

    logic [NUM_LANES-1:0] sb_chk_nd;
    logic [PIPE_DATA_WIDTH-1:0] sb_exp_dw[NUM_LANES];
    logic sb_exp_er[NUM_LANES];

    integer ln;

    always_ff @(posedge rdi_clk or negedge rst_n) begin
        if (!rst_n) begin
            for (ln = 0; ln < NUM_LANES; ln++) begin
                exp_q[ln].delete();
            end
        end else begin
            for (ln = 0; ln < NUM_LANES; ln++) begin
                if (rdi_valid[ln] && rdi_ready[ln]) begin
                    exp_beat_t new_beat;
                    new_beat.data  = rdi_data[ln * RDI_DATA_WIDTH +: RDI_DATA_WIDTH];
                    new_beat.error = rdi_error[ln];
                    exp_q[ln].push_back(new_beat);
                end
            end
        end
    end

    always_ff @(posedge pipe_clk or negedge rst_n) begin
        if (!rst_n) begin
            sb_chk_nd <= '0;
        end else begin
            sb_chk_nd <= '0;
            for (ln = 0; ln < NUM_LANES; ln++) begin
                if (pipe_valid[ln] && pipe_ready[ln]) begin
                    if (exp_q[ln].size() == 0) begin
                        $fatal(1, "[SCOREBOARD] PIPE handshake on lane %0d but expected queue empty", ln);
                    end
                    begin
                        automatic exp_beat_t ge = exp_q[ln].pop_front();
                        sb_exp_dw[ln] <= {{(PIPE_DATA_WIDTH - RDI_DATA_WIDTH) {1'b0}}, ge.data};
                        sb_exp_er[ln] <= ge.error;
                        sb_chk_nd[ln] <= 1'b1;
                    end
                end
            end
        end
    end

    always_ff @(negedge pipe_clk) begin
        if (!rst_n) begin
        end else begin
            for (ln = 0; ln < NUM_LANES; ln++) begin
                if (sb_chk_nd[ln]) begin
                    if (pipe_data[ln * PIPE_DATA_WIDTH +: PIPE_DATA_WIDTH] !== sb_exp_dw[ln]) begin
                        $fatal(1,
                               "[SCOREBOARD] Lane %0d data mismatch exp=%h got=%h",
                               ln,
                               sb_exp_dw[ln],
                               pipe_data[ln * PIPE_DATA_WIDTH +: PIPE_DATA_WIDTH]);
                    end
                    if (pipe_error[ln] !== sb_exp_er[ln]) begin
                        $fatal(1,
                               "[SCOREBOARD] Lane %0d error mismatch exp=%b got=%b",
                               ln,
                               sb_exp_er[ln],
                               pipe_error[ln]);
                    end
                end
            end
        end
    end

    task automatic final_check();
        begin
            $display("[SCOREBOARD] Checking expected queues empty...");
            for (ln = 0; ln < NUM_LANES; ln++) begin
                if (exp_q[ln].size() != 0) begin
                    $fatal(1,
                           "[SCOREBOARD] Lane %0d still has %0d unconsumed expected beats",
                           ln,
                           exp_q[ln].size());
                end
            end
            $display("[SCOREBOARD] PASS — all lanes drained; data and error matched.");
        end
    endtask

endmodule
