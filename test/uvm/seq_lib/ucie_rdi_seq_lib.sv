
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


endpackage
