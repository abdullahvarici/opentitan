// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

module otbn_top_sim (
  input IO_CLK,
  input IO_RST_N
);
  import otbn_pkg::*;
  // import edn_pkg::*;
  // import keymgr_pkg::otbn_key_req_t;

  // Size of the instruction memory, in bytes
  parameter int ImemSizeByte = otbn_reg_pkg::OTBN_IMEM_SIZE;
  // Size of the data memory, in bytes
  parameter int DmemSizeByte = 2 * otbn_reg_pkg::OTBN_DMEM_SIZE;

  localparam int ImemAddrWidth = prim_util_pkg::vbits(ImemSizeByte);
  localparam int DmemAddrWidth = prim_util_pkg::vbits(DmemSizeByte);

  // Fixed key and nonce for scrambling in verilator environment
  localparam logic [127:0] TestScrambleKey   = 128'h48ecf6c738f0f108a5b08620695ffd4d;
  localparam logic [63:0]  TestScrambleNonce = 64'hf88c2578fa4cd123;

  logic      otbn_done; //, otbn_done_r;//, otbn_done_rr;
  logic      otbn_start;

  // Intialise otbn_start_done to 1 so that we only signal otbn_start after we have seen a reset. If
  // you don't do this, we start OTBN before the reset, which can generate confusing trace messages.
  logic      otbn_start_done = 1'b1;

  // Instruction memory (IMEM) signals
  logic                     imem_req;
  logic [ImemAddrWidth-1:0] imem_addr;
  logic [38:0]              imem_rdata;
  logic                     imem_rvalid;

  // Data memory (DMEM) signals
  logic                     dmem_req;
  logic                     dmem_write;
  logic [DmemAddrWidth-1:0] dmem_addr;
  logic [ExtWLEN-1:0]       dmem_wdata;
  logic [ExtWLEN-1:0]       dmem_wmask;
  logic [ExtWLEN-1:0]       dmem_rdata;
  logic                     dmem_rvalid;
  logic                     dmem_rerror;

  // Entropy Distribution Network (EDN)
  logic                     edn_rnd_req, edn_urnd_req;
  logic                     edn_rnd_ack, edn_urnd_ack;
  localparam logic [WLEN-1:0] FixedEdnVal = {{4{64'hAAAA_AAAA_9999_9999}}};
  assign edn_rnd_ack = edn_rnd_req;
  assign edn_urnd_ack = edn_urnd_req;

  logic [1:0][SideloadKeyWidth-1:0] sideload_key_shares;
  assign sideload_key_shares[0] = {12{32'hDEADBEEF}};
  assign sideload_key_shares[1] = {12{32'hBAADF00D}};

  logic secure_wipe_running;

  otbn_core #(
    .ImemSizeByte ( ImemSizeByte ),
    .DmemSizeByte ( DmemSizeByte )
  ) u_otbn_core (
    .clk_i                       ( IO_CLK                     ),
    .rst_ni                      ( IO_RST_N                   ),

    .start_i                     ( otbn_start                 ),
    .done_o                      ( otbn_done                  ),
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

    .escalate_en_i               ( prim_mubi_pkg::MuBi4False  ),

    .software_errs_fatal_i       ( 1'b0                       ),

    .sideload_key_shares_i       ( sideload_key_shares        ),
    .sideload_key_shares_valid_i ( 2'b11                      )
  );

  // Track when OTBN is done with its initial secure wipe of the internal state.  We use this to
  // wait for the OTBN core to complete the initial secure wipe before we send it the start signal.
  // Also keep a delayed copy of the done signal.  This is necessary to align with the status of
  // OTBN and the model, which lags one cycle behind the completion of the OTBN core.
  logic init_sec_wipe_done_q; 
  always_ff @(posedge IO_CLK, negedge IO_RST_N) begin
    if (!IO_RST_N) begin
      init_sec_wipe_done_q  <= 1'b0;
    end else begin
      if (!secure_wipe_running) init_sec_wipe_done_q <= 1'b1;
    end
  end

  // Pulse otbn_start for 1 cycle after the initial secure wipe is done.
  // Flop `done_o` from otbn_core to match up with model done signal.
  always @(posedge IO_CLK or negedge IO_RST_N) begin
    if (!IO_RST_N) begin
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

  localparam int DmemSizeWords = DmemSizeByte / (WLEN / 8);
  localparam int DmemIndexWidth = prim_util_pkg::vbits(DmemSizeWords);

  logic [DmemIndexWidth-1:0] dmem_index;
  logic [DmemAddrWidth-DmemIndexWidth-1:0] unused_dmem_addr;

  assign dmem_index = dmem_addr[DmemAddrWidth-1:DmemAddrWidth-DmemIndexWidth];
  assign unused_dmem_addr = dmem_addr[DmemAddrWidth-DmemIndexWidth-1:0];

  prim_ram_1p_scr #(
    .Width              ( ExtWLEN       ),
    .Depth              ( DmemSizeWords ),
    .DataBitsPerMask    ( 39            ),
    .EnableParity       ( 0             ),
    .ReplicateKeyStream ( 1             )
  ) u_dmem (
    .clk_i        ( IO_CLK            ),
    .rst_ni       ( IO_RST_N          ),

    .key_valid_i  ( 1'b1              ),
    .key_i        ( TestScrambleKey   ),
    .nonce_i      ( TestScrambleNonce ),

    .req_i        ( dmem_req          ),
    .gnt_o        (                   ),
    .write_i      ( dmem_write        ),
    .addr_i       ( dmem_index        ),
    .wdata_i      ( dmem_wdata        ),
    .wmask_i      ( dmem_wmask        ),
    .intg_error_i ( 1'b0              ),

    .rdata_o      ( dmem_rdata        ),
    .rvalid_o     ( dmem_rvalid       ),
    .raddr_o      (                   ),
    .rerror_o     (                   ),
    .cfg_i        ( '0                )
  );

  // No integrity errors in Verilator testbench
  assign dmem_rerror = 1'b0;

  localparam int ImemSizeWords = ImemSizeByte / 4;
  localparam int ImemIndexWidth = prim_util_pkg::vbits(ImemSizeWords);

  logic [ImemIndexWidth-1:0] imem_index;
  logic [1:0] unused_imem_addr;

  assign imem_index = imem_addr[ImemAddrWidth-1:2];
  assign unused_imem_addr = imem_addr[1:0];

  prim_ram_1p_scr #(
    .Width           ( 39            ),
    .Depth           ( ImemSizeWords ),
    .DataBitsPerMask ( 39            ),
    .EnableParity    ( 0             )
  ) u_imem (
    .clk_i        ( IO_CLK                  ),
    .rst_ni       ( IO_RST_N                ),

    .key_valid_i  ( 1'b1                    ),
    .key_i        ( TestScrambleKey         ),
    .nonce_i      ( TestScrambleNonce       ),

    .req_i        ( imem_req                ),
    .gnt_o        (                         ),
    .write_i      ( 1'b0                    ),
    .addr_i       ( imem_index              ),
    .wdata_i      ( '0                      ),
    .wmask_i      ( '0                      ),
    .intg_error_i ( 1'b0                    ),

    .rdata_o      ( imem_rdata              ),
    .rvalid_o     ( imem_rvalid             ),
    .raddr_o      (                         ),
    .rerror_o     (                         ),
    .cfg_i        ( '0                      )
  );

  // When OTBN is done let a few more cycles run then finish simulation
  logic [1:0] finish_counter;

  always @(posedge IO_CLK or negedge IO_RST_N) begin
    if (!IO_RST_N) begin
      finish_counter <= 2'd0;
    end else begin
      if (otbn_done) begin
        finish_counter <= 2'd1;
      end

      if (finish_counter != 0) begin
        finish_counter <= finish_counter + 2'd1;
      end

      if (finish_counter == 2'd3) begin
        $finish;
      end
    end
  end

endmodule
