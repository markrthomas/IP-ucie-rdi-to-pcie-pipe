
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
            repeat (20) begin
                ucie_rdi_transaction tr;
                tr = ucie_rdi_transaction::type_id::create("tr");
                start_item(tr);
                if (!tr.randomize() with { valid == 4'b0010; data == 64'h0000_0000_1234_0000; error == 4'b0000; })
                    `uvm_error("SEQ", "Randomization failed")
                finish_item(tr);
            end
        endtask
    endclass


endpackage
