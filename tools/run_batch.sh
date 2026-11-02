#!/usr/bin/env bash
# sequential differential batch: run_batch.sh FIRST_SEED COUNT INSTR [dec]
export PATH=/Users/lakomoor/MiSTang-FPGA/toolchain/oss-cad-suite/bin:$PATH
cd "$(dirname "$0")/.."
ok=0; bad=0
for sd in $(seq $1 $(($1+$2-1))); do
  out=$(timeout 100 python3 tools/difftest.py $sd $3 $4 2>&1 | tail -4)
  case "$out" in *OK*) ok=$((ok+1));; *) bad=$((bad+1)); echo "$out";; esac
done
echo "RESULT first=$1 count=$2 instr=$3 $4: ok=$ok bad=$bad"
