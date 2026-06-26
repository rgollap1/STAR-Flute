// Copyright (c) 2016-2020 Bluespec, Inc. All Rights Reserved

package TPRF_RegFile;

// ================================================================
// TPRF (Tag Processor) Register File
//
// STAR (Tagged Architecture): the TPRF is a 32-entry Word register
// file that holds the Tag Processor / TPP state. It is distinct from
// the TRF (which shadows GPR/FPR data tags): the TPRF carries the
// control-flow-integrity (CFI) and label state used by the tag engine.
// Entry 1 is special -- it packs the CFI latch in bits [2:0] and the
// active label in bits [21:3] (19-bit function signature). The whole file is saved and restored by
// the STORE_CONTEXT / LOAD_CONTEXT operations on a context switch.
// Two write ports are exposed: write_rd for the CFI/status word and
// write_rd2 for the label word.

// ================================================================
// Exports

export TPRF_RegFile_IFC (..), mkTPRF_RegFile;

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

interface TPRF_RegFile_IFC;
   // Reset
   interface Server #(Token, Token) server_reset;

   // GPR read
   (* always_ready *)
   method Word read_rs1 (RegName rs1);
   (* always_ready *)
   method Word read_rs1_port2 (RegName rs1);    // For debugger access only
   (* always_ready *)
   method Word read_rs2 (RegName rs2);

   // GPR write
   (* always_ready *) // For CFI and other Status bits 
   method Action write_rd (RegName rd1, Word rd_val);

   // GPR write
   (* always_ready *)
   method Action write_rd2 (RegName rd2, Word rd_val_label);

endinterface

// ================================================================
// Major states of mkGPR_RegFile module

typedef enum { RF_RESET_START, RF_RESETTING, RF_RUNNING } RF_State
deriving (Eq, Bits, FShow);

// ================================================================

(* synthesize *)
module mkTPRF_RegFile (TPRF_RegFile_IFC);

   Reg #(RF_State) rg_state      <- mkReg (RF_RESET_START);

   // Reset
   FIFOF #(Token) f_reset_rsps <- mkFIFOF;

   // General Purpose Registers
   // STAR: 32-entry Word file holding TPP state; entry 1 packs CFI latch [2:0] + label [21:3] (19-bit signature)
   // TODO: can we use Reg [0] for some other purpose?
   RegFile #(RegName, Word) regfile <- mkRegFileFull;

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
   // STAR: returns the TPP-state word for rs1; entry 0 reads as 0
   method Word read_rs1 (RegName rs1);
      return ((rs1 == 0) ? 0 : regfile.sub (rs1));
   endmethod

   // GPR read
   // STAR: second read port for rs1, debugger use only (mirrors read_rs1)
   method Word read_rs1_port2 (RegName rs1);        // For debugger access only
      return ((rs1 == 0) ? 0 : regfile.sub (rs1));
   endmethod

   // STAR: returns the TPP-state word for rs2; entry 0 reads as 0
   method Word read_rs2 (RegName rs2);
      return ((rs2 == 0) ? 0 : regfile.sub (rs2));
   endmethod

   // GPR write
   // STAR: write port for the CFI / status word (entry 1 bits [2:0] = CFI latch); writes to entry 0 are dropped
   method Action write_rd (RegName rd1, Word rd_val);
      if (rd1 != 0) regfile.upd (rd1, rd_val);
   endmethod

   // GPR write
   // STAR: separate write port for the label word (entry 1 bits [21:3] = label); writes to entry 0 are dropped
   method Action write_rd2 (RegName rd2, Word rd_val_label);
      if (rd2 != 0) regfile.upd (rd2, rd_val_label);
   endmethod

endmodule

// ================================================================

endpackage
