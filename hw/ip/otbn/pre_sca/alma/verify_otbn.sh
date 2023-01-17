#!/bin/bash
# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

# Script to formally verify the masking of the OTBN using Alma.

echo "Verifying OTBN using Alma"

# Parse
python3 parse.py --keep --top-module otbn_top_coco \
  --source ${REPO_TOP}/hw/ip/otbn/pre_sca/alma/rtl/ram_1p.v \
  ${REPO_TOP}/hw/ip/otbn/pre_sca/alma/rtl/otbn_top_coco.v \
  ${REPO_TOP}/hw/ip/otbn/pre_syn/syn_out/latest/generated/otbn_core.alma.v

# Assemble the program
cd examples/otbn || exit
python3 assemble.py --program programs/isw_and.S \
  --netlist ../../tmp/circuit.v
cd ../../ || exit

# Trace
python3 trace.py --testbench tmp/verilator_tb.c \
  --netlist tmp/circuit.v \
  --output-bin tmp/circuit.elf \
  --c-compiler gcc

# Label
sh update_labels.sh otbn examples/otbn/programs/isw_and_labels.txt

# Verify
python3 verify.py --json tmp/circuit.json \
  --top-module otbn_top_coco \
  --label tmp/labels-updated.txt \
  --vcd tmp/circuit.vcd \
  --mode stable \
  --rst-name rst_sys_n \
  --rst-phase 0 \
  --rst-cycles 2 \
  --cycles 175
