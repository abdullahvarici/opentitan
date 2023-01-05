// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

module otbn_top (
  input clk_sys,
  input rst_sys_n
);
  // Size of the instruction memory, in bytes
  // parameter int ImemSizeByte = otbn_reg_pkg::OTBN_IMEM_SIZE;
  localparam ImemSizeByte = 32'h1000;
  // Size of the data memory, in bytes
  //parameter int DmemSizeByte = 2 * otbn_reg_pkg::OTBN_DMEM_SIZE;
  localparam DmemSizeByte = 32'h1000;
  // Data path width for BN (wide) instructions, in bits.
  localparam WLEN = 256;
  // Instruction data width
  localparam ImemDataWidth = 39;
  // Sideload key data width
  localparam SideloadKeyWidth = 384;
  // "Extended" WLEN: the size of the datapath with added integrity bits
  localparam ExtWLEN = WLEN * ImemDataWidth / 32;

  // Math function: Number of bits needed to address |value| items.
  // vbits function in prim_util_pkg.sv
  function automatic _clog2;
    input value;
    begin : fclog2
      integer result;
      value = value - 1;
      if (value == 1) begin 
        _clog2 = 1;
      end else begin
        for (result = 0; value > 0; result = result + 1) begin
          value = value >> 1;
        end
        _clog2 = result;
      end 
    end : fclog2
  endfunction

  // Instruction memory adress width
  localparam ImemAddrWidth = _clog2(ImemSizeByte);
  // Data memory adress width
  localparam DmemAddrWidth = _clog2(DmemSizeByte);

  reg otbn_start;
  // Intialise otbn_start_done to 1 so that we only signal otbn_start after we have seen a reset. If
  // you don't do this, we start OTBN before the reset, which can generate confusing trace messages.
  reg otbn_start_done = 1'b1;
  wire secure_wipe_running;

  // Instruction memory (IMEM) signals
  wire                     imem_req;
  wire [ImemAddrWidth-1:0] imem_addr;
  wire [ImemDataWidth-1:0] imem_rdata;
  wire                     imem_rvalid;

  // Data memory (DMEM) signals
  wire                     dmem_req;
  wire                     dmem_write;
  wire [DmemAddrWidth-1:0] dmem_addr;
  wire [ExtWLEN-1:0]       dmem_wdata;
  wire [ExtWLEN-1:0]       dmem_wmask;
  wire [ExtWLEN-1:0]       dmem_rdata;
  wire                     dmem_rvalid;
  wire                     dmem_rerror;

  // Entropy Distribution Network (EDN)
  wire                     edn_rnd_req, edn_urnd_req;
  wire                     edn_rnd_ack, edn_urnd_ack;
  localparam [WLEN-1:0] FixedEdnVal = {{4{64'hAAAA_AAAA_9999_9999}}};
  assign edn_rnd_ack = edn_rnd_req;
  assign edn_urnd_ack = edn_urnd_req;

  // Sideload Key
  wire [2*SideloadKeyWidth-1:0] sideload_key_shares;
  assign sideload_key_shares[SideloadKeyWidth-1:0] = {12{32'hDEADBEEF}};
  assign sideload_key_shares[2*SideloadKeyWidth-1:SideloadKeyWidth] = {12{32'hBAADF00D}};

  localparam MuBi4False = 4'h9;

  otbn_core u_otbn_core (
    .clk_i                       ( clk_sys                    ),
    .rst_ni                      ( rst_sys_n                  ),

    .start_i                     ( otbn_start                 ),
    .done_o                      (                            ),
    .locking_o                   (                            ),
    .secure_wipe_running_o       ( secure_wipe_running        ),

    .err_bits_o                  (                            ),
    .recoverable_err_o           (                            ),

    .imem_req_o                  ( imem_req                   ),
    .imem_addr_o                 ( imem_addr                  ),
    .imem_rdata_i                ( imem_rdata                 ),
    .imem_rvalid_i               ( imem_rvalid                ),

    .dmem_req_o                  ( dmem_req                   ),
    .dmem_write_o                ( dmem_write                 ),
    .dmem_addr_o                 ( dmem_addr                  ),
    .dmem_wdata_o                ( dmem_wdata                 ),
    .dmem_wmask_o                ( dmem_wmask                 ),
    .dmem_rmask_o                ( ),
    .dmem_rdata_i                ( dmem_rdata                 ),
    .dmem_rvalid_i               ( dmem_rvalid                ),
    .dmem_rerror_i               ( dmem_rerror                ),

    .edn_rnd_req_o               ( edn_rnd_req                ),
    .edn_rnd_ack_i               ( edn_rnd_ack                ),
    .edn_rnd_data_i              ( FixedEdnVal                ),
    .edn_rnd_fips_i              ( 1'b1                       ),
    .edn_rnd_err_i               ( 1'b0                       ),

    .edn_urnd_req_o              ( edn_urnd_req               ),
    .edn_urnd_ack_i              ( edn_urnd_ack               ),
    .edn_urnd_data_i             ( FixedEdnVal                ),

    .insn_cnt_o                  (                            ),
    .insn_cnt_clear_i            ( 1'b0                       ),

    .mems_sec_wipe_o             (                            ),
    .dmem_sec_wipe_urnd_key_o    (                            ),
    .imem_sec_wipe_urnd_key_o    (                            ),
    .req_sec_wipe_urnd_keys_i    ( 1'b0                       ),

    .escalate_en_i               ( MuBi4False                 ),
    .rma_req_i                   ( MuBi4False                 ),
    .rma_ack_o                   (                            ),

    .software_errs_fatal_i       ( 1'b0                       ),

    .sideload_key_shares_i       ( sideload_key_shares        ),
    .sideload_key_shares_valid_i ( 2'b11                      )
  );

  // Track when OTBN is done with its initial secure wipe of the internal state.  We use this to
  // wait for the OTBN core to complete the initial secure wipe before we send it the start signal.
  // Also keep a delayed copy of the done signal.  This is necessary to align with the status of
  // OTBN and the model, which lags one cycle behind the completion of the OTBN core.
  reg init_sec_wipe_done_q; 
  always @(posedge clk_sys, negedge rst_sys_n) begin
    if (!rst_sys_n) begin
      init_sec_wipe_done_q  <= 1'b0;
    end else begin
      if (!secure_wipe_running) init_sec_wipe_done_q <= 1'b1;
    end
  end

  // Pulse otbn_start for 1 cycle after the initial secure wipe is done.
  // Flop `done_o` from otbn_core to match up with model done signal.
  always @(posedge clk_sys or negedge rst_sys_n) begin
    if (!rst_sys_n) begin
      otbn_start       <= 1'b0;
      otbn_start_done  <= 1'b0;
    end else begin
      if (!otbn_start_done && init_sec_wipe_done_q) begin
        otbn_start      <= 1'b1;
        otbn_start_done <= 1'b1;
      end else if (otbn_start) begin
        otbn_start <= 1'b0;
      end
    end
  end

  localparam DmemSizeWords = DmemSizeByte / (WLEN / 8);
  localparam DmemIndexWidth = _clog2(DmemSizeWords);

  wire [DmemIndexWidth-1:0] dmem_index;
  wire [DmemAddrWidth-DmemIndexWidth-1:0] unused_dmem_addr;

  assign dmem_index = dmem_addr[DmemAddrWidth-1:DmemAddrWidth-DmemIndexWidth];
  assign unused_dmem_addr = dmem_addr[DmemAddrWidth-DmemIndexWidth-1:0];

  ram_1p #(
    .DataWidth(ExtWLEN),
    .AddrWidth(DmemIndexWidth),
    .Depth(DmemSizeWords)
  ) 
  u_dmem(
    .clk_i(clk_sys),
    .rst_ni(rst_sys_n),
    .req_i(dmem_req),
    .we_i(dmem_write),
    .addr_i(dmem_index),
    .wdata_i(dmem_wdata),
    .wmask_i(dmem_wmask),
    .rvalid_o(dmem_rvalid),
    .rdata_o(dmem_rdata)
  );

  // No integrity errors in Verilator testbench
  assign dmem_rerror = 1'b0;

  localparam ImemSizeWords = ImemSizeByte / 4;
  localparam ImemIndexWidth = _clog2(ImemSizeWords);

  wire [ImemIndexWidth-1:0] imem_index;
  wire [1:0] unused_imem_addr;

  assign imem_index = imem_addr[ImemAddrWidth-1:2];
  assign unused_imem_addr = imem_addr[1:0];

  ram_1p #(
    .DataWidth(ImemDataWidth),
    .AddrWidth(ImemIndexWidth),
    .Depth(ImemSizeWords)
  ) 
  u_imem(
    .clk_i(clk_sys),
    .rst_ni(rst_sys_n),
    .req_i(imem_req),
    .we_i(1'b0),
    .addr_i(imem_index),
    .wdata_i({ImemDataWidth{1'b0}}),
    .wmask_i({ImemDataWidth{1'b0}}),
    .rvalid_o(imem_rvalid),
    .rdata_o(imem_rdata)
  );

endmodule