// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Implements functional coverage for csrng.

interface csrng_cov_if (
  input logic clk_i
);

  import uvm_pkg::*;
  import dv_utils_pkg::*;
  import csrng_pkg::*;
  import csrng_agent_pkg::*;
  import csrng_env_pkg::*;
  import prim_mubi_pkg::*;
  `include "dv_fcov_macros.svh"

  bit en_full_cov = 1'b1;
  bit en_intg_cov = 1'b1;

  // If en_full_cov is set, then en_intg_cov must also be set since it is a subset.
  bit en_intg_cov_loc;
  assign en_intg_cov_loc = en_full_cov | en_intg_cov;

  covergroup csrng_cfg_cg with function sample(mubi8_t   otp_en_cs_sw_app_read,
                                               mubi4_t   sw_app_enable,
                                               mubi4_t   read_int_state
                                              );
    option.name         = "csrng_cfg_cg";
    option.per_instance = 1;

    cp_sw_app_read:    coverpoint otp_en_cs_sw_app_read;
    cp_sw_app_enable:  coverpoint sw_app_enable;
    cp_read_int_state: coverpoint read_int_state;

    sw_app_read_sw_app_enable_cross: cross cp_sw_app_read, cp_sw_app_enable;
  endgroup : csrng_cfg_cg

  covergroup csrng_cmds_cg with function sample(bit[NUM_HW_APPS-1:0]   app,
                                                acmd_e                 acmd,
                                                bit[3:0]               clen,
                                                bit[3:0]               flags,
                                                bit[18:0]              glen
                                               );
    option.name         = "csrng_cmds_cg";
    option.per_instance = 1;

    cp_app: coverpoint app {
      bins        hw_app0 = { 0 };
      bins        hw_app1 = { 1 };
      bins        sw_app  = { 2 };
      ignore_bins other   = { 3 };
    }

    cp_acmd: coverpoint acmd {
      illegal_bins illegal = { INV, GENB, GENU };
    }

    cp_clen: coverpoint clen {
      bins zero         = { 0 };
      bins one          = { 1 };
      bins two          = { 2 };
      bins three        = { 3 };
      bins four         = { 4 };
      bins five         = { 5 };
      bins six          = { 6 };
      bins seven        = { 7 };
      bins eight        = { 8 };
      bins nine         = { 9 };
      bins ten          = { 10 };
      bins eleven       = { 11 };
      bins twelve       = { 12 };
      ignore_bins other = { [13:15] };
    }

    cp_flags: coverpoint flags {
      bins false         = { MuBi4False };
      bins true          = { MuBi4True };
    }

    cp_glen: coverpoint glen {
      bins one         = { 1 };
      bins multiple    = { [2:$] };
      ignore_bins zero = { 0 };
    }

    app_acmd_cross: cross cp_app, cp_acmd;

    acmd_clen_cross: cross cp_acmd, cp_clen {
      ignore_bins invalid = binsof(cp_acmd) intersect { UNI } &&
                            binsof(cp_clen) intersect { [1:$] };
    }

    acmd_flags_cross: cross cp_acmd, cp_flags;
    acmd_glen_cross:  cross cp_acmd, cp_glen;
    flags_clen_acmd_cross:  cross cp_acmd, cp_flags, cp_clen {
      // Use only Entropy Source seed
      bins ins_only_entropy_src_seed = binsof(cp_flags) intersect {MuBi4False} &&
                                       binsof(cp_clen) intersect {0} &&
                                       binsof(cp_acmd) intersect {INS};
      bins res_only_entropy_src_seed = binsof(cp_flags) intersect {MuBi4False} &&
                                       binsof(cp_clen) intersect {0} &&
                                       binsof(cp_acmd) intersect {RES};
      // Use Entropy Source Seed ^ Additional Data (clen)
      bins ins_xored_entropy_src_seed = binsof(cp_flags) intersect {MuBi4False} &&
                                        binsof(cp_clen) intersect {[1:$]} &&
                                        binsof(cp_acmd) intersect {INS};
      bins res_xored_entropy_src_seed = binsof(cp_flags) intersect {MuBi4False} &&
                                        binsof(cp_clen) intersect {[1:$]} &&
                                        binsof(cp_acmd) intersect {RES};
      // Use zero as seed
      bins ins_zero_seed = binsof(cp_flags) intersect {MuBi4True} &&
                           binsof(cp_clen) intersect {0} &&
                           binsof(cp_acmd) intersect {INS};
      bins res_zero_seed = binsof(cp_flags) intersect {MuBi4True} &&
                           binsof(cp_clen) intersect {0} &&
                           binsof(cp_acmd) intersect {RES};
      // Use Additional Data (clen) as seed
      bins ins_add_data_seed = binsof(cp_flags) intersect {MuBi4True} &&
                               binsof(cp_clen) intersect {[1:$]} &&
                               binsof(cp_acmd) intersect {INS};
      bins res_add_data_seed = binsof(cp_flags) intersect {MuBi4True} &&
                               binsof(cp_clen) intersect {[1:$]} &&
                               binsof(cp_acmd) intersect {RES};
      // Since other modes are not related with flag0, ignore them in this cross.
      ignore_bins ignore = binsof(cp_acmd) intersect {UPD, UNI, GEN};
    }
  endgroup : csrng_cmds_cg

  `DV_FCOV_INSTANTIATE_CG(csrng_cfg_cg, en_full_cov)
  `DV_FCOV_INSTANTIATE_CG(csrng_cmds_cg, en_full_cov)

  // Sample functions needed for xcelium
  function automatic void cg_cfg_sample(csrng_env_cfg cfg);
    csrng_cfg_cg_inst.sample(cfg.otp_en_cs_sw_app_read,
                              cfg.sw_app_enable,
                              cfg.read_int_state
                             );
  endfunction

  function automatic void cg_cmds_sample(bit[NUM_HW_APPS-1:0] hwapp, csrng_item cs_item);
    csrng_cmds_cg_inst.sample(hwapp,
                              cs_item.acmd,
                              cs_item.clen,
                              cs_item.flags,
                              cs_item.glen
                             );
  endfunction

endinterface : csrng_cov_if
