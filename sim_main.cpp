
#include "Vtb_ucie_rdi_to_pcie_pipe_bridge.h"
#include "verilated.h"
#include "verilated_vcd_c.h"

uint64_t main_time = 0;

double sc_time_stamp() {
    return main_time;
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);

    Vtb_ucie_rdi_to_pcie_pipe_bridge* top = new Vtb_ucie_rdi_to_pcie_pipe_bridge;

    VerilatedVcdC* tfp = new VerilatedVcdC;
    Verilated::traceEverOn(true);
    top->trace(tfp, 99);
    tfp->open("trace.vcd");

    while (main_time < 100000 && !Verilated::gotFinish()) {
        top->eval();
        tfp->dump(main_time);
        main_time++;
    }

    tfp->close();
    delete tfp;
    delete top;
    return 0;
}

