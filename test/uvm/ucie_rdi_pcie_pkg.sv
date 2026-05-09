
`timescale 1ns/1ps

package ucie_rdi_pcie_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    // --- UCIe RDI Transaction ---
    class ucie_rdi_transaction extends uvm_sequence_item;
        rand logic [3:0]  valid;
        rand logic [63:0] data; // 4 lanes * 16 bits
        rand logic [3:0]  error;
        logic [3:0]       ready;
        logic [3:0]       flow_ctrl;

        `uvm_object_utils_begin(ucie_rdi_transaction)
            `uvm_field_int(valid,     UVM_ALL_ON)
            `uvm_field_int(data,      UVM_ALL_ON)
            `uvm_field_int(error,     UVM_ALL_ON)
            `uvm_field_int(ready,     UVM_ALL_ON)
            `uvm_field_int(flow_ctrl, UVM_ALL_ON)
        `uvm_object_utils_end

        function new(string name = "ucie_rdi_transaction");
            super.new(name);
        endfunction
    endclass

    // --- PCIe PIPE Transaction ---
    class pcie_pipe_transaction extends uvm_sequence_item;
        rand logic [3:0]   valid;
        rand logic [127:0] data; // 4 lanes * 32 bits
        rand logic [3:0]   error;
        logic [3:0]        ready;

        `uvm_object_utils_begin(pcie_pipe_transaction)
            `uvm_field_int(valid, UVM_ALL_ON)
            `uvm_field_int(data,  UVM_ALL_ON)
            `uvm_field_int(error, UVM_ALL_ON)
            `uvm_field_int(ready, UVM_ALL_ON)
        `uvm_object_utils_end

        function new(string name = "pcie_pipe_transaction");
            super.new(name);
        endfunction
    endclass

    // --- UCIe RDI Driver ---
    class ucie_rdi_driver extends uvm_driver #(ucie_rdi_transaction);
        virtual ucie_rdi_if vif;

        `uvm_component_utils(ucie_rdi_driver)

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        virtual function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(virtual ucie_rdi_if)::get(this, "", "vif", vif))
                `uvm_fatal("DRV", "Could not get vif")
        endfunction

        virtual task run_phase(uvm_phase phase);
            vif.drv_cb.valid <= '0;
            vif.drv_cb.data  <= '0;
            vif.drv_cb.error <= '0;

            forever begin
                seq_item_port.get_next_item(req);
                drive_item(req);
                seq_item_port.item_done();
            end
        endtask

        task drive_item(ucie_rdi_transaction item);
            @(vif.drv_cb);
            vif.drv_cb.valid <= item.valid;
            vif.drv_cb.data  <= item.data;
            vif.drv_cb.error <= item.error;
            
            // Handshake logic: wait for ready if valid is high
            // Note: Simplification here, in a real agent we'd handle lane-by-lane ready
            while ((vif.drv_cb.valid & vif.drv_cb.ready) == 0 && vif.drv_cb.valid != 0) begin
                @(vif.drv_cb);
            end
            
            // Hold for one cycle of handshake
            @(vif.drv_cb);
            vif.drv_cb.valid <= '0;
        endtask
    endclass

    // --- UCIe RDI Monitor ---
    class ucie_rdi_monitor extends uvm_monitor;
        virtual ucie_rdi_if vif;
        uvm_analysis_port #(ucie_rdi_transaction) ap;

        `uvm_component_utils(ucie_rdi_monitor)

        function new(string name, uvm_component parent);
            super.new(name, parent);
            ap = new("ap", this);
        endfunction

        virtual function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(virtual ucie_rdi_if)::get(this, "", "vif", vif))
                `uvm_fatal("MON", "Could not get vif")
        endfunction

        virtual task run_phase(uvm_phase phase);
            forever begin
                @(vif.mon_cb);
                if (vif.mon_cb.valid != 0 && (vif.mon_cb.valid & vif.mon_cb.ready) != 0) begin
                    ucie_rdi_transaction tr = ucie_rdi_transaction::type_id::create("tr");
                    tr.valid = vif.mon_cb.valid;
                    tr.ready = vif.mon_cb.ready;
                    tr.data  = vif.mon_cb.data;
                    tr.error = vif.mon_cb.error;
                    tr.flow_ctrl = vif.mon_cb.flow_ctrl;
                    ap.write(tr);
                end
            end
        endtask
    endclass

    // --- Sequencer ---
    typedef uvm_sequencer #(ucie_rdi_transaction) ucie_rdi_sequencer;

    // --- Agent ---
    class ucie_rdi_agent extends uvm_agent;
        ucie_rdi_driver    drv;
        ucie_rdi_monitor   mon;
        ucie_rdi_sequencer sqr;

        `uvm_component_utils(ucie_rdi_agent)

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        virtual function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            mon = ucie_rdi_monitor::type_id::create("mon", this);
            if (get_is_active() == UVM_ACTIVE) begin
                drv = ucie_rdi_driver::type_id::create("drv", this);
                sqr = ucie_rdi_sequencer::type_id::create("sqr", this);
            end
        endfunction

        virtual function void connect_phase(uvm_phase phase);
            if (get_is_active() == UVM_ACTIVE) begin
                drv.seq_item_port.connect(sqr.seq_item_export);
            end
        endfunction
    endclass

    // --- PIPE Monitor (Mirroring above for brevity) ---
    class pcie_pipe_monitor extends uvm_monitor;
        virtual pcie_pipe_if vif;
        uvm_analysis_port #(pcie_pipe_transaction) ap;

        `uvm_component_utils(pcie_pipe_monitor)

        function new(string name, uvm_component parent);
            super.new(name, parent);
            ap = new("ap", this);
        endfunction

        virtual function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(virtual pcie_pipe_if)::get(this, "", "vif", vif))
                `uvm_fatal("MON", "Could not get vif")
        endfunction

        virtual task run_phase(uvm_phase phase);
            forever begin
                @(vif.mon_cb);
                if (vif.mon_cb.valid != 0 && (vif.mon_cb.valid & vif.mon_cb.ready) != 0) begin
                    pcie_pipe_transaction tr = pcie_pipe_transaction::type_id::create("tr");
                    tr.valid = vif.mon_cb.valid;
                    tr.ready = vif.mon_cb.ready;
                    tr.data  = vif.mon_cb.data;
                    tr.error = vif.mon_cb.error;
                    ap.write(tr);
                end
            end
        endtask
    endclass

    class pcie_pipe_agent extends uvm_agent;
        pcie_pipe_monitor mon;
        `uvm_component_utils(pcie_pipe_agent)
        function new(string name, uvm_component parent); super.new(name, parent); endfunction
        virtual function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            mon = pcie_pipe_monitor::type_id::create("mon", this);
        endfunction
    endclass

    // --- Scoreboard ---
    class ucie_rdi_pcie_scoreboard extends uvm_scoreboard;
        uvm_analysis_imp_rdi #(ucie_rdi_transaction, ucie_rdi_pcie_scoreboard) imp_rdi;
        uvm_analysis_imp_pipe #(pcie_pipe_transaction, ucie_rdi_pcie_scoreboard) imp_pipe;

        // Expectation queues per lane
        ucie_rdi_transaction tx_exp_q[4][$];

        `uvm_component_utils(ucie_rdi_pcie_scoreboard)

        `uvm_analysis_imp_decl(_rdi)
        `uvm_analysis_imp_decl(_pipe)

        function new(string name, uvm_component parent);
            super.new(name, parent);
            imp_rdi = new("imp_rdi", this);
            imp_pipe = new("imp_pipe", this);
        endfunction

        function void write_rdi(ucie_rdi_transaction tr);
            for (int i = 0; i < 4; i++) begin
                if (tr.valid[i] && tr.ready[i]) begin
                    ucie_rdi_transaction exp = ucie_rdi_transaction::type_id::create("exp");
                    exp.copy(tr);
                    tx_exp_q[i].push_back(exp);
                end
            end
        endfunction

        function void write_pipe(pcie_pipe_transaction tr);
            for (int i = 0; i < 4; i++) begin
                if (tr.valid[i] && tr.ready[i]) begin
                    if (tx_exp_q[i].size() == 0) begin
                        `uvm_error("SB", $sformatf("Unexpected PIPE beat on lane %0d", i))
                    end else begin
                        ucie_rdi_transaction exp = tx_exp_q[i].pop_front();
                        if (tr.data[i*32 +: 16] != exp.data[i*16 +: 16]) begin
                            `uvm_error("SB", $sformatf("Mismatch lane %0d data: exp=%h got=%h",
                                                      i, exp.data[i*16 +: 16], tr.data[i*32 +: 16]))
                        end
                        if (tr.data[i*32+16 +: 16] !== 16'h0) begin
                            `uvm_error("SB", $sformatf("Lane %0d: PIPE upper 16 bits not zero-extended: %h",
                                                      i, tr.data[i*32 +: 32]))
                        end
                        if (tr.error[i] !== exp.error[i]) begin
                            `uvm_error("SB", $sformatf("Mismatch lane %0d error: exp=%b got=%b", i, exp.error[i], tr.error[i]))
                        end
                    end
                end
            end
        endfunction

        virtual function void check_phase(uvm_phase phase);
            super.check_phase(phase);
            for (int i = 0; i < 4; i++) begin
                if (tx_exp_q[i].size() != 0) begin
                    `uvm_error("SB_DRAIN", $sformatf("TX lane %0d: %0d expected beats still queued at end of test",
                                                     i, tx_exp_q[i].size()))
                end
            end
        endfunction
    endclass

    // --- Environment ---
    class ucie_rdi_pcie_env extends uvm_env;
        ucie_rdi_agent    rdi_agent;
        pcie_pipe_agent   pipe_agent;
        ucie_rdi_pcie_scoreboard sb;

        `uvm_component_utils(ucie_rdi_pcie_env)

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        virtual function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            rdi_agent  = ucie_rdi_agent::type_id::create("rdi_agent", this);
            pipe_agent = pcie_pipe_agent::type_id::create("pipe_agent", this);
            sb         = ucie_rdi_pcie_scoreboard::type_id::create("sb", this);
        endfunction

        virtual function void connect_phase(uvm_phase phase);
            rdi_agent.mon.ap.connect(sb.imp_rdi);
            pipe_agent.mon.ap.connect(sb.imp_pipe);
        endfunction
    endclass

    import ucie_rdi_seq_lib::*;

    // --- Base Test ---
    class ucie_rdi_pcie_base_test extends uvm_test;
        ucie_rdi_pcie_env env;
        `uvm_component_utils(ucie_rdi_pcie_base_test)
        function new(string name, uvm_component parent); super.new(name, parent); endfunction
        virtual function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            env = ucie_rdi_pcie_env::type_id::create("env", this);
        endfunction
    endclass

    // --- Sanity Test (Mirrors original TB) ---
    class ucie_rdi_pcie_sanity_test extends ucie_rdi_pcie_base_test;
        `uvm_component_utils(ucie_rdi_pcie_sanity_test)
        function new(string name, uvm_component parent); super.new(name, parent); endfunction

        virtual task run_phase(uvm_phase phase);
            ucie_rdi_single_lane_seq single_seq;
            ucie_rdi_multi_lane_seq multi_seq;
            ucie_rdi_error_seq      err_seq;
            ucie_rdi_flow_ctrl_seq  fc_seq;

            phase.raise_objection(this);
            
            `uvm_info("TEST", "Starting Single Lane Sequence", UVM_LOW)
            single_seq = ucie_rdi_single_lane_seq::type_id::create("single_seq");
            single_seq.start(env.rdi_agent.sqr);
            
            #100ns;

            `uvm_info("TEST", "Starting Multi Lane Sequence", UVM_LOW)
            multi_seq = ucie_rdi_multi_lane_seq::type_id::create("multi_seq");
            multi_seq.start(env.rdi_agent.sqr);

            #100ns;

            `uvm_info("TEST", "Starting Error Sequence", UVM_LOW)
            err_seq = ucie_rdi_error_seq::type_id::create("err_seq");
            err_seq.start(env.rdi_agent.sqr);

            #100ns;

            `uvm_info("TEST", "Starting Flow Control Sequence", UVM_LOW)
            fc_seq = ucie_rdi_flow_ctrl_seq::type_id::create("fc_seq");
            fc_seq.start(env.rdi_agent.sqr);

            #1000ns;
            phase.drop_objection(this);
        endtask
    endclass



endpackage
