#!/usr/bin/env bash
# Mutation test: breaks the vendored core on purpose (in a temporary copy) and checks that the self-test notices.
# A test suite that still says PASS on a broken core is worthless; this proves the checks have teeth.
# Usage: bash sim/mutation_test.sh      Expected output: every mutant line says CAUGHT.
set -u
cd "$(dirname "$0")/.."
mkdir -p sim/build
bash sim/fw/build.sh rv32i_zicsr 4096 selftest "" > sim/build/fw_selftest.log 2>&1
RESULT=0
# Runs one mutant: name, sed expression applied to serv_alu.v
mutant() {
  local name=$1 expr=$2
  rm -rf sim/build/mut_$name; mkdir -p sim/build/mut_$name
  cp rtl/vendor/serv/rtl/*.v sim/build/mut_$name/
  sed -i "$expr" sim/build/mut_$name/serv_alu.v
  if cmp -s rtl/vendor/serv/rtl/serv_alu.v sim/build/mut_$name/serv_alu.v; then echo "MUTANT_NOT_APPLIED $name"; RESULT=1; return; fi
  iverilog -g2012 -DCCGM -P tb_soc.FIRMWARE=\"sim/fw/out/selftest.hex\" -P tb_soc.ENDFILE=\"sim/fw/out/selftest.end\" -P tb_soc.NAME=\"mutant_$name\" -P tb_soc.LIMIT_US=200000 \
    -o sim/build/mut_$name.vvp sim/tb_soc.v rtl/servxzen_soc.v rtl/servxzen_uart_tx.v rtl/vendor/serv/servile/*.v sim/build/mut_$name/*.v rtl/vendor/serv/servant/*.v > sim/build/mut_$name.cc.log 2>&1
  local line; line=$(vvp sim/build/mut_$name.vvp 2>&1 | grep -a "^TEST_" | tail -1)
  case "$line" in TEST_FAIL*) echo "CAUGHT   $name: $line";; *) echo "MISSED   $name: $line"; RESULT=1;; esac
}
# Mutant 1: the signed-compare sign extension of rs1 is dropped, so slt/blt behave unsigned
mutant slt_unsigned 's/wire rs1_sx  = i_rs1\[B\] & i_cmp_sig;/wire rs1_sx  = 1'"'"'b0;/'
# Mutant 2: equality compare inverted, so beq and bne swap
mutant eq_inverted 's/wire result_eq = \(.*\);/wire result_eq = ~(\1);/'
[ $RESULT -eq 0 ] && echo "MUTATION TEST OK" || echo "MUTATION TEST PROBLEM"
exit $RESULT
