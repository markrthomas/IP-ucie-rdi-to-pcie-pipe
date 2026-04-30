# =============================================================================
# Example Synopsys Design Constraints (SDC-style) — UCIe RDI → PCIe PIPE bridge
# =============================================================================
# Placeholders only. Adapt clock names, ports, and delays to your netlist and STA.
# =============================================================================

# create_clock -name rdi_clk  -period 10.0 [get_ports rdi_clk]
# create_clock -name pipe_clk -period 6.667 [get_ports pipe_clk]

# set_clock_groups -asynchronous \
#   -group [get_clocks rdi_clk] \
#   -group [get_clocks pipe_clk]

# set_max_delay -datapath_only -from ... -to ... <ns>
