
`timescale 1ns/1ps

package ucie_rdi_pcie_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"
    `uvm_analysis_imp_decl(_rdi)
    `uvm_analysis_imp_decl(_pipe)
    `uvm_analysis_imp_decl(_covrdi)
    `uvm_analysis_imp_decl(_covpipe)
    `uvm_analysis_imp_decl(_covrxrdi)
    `uvm_analysis_imp_decl(_covrxpipe)
    `uvm_analysis_imp_decl(_rxrdi)
    `uvm_analysis_imp_decl(_rxpipe)

    // ------------------------------------------------------------------
    // Centralized DUT dimensions -- single source of truth for the UVM
    // environment. The per-lane names mirror the RTL parameters exactly
    // (ucie_rdi_to_pcie_pipe_bridge #(.NUM_LANES, .RDI_DATA_WIDTH,
    // .PIPE_DATA_WIDTH)); uvm_test_top passes these same values into the
    // interfaces and the DUT, so transaction/scoreboard widths cannot
    // silently diverge from the DUT. Change lane/data geometry here.
    //
    // Note: the fixed stimulus vectors in seq_lib (e.g. valid == 4'b0001)
    // and the covergroup bins remain 4-lane specific; a NUM_LANES sweep
    // would additionally require generalizing those.
    // ------------------------------------------------------------------
    parameter int NUM_LANES       = 4;
    parameter int RDI_DATA_WIDTH  = 16;  // bits per lane on the RDI side
    parameter int PIPE_DATA_WIDTH = 32;  // bits per lane on the PIPE side
    parameter int RDI_BUS_WIDTH   = NUM_LANES * RDI_DATA_WIDTH;
    parameter int PIPE_BUS_WIDTH  = NUM_LANES * PIPE_DATA_WIDTH;

    // --- UCIe RDI Transaction ---
    class ucie_rdi_transaction extends uvm_sequence_item;
        rand logic [NUM_LANES-1:0]     valid;
        rand logic [RDI_BUS_WIDTH-1:0] data; // NUM_LANES * RDI_DATA_WIDTH bits
        rand logic [NUM_LANES-1:0]     error;
        logic [NUM_LANES-1:0]          ready;
        logic [NUM_LANES-1:0]          flow_ctrl;

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
        rand logic [NUM_LANES-1:0]      valid;
        rand logic [PIPE_BUS_WIDTH-1:0] data; // NUM_LANES * PIPE_DATA_WIDTH bits
        rand logic [NUM_LANES-1:0]      error;
        logic [NUM_LANES-1:0]           ready;
        // Observation-only CRC status (populated by the TX PIPE monitor).
        logic [NUM_LANES-1:0]           crc_enable;
        logic [NUM_LANES-1:0]           crc_error;

        `uvm_object_utils_begin(pcie_pipe_transaction)
            `uvm_field_int(valid,      UVM_ALL_ON)
            `uvm_field_int(data,       UVM_ALL_ON)
            `uvm_field_int(error,      UVM_ALL_ON)
            `uvm_field_int(ready,      UVM_ALL_ON)
            `uvm_field_int(crc_enable, UVM_ALL_ON)
            `uvm_field_int(crc_error,  UVM_ALL_ON)
        `uvm_object_utils_end

        function new(string name = "pcie_pipe_transaction");
            super.new(name);
        endfunction
    endclass

    // --- PIPE Ready Control Transaction ---
    class pcie_pipe_ready_transaction extends uvm_sequence_item;
        rand logic [NUM_LANES-1:0] ready;
        rand int unsigned hold_cycles;

        constraint c_hold_cycles { hold_cycles inside {[1:32]}; }

        `uvm_object_utils_begin(pcie_pipe_ready_transaction)
            `uvm_field_int(ready,       UVM_ALL_ON)
            `uvm_field_int(hold_cycles, UVM_ALL_ON)
        `uvm_object_utils_end

        function new(string name = "pcie_pipe_ready_transaction");
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
                    tr.crc_enable = vif.mon_cb.crc_enable;
                    tr.crc_error  = vif.mon_cb.crc_error;
                    ap.write(tr);
                end
            end
        endtask
    endclass

    // --- PIPE Ready Driver ---
    class pcie_pipe_ready_driver extends uvm_driver #(pcie_pipe_ready_transaction);
        virtual pcie_pipe_if vif;
        covergroup cg_ready with function sample(logic [NUM_LANES-1:0] ready, int unsigned hold_cycles);
            option.per_instance = 1;
            cp_ready: coverpoint ready {
                bins all_low = {4'b0000};
                bins all_high = {4'b1111};
                bins partial[] = {[4'b0001:4'b1110]};
            }
            cp_hold_cycles: coverpoint hold_cycles {
                bins short = {[1:8]};
                bins medium = {[9:24]};
                bins long = {[25:64]};
            }
            ready_x_hold: cross cp_ready, cp_hold_cycles;
        endgroup

        `uvm_component_utils(pcie_pipe_ready_driver)

        function new(string name, uvm_component parent);
            super.new(name, parent);
            cg_ready = new();
        endfunction

        virtual function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(virtual pcie_pipe_if)::get(this, "", "vif", vif))
                `uvm_fatal("PDRV", "Could not get vif")
        endfunction

        virtual task run_phase(uvm_phase phase);
            vif.ctrl_cb.ready <= '1;

            forever begin
                seq_item_port.get_next_item(req);
                cg_ready.sample(req.ready, req.hold_cycles);
                @(vif.ctrl_cb);
                vif.ctrl_cb.ready <= req.ready;
                repeat (req.hold_cycles) @(vif.ctrl_cb);
                seq_item_port.item_done();
            end
        endtask

        virtual function void report_phase(uvm_phase phase);
            super.report_phase(phase);
            `uvm_info("COV",
                      $sformatf("PIPE ready-driver coverage: %0.2f%%",
                                cg_ready.get_inst_coverage()),
                      UVM_LOW)
        endfunction
    endclass

    typedef uvm_sequencer #(pcie_pipe_ready_transaction) pcie_pipe_ready_sequencer;

    // --- PIPE RX Driver ---
    class pcie_pipe_rx_driver extends uvm_driver #(pcie_pipe_transaction);
        virtual pcie_pipe_if vif;

        `uvm_component_utils(pcie_pipe_rx_driver)

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        virtual function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(virtual pcie_pipe_if)::get(this, "", "vif", vif))
                `uvm_fatal("RXDRV", "Could not get vif")
        endfunction

        virtual task run_phase(uvm_phase phase);
            vif.drv_cb.valid <= '0;
            vif.drv_cb.data  <= '0;
            vif.drv_cb.error <= '0;

            forever begin
                seq_item_port.get_next_item(req);
                @(vif.drv_cb);
                vif.drv_cb.valid <= req.valid;
                vif.drv_cb.data  <= req.data;
                vif.drv_cb.error <= req.error;
                while ((vif.drv_cb.valid & vif.drv_cb.ready) == 0 && vif.drv_cb.valid != 0) begin
                    @(vif.drv_cb);
                end
                @(vif.drv_cb);
                vif.drv_cb.valid <= '0;
                seq_item_port.item_done();
            end
        endtask
    endclass

    typedef uvm_sequencer #(pcie_pipe_transaction) pcie_pipe_rx_sequencer;

    class pcie_pipe_rx_agent extends uvm_agent;
        pcie_pipe_rx_driver    drv;
        pcie_pipe_rx_sequencer sqr;

        `uvm_component_utils(pcie_pipe_rx_agent)

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        virtual function void build_phase(uvm_phase phase);
            uvm_active_passive_enum mode;
            super.build_phase(phase);
            if (uvm_config_db#(uvm_active_passive_enum)::get(this, "", "is_active", mode)) begin
                set_is_active(mode);
            end else begin
                set_is_active(UVM_PASSIVE);
            end
            if (get_is_active() == UVM_ACTIVE) begin
                drv = pcie_pipe_rx_driver::type_id::create("drv", this);
                sqr = pcie_pipe_rx_sequencer::type_id::create("sqr", this);
            end
        endfunction

        virtual function void connect_phase(uvm_phase phase);
            if (get_is_active() == UVM_ACTIVE) begin
                drv.seq_item_port.connect(sqr.seq_item_export);
            end
        endfunction
    endclass

    // --- UVM Coverage Collector ---
    class ucie_rdi_pcie_coverage extends uvm_component;
        uvm_analysis_imp_covrdi #(ucie_rdi_transaction, ucie_rdi_pcie_coverage) imp_rdi;
        uvm_analysis_imp_covpipe #(pcie_pipe_transaction, ucie_rdi_pcie_coverage) imp_pipe;
        uvm_analysis_imp_covrxrdi #(ucie_rdi_transaction, ucie_rdi_pcie_coverage) imp_rx_rdi;
        uvm_analysis_imp_covrxpipe #(pcie_pipe_transaction, ucie_rdi_pcie_coverage) imp_rx_pipe;

        `uvm_component_utils(ucie_rdi_pcie_coverage)

        covergroup cg_rdi with function sample(logic [NUM_LANES-1:0] valid, logic [NUM_LANES-1:0] error, logic [NUM_LANES-1:0] flow_ctrl);
            option.per_instance = 1;
            cp_valid: coverpoint valid {
                bins single[] = {4'b0001, 4'b0010, 4'b0100, 4'b1000};
                bins multi[] = {4'b0011, 4'b0110, 4'b1100, 4'b1111};
            }
            cp_error: coverpoint error {
                bins none = {4'b0000};
                bins any[] = {[4'b0001:4'b1111]};
            }
            cp_flow_ctrl: coverpoint flow_ctrl {
                bins none = {4'b0000};
                bins any[] = {[4'b0001:4'b1111]};
            }
            valid_x_error: cross cp_valid, cp_error;
        endgroup

        covergroup cg_pipe with function sample(logic [NUM_LANES-1:0] valid, logic [NUM_LANES-1:0] error);
            option.per_instance = 1;
            cp_valid: coverpoint valid {
                bins single[] = {4'b0001, 4'b0010, 4'b0100, 4'b1000};
                bins multi[] = {4'b0011, 4'b0110, 4'b1100, 4'b1111};
            }
            cp_error: coverpoint error {
                bins none = {4'b0000};
                bins any[] = {[4'b0001:4'b1111]};
            }
            valid_x_error: cross cp_valid, cp_error;
        endgroup

        // RX direction (PIPE -> RDI): mirrors the TX covergroups so the
        // reverse path is measured, not just the TX path.
        covergroup cg_rx_pipe with function sample(logic [NUM_LANES-1:0] valid, logic [NUM_LANES-1:0] error);
            option.per_instance = 1;
            cp_valid: coverpoint valid {
                bins single[] = {4'b0001, 4'b0010, 4'b0100, 4'b1000};
                bins multi[] = {4'b0011, 4'b0110, 4'b1100, 4'b1111};
            }
            cp_error: coverpoint error {
                bins none = {4'b0000};
                bins any[] = {[4'b0001:4'b1111]};
            }
            valid_x_error: cross cp_valid, cp_error;
        endgroup

        covergroup cg_rx_rdi with function sample(logic [NUM_LANES-1:0] valid, logic [NUM_LANES-1:0] error);
            option.per_instance = 1;
            cp_valid: coverpoint valid {
                bins single[] = {4'b0001, 4'b0010, 4'b0100, 4'b1000};
                bins multi[] = {4'b0011, 4'b0110, 4'b1100, 4'b1111};
            }
            cp_error: coverpoint error {
                bins none = {4'b0000};
                bins any[] = {[4'b0001:4'b1111]};
            }
            valid_x_error: cross cp_valid, cp_error;
        endgroup

        // Width conversion (RDI 16-bit -> PIPE 32-bit): sample lane 0's
        // PIPE word to confirm the upper half is zero-extended and that a
        // range of payload magnitudes exercise the conversion.
        covergroup cg_pipe_width with function sample(logic [PIPE_DATA_WIDTH-1:0] lane0_word);
            option.per_instance = 1;
            cp_upper: coverpoint lane0_word[RDI_DATA_WIDTH +: (PIPE_DATA_WIDTH-RDI_DATA_WIDTH)] {
                bins zero_extended = {0};
                bins nonzero      = default;
            }
            cp_low_magnitude: coverpoint lane0_word[0 +: RDI_DATA_WIDTH] {
                bins zero       = {0};
                bins byte_range = {[1:(1<<8)-1]};
                bins word_range = {[(1<<8):(1<<RDI_DATA_WIDTH)-1]};
            }
        endgroup

        // FIFO-occupancy proxy: number of RDI lanes asserting flow_ctrl on
        // a beat. flow_ctrl reflects near-full elastic buffers, so this is
        // an observable stand-in for internal FIFO occupancy/backpressure.
        covergroup cg_occupancy with function sample(int unsigned fc_lanes);
            option.per_instance = 1;
            cp_fc_lanes: coverpoint fc_lanes {
                bins none      = {0};
                bins partial   = {[1:NUM_LANES-1]};
                bins all_lanes = {NUM_LANES};
            }
        endgroup

        // CRC enable/error observed on the TX PIPE interface.
        covergroup cg_crc with function sample(logic [NUM_LANES-1:0] crc_enable, logic [NUM_LANES-1:0] crc_error);
            option.per_instance = 1;
            cp_crc_en: coverpoint crc_enable {
                bins disabled    = {0};
                bins any_enabled = {[1:(1<<NUM_LANES)-1]};
            }
            cp_crc_err: coverpoint crc_error {
                bins clean     = {0};
                bins any_error = {[1:(1<<NUM_LANES)-1]};
            }
            crc_en_x_err: cross cp_crc_en, cp_crc_err;
        endgroup

        function new(string name, uvm_component parent);
            super.new(name, parent);
            imp_rdi = new("imp_rdi", this);
            imp_pipe = new("imp_pipe", this);
            imp_rx_rdi = new("imp_rx_rdi", this);
            imp_rx_pipe = new("imp_rx_pipe", this);
            cg_rdi = new();
            cg_pipe = new();
            cg_rx_pipe = new();
            cg_rx_rdi = new();
            cg_pipe_width = new();
            cg_occupancy = new();
            cg_crc = new();
        endfunction

        function void write_covrdi(ucie_rdi_transaction tr);
            cg_rdi.sample(tr.valid, tr.error, tr.flow_ctrl);
            cg_occupancy.sample($countones(tr.flow_ctrl));
        endfunction

        function void write_covpipe(pcie_pipe_transaction tr);
            cg_pipe.sample(tr.valid, tr.error);
            cg_pipe_width.sample(tr.data[0 +: PIPE_DATA_WIDTH]);
            cg_crc.sample(tr.crc_enable, tr.crc_error);
        endfunction

        // PIPE RX stimulus entering the DUT (reverse path source).
        function void write_covrxpipe(pcie_pipe_transaction tr);
            cg_rx_pipe.sample(tr.valid, tr.error);
        endfunction

        // RDI RX beats emerging from the DUT (reverse path sink).
        function void write_covrxrdi(ucie_rdi_transaction tr);
            cg_rx_rdi.sample(tr.valid, tr.error);
        endfunction

        virtual function void report_phase(uvm_phase phase);
            super.report_phase(phase);
            `uvm_info("COV",
                      $sformatf("UVM coverage: RDI=%0.2f%% PIPE=%0.2f%% RX_PIPE=%0.2f%% RX_RDI=%0.2f%% WIDTH=%0.2f%% OCC=%0.2f%% CRC=%0.2f%%",
                                cg_rdi.get_inst_coverage(),
                                cg_pipe.get_inst_coverage(),
                                cg_rx_pipe.get_inst_coverage(),
                                cg_rx_rdi.get_inst_coverage(),
                                cg_pipe_width.get_inst_coverage(),
                                cg_occupancy.get_inst_coverage(),
                                cg_crc.get_inst_coverage()),
                      UVM_LOW)
        endfunction
    endclass

    class pcie_pipe_agent extends uvm_agent;
        pcie_pipe_monitor mon;
        pcie_pipe_ready_driver drv;
        pcie_pipe_ready_sequencer sqr;
        `uvm_component_utils(pcie_pipe_agent)

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        virtual function void build_phase(uvm_phase phase);
            uvm_active_passive_enum mode;
            super.build_phase(phase);
            if (uvm_config_db#(uvm_active_passive_enum)::get(this, "", "is_active", mode)) begin
                set_is_active(mode);
            end else begin
                set_is_active(UVM_PASSIVE);
            end
            mon = pcie_pipe_monitor::type_id::create("mon", this);
            if (get_is_active() == UVM_ACTIVE) begin
                drv = pcie_pipe_ready_driver::type_id::create("drv", this);
                sqr = pcie_pipe_ready_sequencer::type_id::create("sqr", this);
            end
        endfunction

        virtual function void connect_phase(uvm_phase phase);
            if (get_is_active() == UVM_ACTIVE) begin
                drv.seq_item_port.connect(sqr.seq_item_export);
            end
        endfunction
    endclass

    // --- Scoreboard ---
    class ucie_rdi_pcie_scoreboard extends uvm_scoreboard;
        uvm_analysis_imp_rdi #(ucie_rdi_transaction, ucie_rdi_pcie_scoreboard) imp_rdi;
        uvm_analysis_imp_pipe #(pcie_pipe_transaction, ucie_rdi_pcie_scoreboard) imp_pipe;
        uvm_analysis_imp_rxrdi #(ucie_rdi_transaction, ucie_rdi_pcie_scoreboard) imp_rx_rdi;
        uvm_analysis_imp_rxpipe #(pcie_pipe_transaction, ucie_rdi_pcie_scoreboard) imp_rx_pipe;

        // Expectation queues per lane
        ucie_rdi_transaction tx_exp_q[NUM_LANES][$];
        ucie_rdi_transaction rx_exp_q[NUM_LANES][$];

        `uvm_component_utils(ucie_rdi_pcie_scoreboard)

        function new(string name, uvm_component parent);
            super.new(name, parent);
            imp_rdi = new("imp_rdi", this);
            imp_pipe = new("imp_pipe", this);
            imp_rx_rdi = new("imp_rx_rdi", this);
            imp_rx_pipe = new("imp_rx_pipe", this);
        endfunction

        function void write_rdi(ucie_rdi_transaction tr);
            for (int i = 0; i < NUM_LANES; i++) begin
                if (tr.valid[i] && tr.ready[i]) begin
                    ucie_rdi_transaction exp = ucie_rdi_transaction::type_id::create("exp");
                    exp.copy(tr);
                    tx_exp_q[i].push_back(exp);
                end
            end
        endfunction

        function void write_pipe(pcie_pipe_transaction tr);
            for (int i = 0; i < NUM_LANES; i++) begin
                if (tr.valid[i] && tr.ready[i]) begin
                    if (tx_exp_q[i].size() == 0) begin
                        `uvm_error("SB", $sformatf("Unexpected PIPE beat on lane %0d", i))
                    end else begin
                        ucie_rdi_transaction exp = tx_exp_q[i].pop_front();
                        if (tr.data[i*PIPE_DATA_WIDTH +: RDI_DATA_WIDTH] != exp.data[i*RDI_DATA_WIDTH +: RDI_DATA_WIDTH]) begin
                            `uvm_error("SB", $sformatf("Mismatch lane %0d data: exp=%h got=%h",
                                                      i, exp.data[i*RDI_DATA_WIDTH +: RDI_DATA_WIDTH], tr.data[i*PIPE_DATA_WIDTH +: RDI_DATA_WIDTH]))
                        end
                        if (tr.data[i*PIPE_DATA_WIDTH+RDI_DATA_WIDTH +: (PIPE_DATA_WIDTH-RDI_DATA_WIDTH)] !== '0) begin
                            `uvm_error("SB", $sformatf("Lane %0d: PIPE upper %0d bits not zero-extended: %h",
                                                      i, (PIPE_DATA_WIDTH-RDI_DATA_WIDTH), tr.data[i*PIPE_DATA_WIDTH +: PIPE_DATA_WIDTH]))
                        end
                        if (tr.error[i] !== exp.error[i]) begin
                            `uvm_error("SB", $sformatf("Mismatch lane %0d error: exp=%b got=%b", i, exp.error[i], tr.error[i]))
                        end
                    end
                end
            end
        endfunction

        function void write_rxpipe(pcie_pipe_transaction tr);
            for (int i = 0; i < NUM_LANES; i++) begin
                if (tr.valid[i] && tr.ready[i]) begin
                    ucie_rdi_transaction exp = ucie_rdi_transaction::type_id::create("rx_exp");
                    exp.valid = '0;
                    exp.ready = '0;
                    exp.data  = '0;
                    exp.error = '0;
                    exp.data[i*RDI_DATA_WIDTH +: RDI_DATA_WIDTH] = tr.data[i*PIPE_DATA_WIDTH +: RDI_DATA_WIDTH];
                    exp.error[i] = tr.error[i];
                    rx_exp_q[i].push_back(exp);
                end
            end
        endfunction

        function void write_rxrdi(ucie_rdi_transaction tr);
            for (int i = 0; i < NUM_LANES; i++) begin
                if (tr.valid[i] && tr.ready[i]) begin
                    if (rx_exp_q[i].size() == 0) begin
                        `uvm_error("RX_SB", $sformatf("Unexpected RDI RX beat on lane %0d", i))
                    end else begin
                        ucie_rdi_transaction exp = rx_exp_q[i].pop_front();
                        if (tr.data[i*RDI_DATA_WIDTH +: RDI_DATA_WIDTH] != exp.data[i*RDI_DATA_WIDTH +: RDI_DATA_WIDTH]) begin
                            `uvm_error("RX_SB", $sformatf("Mismatch RX lane %0d data: exp=%h got=%h",
                                                          i, exp.data[i*RDI_DATA_WIDTH +: RDI_DATA_WIDTH], tr.data[i*RDI_DATA_WIDTH +: RDI_DATA_WIDTH]))
                        end
                        if (tr.error[i] !== exp.error[i]) begin
                            `uvm_error("RX_SB", $sformatf("Mismatch RX lane %0d error: exp=%b got=%b",
                                                          i, exp.error[i], tr.error[i]))
                        end
                    end
                end
            end
        endfunction

        virtual function void check_phase(uvm_phase phase);
            super.check_phase(phase);
            for (int i = 0; i < NUM_LANES; i++) begin
                if (tx_exp_q[i].size() != 0) begin
                    `uvm_error("SB_DRAIN", $sformatf("TX lane %0d: %0d expected beats still queued at end of test",
                                                     i, tx_exp_q[i].size()))
                end
                if (rx_exp_q[i].size() != 0) begin
                    `uvm_error("RX_SB_DRAIN", $sformatf("RX lane %0d: %0d expected beats still queued at end of test",
                                                         i, rx_exp_q[i].size()))
                end
            end
        endfunction
    endclass

    // --- Environment ---
    class ucie_rdi_pcie_env extends uvm_env;
        ucie_rdi_agent    rdi_agent;
        pcie_pipe_agent   pipe_agent;
        pcie_pipe_rx_agent pipe_rx_agent;
        ucie_rdi_monitor  rdi_rx_mon;
        pcie_pipe_monitor pipe_rx_mon;
        ucie_rdi_pcie_coverage cov;
        ucie_rdi_pcie_scoreboard sb;

        `uvm_component_utils(ucie_rdi_pcie_env)

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        virtual function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            rdi_agent  = ucie_rdi_agent::type_id::create("rdi_agent", this);
            pipe_agent = pcie_pipe_agent::type_id::create("pipe_agent", this);
            pipe_rx_agent = pcie_pipe_rx_agent::type_id::create("pipe_rx_agent", this);
            rdi_rx_mon = ucie_rdi_monitor::type_id::create("rdi_rx_mon", this);
            pipe_rx_mon = pcie_pipe_monitor::type_id::create("pipe_rx_mon", this);
            cov        = ucie_rdi_pcie_coverage::type_id::create("cov", this);
            sb         = ucie_rdi_pcie_scoreboard::type_id::create("sb", this);
        endfunction

        virtual function void connect_phase(uvm_phase phase);
            rdi_agent.mon.ap.connect(sb.imp_rdi);
            pipe_agent.mon.ap.connect(sb.imp_pipe);
            pipe_rx_mon.ap.connect(sb.imp_rx_pipe);
            rdi_rx_mon.ap.connect(sb.imp_rx_rdi);
            rdi_agent.mon.ap.connect(cov.imp_rdi);
            pipe_agent.mon.ap.connect(cov.imp_pipe);
            pipe_rx_mon.ap.connect(cov.imp_rx_pipe);
            rdi_rx_mon.ap.connect(cov.imp_rx_rdi);
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

        virtual function void build_phase(uvm_phase phase);
            uvm_config_db#(uvm_active_passive_enum)::set(this, "env.pipe_agent", "is_active", UVM_ACTIVE);
            uvm_config_db#(uvm_active_passive_enum)::set(this, "env.pipe_rx_agent", "is_active", UVM_ACTIVE);
            super.build_phase(phase);
        endfunction

        virtual task run_phase(uvm_phase phase);
            ucie_rdi_single_lane_seq single_seq;
            ucie_rdi_multi_lane_seq multi_seq;
            ucie_rdi_error_seq      err_seq;
            ucie_rdi_flow_ctrl_seq  fc_seq;
            pcie_pipe_backpressure_seq bp_seq;
            pcie_pipe_rx_seq        rx_seq;
            pcie_pipe_rx_single_lane_seq rx_single_seq;
            pcie_pipe_rx_error_seq  rx_err_seq;
            pcie_pipe_rx_burst_seq  rx_burst_seq;
            ucie_rdi_crc_seq        crc_seq;

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
            fork
                begin
                    bp_seq = pcie_pipe_backpressure_seq::type_id::create("bp_seq");
                    bp_seq.start(env.pipe_agent.sqr);
                end
                begin
                    #20ns;
                    fc_seq = ucie_rdi_flow_ctrl_seq::type_id::create("fc_seq");
                    fc_seq.start(env.rdi_agent.sqr);
                end
                begin
                    rx_seq = pcie_pipe_rx_seq::type_id::create("rx_seq");
                    rx_seq.start(env.pipe_rx_agent.sqr);
                end
            join

            `uvm_info("TEST", "Starting CRC Sequence", UVM_LOW)
            crc_seq = ucie_rdi_crc_seq::type_id::create("crc_seq");
            crc_seq.start(env.rdi_agent.sqr);

            #100ns;

            `uvm_info("TEST", "Starting RX Single-Lane Sequence", UVM_LOW)
            rx_single_seq = pcie_pipe_rx_single_lane_seq::type_id::create("rx_single_seq");
            rx_single_seq.start(env.pipe_rx_agent.sqr);

            `uvm_info("TEST", "Starting RX Error Sequence", UVM_LOW)
            rx_err_seq = pcie_pipe_rx_error_seq::type_id::create("rx_err_seq");
            rx_err_seq.start(env.pipe_rx_agent.sqr);

            `uvm_info("TEST", "Starting RX Burst Sequence", UVM_LOW)
            rx_burst_seq = pcie_pipe_rx_burst_seq::type_id::create("rx_burst_seq");
            rx_burst_seq.start(env.pipe_rx_agent.sqr);

            #1000ns;
            phase.drop_objection(this);
        endtask
    endclass



endpackage
