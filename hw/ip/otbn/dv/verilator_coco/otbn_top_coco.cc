// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

#include "Votbn_top_sim__Syms.h"
#include "otbn_memutil.h"
#include "verilated_toplevel.h"
#include "verilator_memutil.h"
#include "verilator_sim_ctrl.h"

static otbn_top_coco *verilator_top;
static OtbnMemUtil otbn_memutil("TOP.otbn_top_coco");

int main(int argc, char **argv) {
  VerilatorMemUtil memutil(&otbn_memutil);

  otbn_top_coco top;
  // Make the otbn_top_coco object visible to OtbnTopApplyLoopWarp.
  // This will leave a dangling pointer when we exit main, but that
  // doesn't really matter because we don't have anything that uses it
  // running in atexit hooks.
  verilator_top = &top;

  VerilatorSimCtrl &simctrl = VerilatorSimCtrl::GetInstance();
  simctrl.SetTop(&top, &top.clk_sys, &top.rst_sys_n,
                 VerilatorSimCtrlFlags::ResetPolarityNegative);
  simctrl.RegisterExtension(&memutil);

  auto pr = simctrl.Exec(argc, argv);
  int ret_code = pr.first;
  bool ran_simulation = pr.second;

  if (ret_code != 0 || !ran_simulation) {
    return ret_code;
  }

  svSetScope(svGetScopeFromName("TOP.otbn_top_coco"));

  return 0;
}