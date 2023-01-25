// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// This module is coded to be similar to the ram_1p_secure.v in COCO-IBEX project
// Secured version of ram_1p.v

module ram_1p_secure #(
  parameter DataWidth = 32,
  parameter AddrWidth = 2,
  parameter AddrWidthInBlock = 1
) (
  input                  clk_i,
  input                  rst_ni,
  input                  req_i,
  input                  we_i,
  input  [AddrWidth-1:0] addr_i,
  input  [DataWidth-1:0] wdata_i,
  input  [DataWidth-1:0] wmask_i,
  output                 rvalid_o,
  output [DataWidth-1:0] rdata_o
);

  // Address bits for in-block addressing.
  // 2^a = number of registers in block.
  parameter a = AddrWidthInBlock;
  // Address bits for inter-block addressing.
  // 2^b = number of block.
  parameter b = AddrWidth - AddrWidthInBlock;
  parameter num_regs_in_block = 2 ** a;
  parameter num_blocks = 2 ** b;

  // Compute address index
  wire [a+b-1:0] addr_idx;
  assign addr_idx = addr_i;

  // Create mem:
  // 32 Bit wide registers
  // num_regs_in_block registers per block in num_blocks
  reg [DataWidth-1:0] mem[num_blocks-1:0][num_regs_in_block-1:0];

  //OH-vector for register accesses
  reg [num_regs_in_block-1:0] OH_in_reg;
  reg [num_regs_in_block-1:0] OH_in_signal;

  //Address of register in block
  wire [a-1:0] in_block_addr;
  assign in_block_addr = addr_idx[a-1:0];

  //Address of block
  wire [b-1:0] inter_block_addr;
  assign inter_block_addr = addr_idx[b+a-1:a];
  reg [b-1:0] inter_block_addr_reg;
  reg [b-1:0] inter_block_addr_stage1;

  integer oh_reg_id;
  always @(*) begin
    for (oh_reg_id = 0; oh_reg_id < num_regs_in_block; oh_reg_id = oh_reg_id + 1) begin
      OH_in_signal[oh_reg_id] = (in_block_addr ==  (oh_reg_id)) ? 1'b1 : 1'b0;
    end
  end

  reg gnt;

  reg we;
  reg [DataWidth-1:0] wdata;
  reg [DataWidth-1:0] wmask;

  always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      OH_in_reg <= 0;
      gnt <= 0;
      we <= 0;
      wdata <= 0;
      wmask <= 0;
    end else begin
      if (req_i) begin
        OH_in_reg <= OH_in_signal;
        gnt <= 1;
        inter_block_addr_stage1 <= inter_block_addr;
        we <= we_i;
        wdata <= wdata_i;
        wmask <= wmask_i;
      end else begin
        OH_in_reg <= 0;
        gnt <= 0;
        inter_block_addr_stage1 <= 0;
        we <= 0;
        wdata <= 0;
        wmask <= 0;
      end
      if (gnt) begin
        inter_block_addr_reg <= inter_block_addr_stage1;
      end
    end
  end

  reg [DataWidth-1:0] rdata_OR[num_blocks-1:0];
  reg rvalid;

  integer read_mem_id;
  integer read_mem_block_id;
  reg [DataWidth-1:0] rdata_OR_tmp;
  always @(posedge clk_i) begin
    for (
        read_mem_block_id = 0;
        read_mem_block_id < num_blocks;
        read_mem_block_id = read_mem_block_id + 1
    ) begin
      rdata_OR_tmp = 0;
      for (read_mem_id = 0; read_mem_id < num_regs_in_block; read_mem_id = read_mem_id + 1) begin
        rdata_OR_tmp = rdata_OR_tmp | (mem[read_mem_block_id][read_mem_id] &
                                       {DataWidth{OH_in_reg[read_mem_id]}} & {DataWidth{~we}});
      end
      rdata_OR[read_mem_block_id] = rdata_OR_tmp;
    end
  end

  always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      rvalid <= 0;
    end else begin
      rvalid <= |OH_in_reg;
    end
  end

  assign rvalid_o = rvalid;

  genvar gen_level_cnt;
  genvar gen_data_cnt;
  generate
    for (gen_level_cnt = 0; gen_level_cnt <= b; gen_level_cnt = gen_level_cnt + 1) begin : rdata
      wire [DataWidth-1:0] leveldata[2**(b-gen_level_cnt)-1:0];
      if (gen_level_cnt != 0) begin
        for (
          gen_data_cnt = 0;
          gen_data_cnt < 2 ** (b - gen_level_cnt);
          gen_data_cnt = gen_data_cnt + 1
        ) begin
          assign leveldata[gen_data_cnt] = inter_block_addr_reg[gen_level_cnt-1] ? 
                                           rdata[gen_level_cnt-1].leveldata[2 * gen_data_cnt + 1] :  
                                           rdata[gen_level_cnt-1].leveldata[2 * gen_data_cnt];
        end
      end
    end

  endgenerate

  genvar gen_init_cnt;
  generate
    for (gen_init_cnt = 0; gen_init_cnt < num_blocks; gen_init_cnt = gen_init_cnt + 1) begin
      assign rdata[0].leveldata[gen_init_cnt] = rdata_OR[gen_init_cnt];
    end
  endgenerate

  assign rdata_o = rdata[b].leveldata[0];

  integer write_block_id0;
  integer write_reg_id0;
  always @(posedge clk_i) begin
    for (
        write_block_id0 = 0; write_block_id0 < num_blocks; write_block_id0 = write_block_id0 + 1
    ) begin
      for (
          write_reg_id0 = 0; write_reg_id0 < num_regs_in_block; write_reg_id0 = write_reg_id0 + 1
      ) begin
        if (we & (  /*3'*/ (write_block_id0) == inter_block_addr_stage1)) begin
          mem[write_block_id0][write_reg_id0] <= 
            (((wdata & wmask) | (mem[write_block_id0][write_reg_id0] & ~wmask)) &
             {DataWidth{OH_in_reg[write_reg_id0]}}) |
            (mem[write_block_id0][write_reg_id0] & ~{DataWidth{OH_in_reg[write_reg_id0]}});
        end
      end
    end
  end

endmodule

