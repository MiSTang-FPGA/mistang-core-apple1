#!/usr/bin/env bash
# system test: assemble the monitor, run keys through RTL and the Python model, compare the screens
set -e; cd "$(dirname "$0")"; mkdir -p build
export PATH=/Users/lakomoor/MiSTang-FPGA/toolchain/oss-cad-suite/bin:$PATH
python3 tools/asm6502.py rom/monitor.s rom/monitor.hex 0xF000 >/dev/null
N=$(wc -c < sim/keys.bin | tr -d ' ')
iverilog -g2012 -DNKEYS=$N -DGAP=900 -DGAPCR=60000 -o build/tbs.vvp sim/tb_sys.sv rtl/apple1_sys.sv rtl/cpu6502.sv rtl/term40x24.sv rtl/uart_rx.sv 2>&1 | grep -v sorry || true
timeout 600 vvp build/tbs.vvp > /dev/null
python3 tools/sysmodel.py rom/monitor.hex sim/keys.bin > build/model_screen.txt
diff build/model_screen.txt build/rtl_screen.txt && echo "PASS: RTL screen == reference model"
python3 tools/render_text.py build/rtl_screen.txt rom/font8x8.hex docs/img/sim-apple1.png && rm -f docs/img/sim-apple1.txt
