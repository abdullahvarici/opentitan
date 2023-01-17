# OTBN Formal Masking Verification Using Alma

This directory contains support files to formally verify the OTBN core using the
tool [Alma:
Execution-aware Masking Verification](https://github.com/IAIK/coco-alma).

## Prerequisites

Note that this flow is experimental. It has been developed using Yosys 0.9+4306
(git sha1 3931b3a03), sv2v v0.0.9-24-gf868f06 and Verilator 4.106 (2020-12-02
rev v4.106). Other tool versions might not be compatible.

1. Download the Alma tool from this specific repo and check out to the
   `coco-otbn` branch of the tool
   ```sh
   git clone git@github.com:abdullahvarici/coco-alma.git -b coco-otbn
   ```
   Enter the directory using
   ```sh
   cd coco-alma
   ```
   Set up a new virtual Python environment
   ```sh
   python3 -m venv dev
   source dev/bin/activate
   ```
   And install the Python requirements
   ```sh
   pip3 install -r requirements.txt
   ```
   Update `examples/otbn/config.json` to point correct locations for `asm`,
   `objdump` and `rv_objdump`.

1. Generate a Verilog netlist

   A netlist of the DUT can be generated using the Yosys synthesis flow from
   the OpenTitan repository. From the OpenTitan top level, run
   ```sh
   cd hw/ip/otbn/pre_syn
   ```
   Set up the synthesis flow as described in the corresponding README. Then run
   the synthesis
   ```sh
   ./syn_yosys.sh
   ```

## Formally verifying the masking of the OTBN core

After downloading the Alma tool, installing dependencies and synthesizing OTBN,
the masking can finally be formally verified.

1. Enter the directory where you have downloaded Alma and load the virtual
   Python environment
   ```sh
   source dev/bin/activate
   ```

1. Make sure to source the `build_consts.sh` script from the OpenTitan
   repository in order to set up some shell variables.
   ```sh
   source ../opentitan/util/build_consts.sh
   ```

1. Launch the Alma tool to parse, assemble, trace (simulate) and formally verify
   the netlist. For simplicity, a single script is provided to launch all the
   required steps with a single command. Simply run
   ```sh
   ${REPO_TOP}/hw/ip/otbn/pre_sca/alma/verify_otbn.sh
   ```
   This should produce output similar to the one below:
   ```sh
   TODO
   ```

## Individual steps in detail

Below we outline the individual steps performed by the `verify_otbn.sh` script.
This is useful if you, e.g., want to verify the masking of your own module.

For more details, please refer to the [Alma tutorial]
(https://github.com/IAIK/coco-alma/tree/hw-verif#usage).

1. Make sure to source the `build_consts.sh` script from the OpenTitan
   repository in order to set up some shell variables.
   ```sh
   source ../opentitan/util/build_consts.sh
   ```

1. The first step involves the parsing of the synthesized netlist.
   ```sh
   python3 parse.py --keep --top-module otbn_top_coco \
      --source ${REPO_TOP}/hw/ip/otbn/pre_sca/alma/rtl/ram_1p.v \
      ${REPO_TOP}/hw/ip/otbn/pre_sca/alma/rtl/otbn_top_coco.v \
      ${REPO_TOP}/hw/ip/otbn/pre_syn/syn_out/latest/generated/otbn_core.alma.v
   ```

1. Next, run the `assemble.py` script to generate memory initialization file for
   OTBN.
   ```sh
   cd examples/otbn
   python3 assemble.py --program programs/isw_and.S \
      --netlist ../../tmp/circuit.v
   cd ../../
   ```

1. Then, the Verilator testbench can be compiled and run. This step is required
   to identify control signals.
   ```sh
   python3 trace.py --testbench tmp/verilator_tb.c \
      --netlist tmp/circuit.v \
      --output-bin tmp/circuit.elf \
      --c-compiler gcc
   ```

1. Next, the automatically generated labeling file `tmp/labels.txt` needs to be
   adapted. This file tells Alma which inputs of the DUT correspond to the
   secret shares and which ones are used to provide randomness for
   (re-)masking. Use `update_labels.sh` script to update labels automatically.
   ```sh
   sh update_labels.sh otbn examples/otbn/programs/isw_and_labels.txt
   ```


1. Finally the verification of the masking implementation can be started.
   ```sh
   python3 verify.py --json tmp/circuit.json \
      --top-module otbn_top_coco \
      --label tmp/labels-updated.txt \
      --vcd tmp/circuit.vcd \
      --mode stable \
      --rst-name rst_sys_n \
      --rst-phase 0 \
      --rst-cycles 2 \
      --cycles 175
   ```

Run the following command to see the waveform:
   ```sh
   gtkwave tmp/circuit.vcd
   ```
