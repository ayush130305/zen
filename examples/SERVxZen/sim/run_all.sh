#!/usr/bin/env bash
# Runs the SERVxZen simulation matrix with Icarus Verilog and prints one TEST_PASS/TEST_FAIL line per run.
# Usage: bash sim/run_all.sh [quick]     "quick" runs only the default Zen 4 configuration.
# Needs: iverilog (>= 11), riscv64-unknown-elf-gcc, python3. Run from anywhere; it changes into the project root.
set -u
cd "$(dirname "$0")/.."
mkdir -p sim/build
FAIL=0
# RTL of the SoC and the vendored SERV files it uses
SRC="rtl/servxzen_soc.v rtl/servxzen_uart_tx.v rtl/vendor/serv/servile/*.v rtl/vendor/serv/rtl/*.v rtl/vendor/serv/servant/*.v"
# Firmware output folder and build log folder
FW=sim/fw/out
B=sim/build

# Builds one firmware image: name, march, memsize, extra compiler flags
fw() { bash sim/fw/build.sh "$2" "$3" "$1" "$4" > $B/fw_$1.log 2>&1 || { echo "BUILD_FAIL $1 (see $B/fw_$1.log)"; FAIL=1; }; }

# Runs one simulation: label, firmware name, width, compressed, memsize, time limit in microseconds
sim() {
  local label=$1 img=$2 w=$3 c=$4 mem=$5 lim=$6
  iverilog -g2012 -DCCGM -P tb_soc.FIRMWARE=\"$FW/$img.hex\" -P tb_soc.ENDFILE=\"$FW/$img.end\" -P tb_soc.NAME=\"$label\" \
    -P tb_soc.WIDTH=$w -P tb_soc.COMPRESSED=$c -P tb_soc.MEMSIZE=$mem -P tb_soc.LIMIT_US=$lim \
    -o $B/$label.vvp sim/tb_soc.v $SRC > $B/$label.cc.log 2>&1 || { echo "COMPILE_FAIL $label (see $B/$label.cc.log)"; FAIL=1; return; }
  vvp $B/$label.vvp > $B/$label.log 2>&1
  local line; line=$(grep -a "^TEST_" $B/$label.log | tail -1)
  echo "${line:-TEST_FAIL $label (no result line, see $B/$label.log)}"
  case "$line" in TEST_PASS*) ;; *) FAIL=1;; esac
}

# Board top: pins, reset synchroniser and LEDs with the default Zen 4 image
board() {
  iverilog -g2012 -DCCGM -P tb_zen_serv_top.FIRMWARE=\"$FW/selftest.hex\" -o $B/zen_top.vvp sim/tb_zen_serv_top.v rtl/zen_serv_top.v $SRC > $B/zen_top.cc.log 2>&1 \
    || { echo "COMPILE_FAIL zen_top (see $B/zen_top.cc.log)"; FAIL=1; return; }
  local line; line=$(vvp $B/zen_top.vvp 2>&1 | grep -a "^TEST_" | tail -1)
  echo "${line:-TEST_FAIL zen_top (no result line)}"
  case "$line" in TEST_PASS*) ;; *) FAIL=1;; esac
}

echo "== firmware images"
fw selftest   rv32i_zicsr  4096  ""
fw trapperf   rv32i_zicsr  4096  "-DWITH_TRAP -DWITH_PERF"
if [ "${1:-}" != "quick" ]; then
  fw full       rv32i_zicsr  16384 "-DWITH_CORE -DWITH_TRAP -DWITH_SOFT -DWITH_PERF"
  fw selftest_c rv32ic_zicsr 4096  ""
  fw full_c     rv32ic_zicsr 16384 "-DWITH_CORE -DWITH_TRAP -DWITH_SOFT -DWITH_PERF"
fi
for i in selftest trapperf full selftest_c full_c; do [ -f $FW/$i.hex ] && echo "  $(grep -a "^built" $B/fw_$i.log)"; done

echo "== simulation"
sim zen4_core   selftest  1 0 4096  200000
sim zen4_trap   trapperf  1 0 4096  400000
board
if [ "${1:-}" != "quick" ]; then
  sim full_w1     full       1 0 16384 400000
  sim qerv_core   selftest   4 0 4096  200000
  sim qerv_trap   trapperf   4 0 4096  400000
  sim qerv_full   full       4 0 16384 400000
  sim rvc_core    selftest_c 1 1 4096  200000
  sim rvc_full    full_c     1 1 16384 400000
  sim qerv_rvc    selftest_c 4 1 4096  200000
fi
[ $FAIL -eq 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit $FAIL
