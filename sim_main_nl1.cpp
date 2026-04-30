
#include "Vtb_ucie_rdi_to_pcie_pipe_nl1.h"
#include "verilated.h"
#include "verilated_vcd_c.h"
#if VM_COVERAGE
#include "verilated_cov.h"
#endif

static vluint64_t g_sim_time_ps = 0;

double sc_time_stamp() {
    return static_cast<double>(g_sim_time_ps);
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);

    Vtb_ucie_rdi_to_pcie_pipe_nl1* top = new Vtb_ucie_rdi_to_pcie_pipe_nl1;

    VerilatedVcdC* tfp = new VerilatedVcdC;
    Verilated::traceEverOn(true);
    top->trace(tfp, 99);
    tfp->open("dump.vcd");

    const vluint64_t step_ps = 500;
    const vluint64_t t_reset_release_ps = 100000;
    const vluint64_t t_max_ps = 50000000;

    top->rst_n = 0;
    top->rdi_clk = 0;
    top->pipe_clk = 0;

    for (vluint64_t t_ps = 0; t_ps < t_max_ps && !Verilated::gotFinish(); t_ps += step_ps) {
        g_sim_time_ps = t_ps;
        top->rst_n = (t_ps >= t_reset_release_ps) ? 1 : 0;
        // rdi_clk: 10 ns period => toggle every 5000 ps; pipe_clk ~6.667 ns => ~3333 ps half-period
        top->rdi_clk = ((t_ps / 5000) % 2) != 0;
        top->pipe_clk = ((t_ps / 3333) % 2) != 0;

        top->eval();
        tfp->dump(static_cast<vluint64_t>(t_ps));
    }

#if VM_COVERAGE
    VerilatedCov::write();
#endif

    tfp->close();
    delete tfp;
    delete top;
    return 0;
}
