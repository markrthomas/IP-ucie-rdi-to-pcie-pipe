# =============================================================================
# Example Xilinx Design Constraints (XDC) — UCIe RDI → PCIe PIPE bridge
# =============================================================================
# This file is a STARTING POINT for integration. Values and object names are
# placeholders. Sign off timing with your own clocks, hierarchy, and STA flow.
# =============================================================================

# --- Clocks ---
# Create or reference project clocks that drive rdi_clk and pipe_clk on the
# bridge instance, then relate asynchronous domains. Example:
#
# create_clock -period 10.000 -name rdi_clk  [get_ports rdi_clk]
# create_clock -period 6.667  -name pipe_clk [get_ports pipe_clk]

# Treat RDI and PIPE as asynchronous (typical). Uncomment after clocks exist:
#
# set_clock_groups -asynchronous \
#   -group [get_clocks -of_objects [get_ports rdi_clk]] \
#   -group [get_clocks -of_objects [get_ports pipe_clk]]

# --- CDC datapath ---
# Gray-coded pointers cross between domains; prefer scoped max_delay -datapath_only
# between synchronizer flops rather than blanket false paths on pointer buses.
# Example pattern (replace cell/pin names with your synthesized hierarchy):
#
# set_max_delay -datapath_only -from [get_cells ...rdi_wr_ptr_gray_reg*] \
#   -to [get_cells ...rdi_wr_ptr_gray_sync_r1_reg*] 5.0

# --- Reset ---
# rst_n is modeled asynchronous active-low in RTL. Apply platform-specific
# recovery/removal or false-path guidance per your vendor methodology.
