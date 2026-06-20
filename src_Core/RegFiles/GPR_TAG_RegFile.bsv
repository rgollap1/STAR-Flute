// Copyright (c) 2016-2020 Bluespec, Inc. All Rights Reserved

package GPR_TAG_RegFile;

// ================================================================
// GPR TAG (General Purpose Register) Register File
//
// STAR (Tagged Architecture): this module is the GPR half of the TRF
// (Tag Register File) -- a shadow copy of the base GPR register file
// that holds a 4-bit tag per architectural register instead of data.
// Each entry mirrors one x-register; the 4-bit tag is the nibble of a
// 64-bit pointer (2 tag bits per 32-bit word). Tag encodings (dtag_*):
//   0 = DT plain data, 1 = DP data pointer,
//   2 = CP code pointer, 3 = RA return address (value == rank).
// Reads/writes stay in lock-step with the base GPR regfile so the tag
// of register x[i] always travels alongside its data value.

// ================================================================
// Exports

export GPR_TAG_RegFile_IFC (..), mkGPR_TAG_RegFile;

// ================================================================
// BSV library imports

import ConfigReg    :: *;
import RegFile      :: *;
import FIFOF        :: *;
import GetPut       :: *;
import ClientServer :: *;

// BSV additional libs

import GetPut_Aux :: *;

// ================================================================
// Project imports

import ISA_Decls :: *;

// ================================================================

interface GPR_TAG_RegFile_IFC;
   // Reset
   interface Server #(Token, Token) server_reset;

   // GPR read
   (* always_ready *)
   method Bit #(4) read_rs1 (RegName rs1);
   (* always_ready *)
   method Bit #(4) read_rs1_port2 (RegName rs1);    // For debugger access only
   (* always_ready *)
   method Bit #(4) read_rs2 (RegName rs2);

   // GPR write
   (* always_ready *)
   method Action write_rd (RegName rd, Bit #(4) rd_val);

endinterface

// ================================================================
// Major states of mkGPR_TAG_RegFile module

typedef enum { RF_RESET_START, RF_RESETTING, RF_RUNNING } RF_State
deriving (Eq, Bits, FShow);

// ================================================================

(* synthesize *)
module mkGPR_TAG_RegFile (GPR_TAG_RegFile_IFC);

   Reg #(RF_State) rg_state      <- mkReg (RF_RESET_START);

   // Reset
   FIFOF #(Token) f_reset_rsps <- mkFIFOF;

   // General Purpose Registers
   // STAR: holds a 4-bit shadow tag per GPR (not data); same RegName index space as base GPR regfile
   // TODO: can we use Reg [0] for some other purpose?
   RegFile #(RegName, Bit #(4)) regfile <- mkRegFileFull;

   // ----------------------------------------------------------------
   // Reset.
   // This loop initializes all GPRs to 0.
   // The spec does not require this, but it's useful for debugging
   // and tandem verification

`ifdef INCLUDE_TANDEM_VERIF
   Reg #(RegName) rg_j <- mkRegU;    // reset loop index
`endif

   rule rl_reset_start (rg_state == RF_RESET_START);
      rg_state <= RF_RESETTING;
`ifdef INCLUDE_TANDEM_VERIF
      rg_j <= 1;
`endif
   endrule

   rule rl_reset_loop (rg_state == RF_RESETTING);
`ifdef INCLUDE_TANDEM_VERIF
      regfile.upd (rg_j, 0);
      rg_j <= rg_j + 1;
      if (rg_j == 31)
	 rg_state <= RF_RUNNING;
`else
      rg_state <= RF_RUNNING;
`endif
   endrule

   // ----------------------------------------------------------------
   // INTERFACE

   // Reset
   interface Server server_reset;
      interface Put request;
	 method Action put (Token token);
	    rg_state <= RF_RESET_START;

	    // This response is placed here, and not in rl_reset_loop, because
	    // reset_loop can happen on power-up, where no response is expected.
	    f_reset_rsps.enq (?);
	 endmethod
      endinterface
      interface Get response;
	 method ActionValue #(Token) get if (rg_state == RF_RUNNING);
	    let token <- pop (f_reset_rsps);
	    return token;
	 endmethod
      endinterface
   endinterface

   // GPR read
   // STAR: returns the 4-bit tag for rs1; x0 is hard-wired to tag 0 (DT plain data)
   method Bit #(4) read_rs1 (RegName rs1);
      return ((rs1 == 0) ? 0 : regfile.sub (rs1));
   endmethod

   // GPR read
   // STAR: second tag read port for rs1, debugger use only (mirrors read_rs1)
   method Bit #(4) read_rs1_port2 (RegName rs1);        // For debugger access only
      return ((rs1 == 0) ? 0 : regfile.sub (rs1));
   endmethod

   // STAR: returns the 4-bit tag for rs2; x0 is hard-wired to tag 0 (DT plain data)
   method Bit #(4) read_rs2 (RegName rs2);
      return ((rs2 == 0) ? 0 : regfile.sub (rs2));
   endmethod

   // GPR write
   // STAR: writes the 4-bit destination tag for rd; writes to x0 are dropped
   method Action write_rd (RegName rd, Bit #(4) rd_val);
      if (rd != 0) regfile.upd (rd, rd_val);
   endmethod

endmodule

// ================================================================

endpackage
