SBY ?= sby

.PHONY: all bmc cover clean

all: bmc cover

bmc:
	@command -v $(SBY) >/dev/null 2>&1 || { echo "[FORMAL] sby not found; install SymbiYosys to run BMC"; exit 0; }
	$(SBY) -f fifo_cdc.sby bmc

cover:
	@command -v $(SBY) >/dev/null 2>&1 || { echo "[FORMAL] sby not found; install SymbiYosys to run cover"; exit 0; }
	$(SBY) -f fifo_cdc.sby cover

clean:
	rm -rf fifo_cdc_bmc/ fifo_cdc_cover/
