// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

module ram_1p #(
	parameter DataWidth = 32,
	parameter AddrWidth = 32,
	parameter Depth = 128 
) (
	input 											clk_i,
	input 											rst_ni,
	input 											req_i,
	input 											we_i,
	input 		 [AddrWidth-1:0]  addr_i,
	input 		 [DataWidth-1:0]  wdata_i,
	input 		 [DataWidth-1:0]  wmask_i,
	output reg 									rvalid_o,
	output reg [DataWidth-1:0]  rdata_o
);

	reg [DataWidth-1:0] mem [0:Depth - 1];

	always @(posedge clk_i)
		if (req_i) begin
			if (we_i) begin : sv2v_autoblock_1
				mem[addr_i] <= (mem[addr_i] & ~wmask_i) | (wdata_i & wmask_i);
			end
			rdata_o <= mem[addr_i];
		end

	always @(posedge clk_i or negedge rst_ni)
		if (!rst_ni)
			rvalid_o <= 1'sb0;
		else
			rvalid_o <= req_i;

endmodule
