
`timescale 1ns/1ps

package ucie_rdi_seq_lib;
    import uvm_pkg::*;
    import ucie_rdi_pcie_pkg::*;
    `include "uvm_macros.svh"

    // --- Base Sequence ---
    class ucie_rdi_base_seq extends uvm_sequence #(ucie_rdi_transaction);
        `uvm_object_utils(ucie_rdi_base_seq)
        function new(string name = "ucie_rdi_base_seq"); super.new(name); endfunction
    endclass

    // --- Single Lane Sequence ---
    class ucie_rdi_single_lane_seq extends ucie_rdi_base_seq;
        `uvm_object_utils(ucie_rdi_single_lane_seq)
        function new(string name = "ucie_rdi_single_lane_seq"); super.new(name); endfunction

        virtual task body();
            ucie_rdi_transaction tr;
            tr = ucie_rdi_transaction::type_id::create("tr");
            start_item(tr);
            if (!tr.randomize() with { valid == 4'b0001; data == 64'hDEAD; error == 4'b0000; })
                `uvm_error("SEQ", "Randomization failed")
            finish_item(tr);
        endtask
    endclass

    // --- Multi Lane Sequence ---
    class ucie_rdi_multi_lane_seq extends ucie_rdi_base_seq;
        `uvm_object_utils(ucie_rdi_multi_lane_seq)
        function new(string name = "ucie_rdi_multi_lane_seq"); super.new(name); endfunction

        virtual task body();
            ucie_rdi_transaction tr;
            tr = ucie_rdi_transaction::type_id::create("tr");
            start_item(tr);
            if (!tr.randomize() with { 
                valid == 4'b1111; 
                data == 64'hDDDD_CCCC_BBBB_AAAA; 
                error == 4'b0000; 
            })
                `uvm_error("SEQ", "Randomization failed")
            finish_item(tr);
        endtask
    endclass

    // --- Error Propagation Sequence ---
    class ucie_rdi_error_seq extends ucie_rdi_base_seq;
        `uvm_object_utils(ucie_rdi_error_seq)
        function new(string name = "ucie_rdi_error_seq"); super.new(name); endfunction

        virtual task body();
            ucie_rdi_transaction tr;
            tr = ucie_rdi_transaction::type_id::create("tr");
            start_item(tr);
            if (!tr.randomize() with { valid == 4'b0100; data == 64'hEEEE_1234_0000_0000; error == 4'b0100; })
                `uvm_error("SEQ", "Randomization failed")
            finish_item(tr);
        endtask
    endclass

    // --- Flow Control Sequence ---
    class ucie_rdi_flow_ctrl_seq extends ucie_rdi_base_seq;
        `uvm_object_utils(ucie_rdi_flow_ctrl_seq)
        function new(string name = "ucie_rdi_flow_ctrl_seq"); super.new(name); endfunction

        virtual task body();
            repeat (32) begin
                ucie_rdi_transaction tr;
                tr = ucie_rdi_transaction::type_id::create("tr");
                start_item(tr);
                if (!tr.randomize() with { valid == 4'b0010; data == 64'h0000_0000_1234_0000; error == 4'b0000; })
                    `uvm_error("SEQ", "Randomization failed")
                finish_item(tr);
            end
        endtask
    endclass

    // --- FIFO-Full Sequence (all lanes) ---
    // Drives all NUM_LANES simultaneously for more beats than the TX FIFO can
    // hold (BUFFER_DEPTH=16 + one output register). Paired with a deep PIPE
    // backpressure so the read side never drains: every lane's TX FIFO fills,
    // asserting rdi_flow_ctrl on all lanes and stalling the driver
    // (hold-under-stall). Per-lane payloads are distinct and increment per
    // beat so the scoreboard also proves in-order, lossless drain once ready
    // is released.
    class ucie_rdi_fifo_full_seq extends ucie_rdi_base_seq;
        `uvm_object_utils(ucie_rdi_fifo_full_seq)
        function new(string name = "ucie_rdi_fifo_full_seq"); super.new(name); endfunction

        virtual task body();
            ucie_rdi_transaction tr;
            for (int b = 0; b < 24; b++) begin
                logic [RDI_BUS_WIDTH-1:0] payload;
                for (int i = 0; i < NUM_LANES; i++) begin
                    payload[i*RDI_DATA_WIDTH +: RDI_DATA_WIDTH] =
                        (b * NUM_LANES) + i + 1;
                end
                tr = ucie_rdi_transaction::type_id::create($sformatf("fifo_full_%0d", b));
                start_item(tr);
                if (!tr.randomize() with { valid == '1; data == payload; error == '0; })
                    `uvm_error("SEQ", "Randomization failed")
                finish_item(tr);
            end
        endtask
    endclass

    // --- CRC Smoke Sequence ---
    class ucie_rdi_crc_seq extends ucie_rdi_base_seq;
        `uvm_object_utils(ucie_rdi_crc_seq)
        function new(string name = "ucie_rdi_crc_seq"); super.new(name); endfunction

        virtual task body();
            uvm_event_pool event_pool;
            ucie_rdi_transaction tr;

            event_pool = uvm_event_pool::get_global_pool();
            event_pool.get("crc_start").trigger();

            tr = ucie_rdi_transaction::type_id::create("crc_beat_0");
            start_item(tr);
            if (!tr.randomize() with { valid == 4'b0001; data == 64'h0000_0000_0000_0001; error == 4'b0000; })
                `uvm_error("SEQ", "Randomization failed")
            finish_item(tr);

            tr = ucie_rdi_transaction::type_id::create("crc_beat_1");
            start_item(tr);
            if (!tr.randomize() with { valid == 4'b0001; data == 64'h0000_0000_0000_0002; error == 4'b0000; })
                `uvm_error("SEQ", "Randomization failed")
            finish_item(tr);

            #100ns;
            event_pool.get("crc_stop").trigger();
        endtask
    endclass

    // --- PIPE Backpressure Sequence ---
    class pcie_pipe_backpressure_seq extends uvm_sequence #(pcie_pipe_ready_transaction);
        `uvm_object_utils(pcie_pipe_backpressure_seq)
        function new(string name = "pcie_pipe_backpressure_seq"); super.new(name); endfunction

        virtual task body();
            pcie_pipe_ready_transaction tr;

            tr = pcie_pipe_ready_transaction::type_id::create("hold_low");
            start_item(tr);
            if (!tr.randomize() with { ready == 4'b0000; hold_cycles == 48; })
                `uvm_error("SEQ", "Randomization failed")
            finish_item(tr);

            tr = pcie_pipe_ready_transaction::type_id::create("release");
            start_item(tr);
            if (!tr.randomize() with { ready == 4'b1111; hold_cycles == 16; })
                `uvm_error("SEQ", "Randomization failed")
            finish_item(tr);

            tr = pcie_pipe_ready_transaction::type_id::create("reassert_low");
            start_item(tr);
            if (!tr.randomize() with { ready == 4'b0000; hold_cycles == 16; })
                `uvm_error("SEQ", "Randomization failed")
            finish_item(tr);

            tr = pcie_pipe_ready_transaction::type_id::create("final_release");
            start_item(tr);
            if (!tr.randomize() with { ready == 4'b1111; hold_cycles == 24; })
                `uvm_error("SEQ", "Randomization failed")
            finish_item(tr);
        endtask
    endclass

    // --- Deep PIPE Backpressure Sequence ---
    // Holds PIPE TX ready low long enough for a sustained RDI source to fill
    // every lane's TX FIFO (drives rdi_flow_ctrl on all lanes), then releases
    // ready for an extended window so the FIFOs fully drain. Pair with
    // ucie_rdi_fifo_full_seq on the RDI TX sequencer.
    class pcie_pipe_deep_backpressure_seq extends uvm_sequence #(pcie_pipe_ready_transaction);
        `uvm_object_utils(pcie_pipe_deep_backpressure_seq)
        function new(string name = "pcie_pipe_deep_backpressure_seq"); super.new(name); endfunction

        virtual task body();
            pcie_pipe_ready_transaction tr;

            tr = pcie_pipe_ready_transaction::type_id::create("deep_hold_low");
            start_item(tr);
            if (!tr.randomize() with { ready == 4'b0000; hold_cycles == 128; })
                `uvm_error("SEQ", "Randomization failed")
            finish_item(tr);

            tr = pcie_pipe_ready_transaction::type_id::create("deep_release");
            start_item(tr);
            if (!tr.randomize() with { ready == 4'b1111; hold_cycles == 400; })
                `uvm_error("SEQ", "Randomization failed")
            finish_item(tr);
        endtask
    endclass

    // --- PIPE RX Sequence ---
    class pcie_pipe_rx_seq extends uvm_sequence #(pcie_pipe_transaction);
        `uvm_object_utils(pcie_pipe_rx_seq)
        function new(string name = "pcie_pipe_rx_seq"); super.new(name); endfunction

        virtual task body();
            pcie_pipe_transaction tr;

            tr = pcie_pipe_transaction::type_id::create("rx_all_lanes");
            start_item(tr);
            if (!tr.randomize() with {
                valid == 4'b1111;
                data == 128'h1111_0001_2222_0002_3333_0003_4444_0004;
                error == 4'b0000;
            })
                `uvm_error("SEQ", "Randomization failed")
            finish_item(tr);

            tr = pcie_pipe_transaction::type_id::create("rx_sparse");
            start_item(tr);
            if (!tr.randomize() with {
                valid == 4'b0101;
                data == 128'h0000_0000_CCCC_2222_0000_0000_AAAA_1111;
                error == 4'b0100;
            })
                `uvm_error("SEQ", "Randomization failed")
            finish_item(tr);
        endtask
    endclass

    // --- PIPE RX Single-Lane Sequence ---
    // Drives a single lane-0 RX beat; lower 16 bits (0xBEEF) are the
    // payload converted back onto the RDI RX bus.
    class pcie_pipe_rx_single_lane_seq extends uvm_sequence #(pcie_pipe_transaction);
        `uvm_object_utils(pcie_pipe_rx_single_lane_seq)
        function new(string name = "pcie_pipe_rx_single_lane_seq"); super.new(name); endfunction

        virtual task body();
            pcie_pipe_transaction tr;
            tr = pcie_pipe_transaction::type_id::create("rx_lane0");
            start_item(tr);
            if (!tr.randomize() with {
                valid == 4'b0001;
                data == 128'h0000_0000_0000_0000_0000_0000_0000_BEEF;
                error == 4'b0000;
            })
                `uvm_error("SEQ", "Randomization failed")
            finish_item(tr);
        endtask
    endclass

    // --- PIPE RX Error Sequence ---
    // Lane-1 RX beat with error asserted; exercises reverse-path error
    // propagation (lane 1 occupies data[63:32], low half at [47:32]).
    class pcie_pipe_rx_error_seq extends uvm_sequence #(pcie_pipe_transaction);
        `uvm_object_utils(pcie_pipe_rx_error_seq)
        function new(string name = "pcie_pipe_rx_error_seq"); super.new(name); endfunction

        virtual task body();
            pcie_pipe_transaction tr;
            tr = pcie_pipe_transaction::type_id::create("rx_lane1_err");
            start_item(tr);
            if (!tr.randomize() with {
                valid == 4'b0010;
                data == 128'h0000_0000_0000_0000_0000_CAFE_0000_0000;
                error == 4'b0010;
            })
                `uvm_error("SEQ", "Randomization failed")
            finish_item(tr);
        endtask
    endclass

    // --- PIPE RX Burst Sequence ---
    // Four back-to-back lane-0 beats with incrementing payloads; checks
    // reverse-path ordering through the RX FIFO via the scoreboard queue.
    class pcie_pipe_rx_burst_seq extends uvm_sequence #(pcie_pipe_transaction);
        `uvm_object_utils(pcie_pipe_rx_burst_seq)
        function new(string name = "pcie_pipe_rx_burst_seq"); super.new(name); endfunction

        virtual task body();
            pcie_pipe_transaction tr;
            for (int b = 0; b < 4; b++) begin
                tr = pcie_pipe_transaction::type_id::create($sformatf("rx_burst_%0d", b));
                start_item(tr);
                if (!tr.randomize() with {
                    valid == 4'b0001;
                    data == (b + 1);
                    error == 4'b0000;
                })
                    `uvm_error("SEQ", "Randomization failed")
                finish_item(tr);
            end
        endtask
    endclass

    // --- PIPE RX Randomized Traffic Sequence ---
    // Twelve constrained-random RX beats (at least one lane valid, random
    // data and error). The mirrored RX scoreboard self-checks against the
    // observed PIPE RX input, so no precomputed expected values are needed.
    class pcie_pipe_rx_rand_seq extends uvm_sequence #(pcie_pipe_transaction);
        `uvm_object_utils(pcie_pipe_rx_rand_seq)
        function new(string name = "pcie_pipe_rx_rand_seq"); super.new(name); endfunction

        virtual task body();
            pcie_pipe_transaction tr;
            repeat (12) begin
                tr = pcie_pipe_transaction::type_id::create("rx_rand");
                start_item(tr);
                if (!tr.randomize() with { valid != 0; })
                    `uvm_error("SEQ", "Randomization failed")
                finish_item(tr);
            end
        endtask
    endclass

    // --- RDI RX Backpressure Sequence ---
    // Stalls and releases rdi_rx_ready to exercise reverse-path (PIPE -> RDI)
    // FIFO backpressure. Ends with ready high so queued beats drain.
    class ucie_rdi_rx_backpressure_seq extends uvm_sequence #(pcie_pipe_ready_transaction);
        `uvm_object_utils(ucie_rdi_rx_backpressure_seq)
        function new(string name = "ucie_rdi_rx_backpressure_seq"); super.new(name); endfunction

        virtual task body();
            pcie_pipe_ready_transaction tr;

            tr = pcie_pipe_ready_transaction::type_id::create("rx_hold_low");
            start_item(tr);
            if (!tr.randomize() with { ready == 4'b0000; hold_cycles == 32; })
                `uvm_error("SEQ", "Randomization failed")
            finish_item(tr);

            tr = pcie_pipe_ready_transaction::type_id::create("rx_release");
            start_item(tr);
            if (!tr.randomize() with { ready == 4'b1111; hold_cycles == 16; })
                `uvm_error("SEQ", "Randomization failed")
            finish_item(tr);

            tr = pcie_pipe_ready_transaction::type_id::create("rx_reassert_low");
            start_item(tr);
            if (!tr.randomize() with { ready == 4'b0000; hold_cycles == 12; })
                `uvm_error("SEQ", "Randomization failed")
            finish_item(tr);

            tr = pcie_pipe_ready_transaction::type_id::create("rx_final_release");
            start_item(tr);
            if (!tr.randomize() with { ready == 4'b1111; hold_cycles == 24; })
                `uvm_error("SEQ", "Randomization failed")
            finish_item(tr);
        endtask
    endclass


endpackage
