// Copyright (c) 2016-2019 Bluespec, Inc. All Rights Reserved

package CPU_Stage1;

// ================================================================
// This is Stage 1 of the "Flute" CPU.
// It contains the EX functionality.
// EX: "Execute"

// ================================================================
// Exports

export
CPU_Stage1_IFC (..),
mkCPU_Stage1;

// ================================================================
// BSV library imports

import FIFOF        :: *;
import GetPut       :: *;
import ClientServer :: *;
import ConfigReg    :: *;

// ----------------
// BSV additional libs

import Cur_Cycle :: *;

// ================================================================
// Project imports

import ISA_Decls        :: *;
import CPU_Globals      :: *;
import Near_Mem_IFC     :: *;
import GPR_RegFile      :: *;
import GPR_TAG_RegFile  :: *;
import TPRF_RegFile     :: *;
`ifdef ISA_F
import FPR_RegFile      :: *;
import FPR_TAG_RegFile      :: *;
`endif
import CSR_RegFile      :: *;
import EX_ALU_functions :: *;

`ifdef ISA_C
// 'C' extension (16b compressed instructions)
import CPU_Decode_C     :: *;
`endif

// ================================================================
// Interface

interface CPU_Stage1_IFC;
   // ---- Reset
   interface Server #(Token, Token) server_reset;

   // ---- Output
   (* always_ready *)
   method Output_Stage1 out;

   (* always_ready *)
   method Action deq;

   // ---- Input
   (* always_ready *)
   method Action enq (Data_StageD_to_Stage1  data);

   (* always_ready *)
   method Action set_full (Bool full);
endinterface

// ================================================================
// Implementation module

module mkCPU_Stage1 #(Bit #(4)         verbosity,
		      GPR_RegFile_IFC  gpr_regfile,
		      GPR_TAG_RegFile_IFC  gpr_tag_regfile,
		      TPRF_RegFile_IFC tprf_tag_regfile,		      
		      Bypass           bypass_from_stage2,
		      Bypass_Tag       bypass_tag_from_stage2,
		      Bypass_TPRF      bypass_tprf_from_stage2,
		      Bypass_LBL       bypass_lbl_from_stage2,
		      Bypass           bypass_from_stage3,
		      Bypass_Tag       bypass_tag_from_stage3,
                      Bypass_TPRF      bypass_tprf_from_stage3,
                      Bypass_LBL       bypass_lbl_from_stage3,

`ifdef ISA_F
		      FPR_RegFile_IFC  fpr_regfile,
		      FPR_TAG_RegFile_IFC  fpr_tag_regfile,
		      FBypass          fbypass_from_stage2,
		      FBypass          fbypass_from_stage3,
`endif
		      CSR_RegFile_IFC  csr_regfile,
		      Epoch            cur_epoch,
		      Priv_Mode        cur_priv)
                    (CPU_Stage1_IFC);

   FIFOF #(Token) f_reset_reqs <- mkFIFOF;
   FIFOF #(Token) f_reset_rsps <- mkFIFOF;

   Reg #(Bool)                  rg_full        <- mkReg (False);
   Reg #(Data_StageD_to_Stage1) rg_stage_input <- mkRegU;

   let rg_cfi        = 0;
   let rg_source_lbl = 0; 
   
   MISA misa   = csr_regfile.read_misa;
   Bit #(2) xl = ((xlen == 32) ? misa_mxl_32 : misa_mxl_64);

   // ----------------------------------------------------------------
   // BEHAVIOR

   rule rl_reset;
      f_reset_reqs.deq;
      rg_full <= False;
      f_reset_rsps.enq (?);
   endrule

   // ----------------
   // ALU

   let decoded_instr  = rg_stage_input.decoded_instr;
   let funct3         = decoded_instr.funct3;

   // Register rs1 read and bypass
   let rs1 = decoded_instr.rs1;
   let rs1_val = gpr_regfile.read_rs1 (rs1);
   match { .busy1a, .rs1a } = fn_gpr_bypass (bypass_from_stage3, rs1, rs1_val);
   match { .busy1b, .rs1b } = fn_gpr_bypass (bypass_from_stage2, rs1, rs1a);
   Bool rs1_busy = (busy1a || busy1b);
   Word rs1_val_bypassed = ((rs1 == 0) ? 0 : rs1b);

   // Register rs1 tag read and bypass
   let rs1_val_tag = gpr_tag_regfile.read_rs1 (rs1); //rgollap1 - val1 data tag
   match { .busyt1a, .rst1a } = fn_tag_bypass (bypass_tag_from_stage3, rs1, rs1_val_tag);
   match { .busyt1b, .rst1b } = fn_tag_bypass (bypass_tag_from_stage2, rs1, rst1a);
   Bool rs1_tag_busy = (busyt1a || busyt1b);
   Bit #(4) rs1_val_tag_bypassed = ((rs1 == 0) ? 0 : rst1b);
   
   // Register rs2 read and bypass
   let rs2 = decoded_instr.rs2;
   let rs2_val = gpr_regfile.read_rs2 (rs2);
   match { .busy2a, .rs2a } = fn_gpr_bypass (bypass_from_stage3, rs2, rs2_val);
   match { .busy2b, .rs2b } = fn_gpr_bypass (bypass_from_stage2, rs2, rs2a);
   Bool rs2_busy = (busy2a || busy2b);
   Word rs2_val_bypassed = ((rs2 == 0) ? 0 : rs2b);

   // Register rs2 tag read and bypass
   let rs2_val_tag = gpr_tag_regfile.read_rs2 (rs2); //rgollap1 - val2 data tag
   match { .busyt2a, .rst2a } = fn_tag_bypass (bypass_tag_from_stage3, rs2, rs2_val_tag);
   match { .busyt2b, .rst2b } = fn_tag_bypass (bypass_tag_from_stage2, rs2, rst2a);
   Bool rs2_tag_busy = (busyt2a || busyt2b);
   Bit #(4) rs2_val_tag_bypassed = ((rs2 == 0) ? 0 : rst2b);

   let rs_cfi = 1;
   let cfi_val = tprf_tag_regfile.read_rs1 (rs_cfi); //rgollap1 - cfi status
   match { .busycfia, .rscfia } = fn_tprf_bypass (bypass_tprf_from_stage3, 1, cfi_val);
   match { .busycfib, .rscfib } = fn_tprf_bypass (bypass_tprf_from_stage2, 1, rscfia);
   Bool rscfi_busy = (busycfia || busycfib);
   rg_cfi = rscfib[2:0];

   let rs_lbl = 1;  
   let cfi_lbl = tprf_tag_regfile.read_rs2 (rs_lbl); //rgollap1 - cfi label
   match { .busylbla, .rslbla } = fn_lbl_bypass (bypass_lbl_from_stage3, 2, cfi_lbl);
   match { .busylblb, .rslblb } = fn_lbl_bypass (bypass_lbl_from_stage2, 2, rslbla);
   Bool rslbl_busy = (busylbla || busylblb);
   rg_source_lbl = rslblb[20:3];
   
`ifdef ISA_F
   // FP Register rs1 read and bypass
   let frs1_val = fpr_regfile.read_rs1 (rs1);
   match { .fbusy1a, .frs1a } = fn_fpr_bypass (fbypass_from_stage3, rs1, frs1_val);
   match { .fbusy1b, .frs1b } = fn_fpr_bypass (fbypass_from_stage2, rs1, frs1a);
   Bool frs1_busy = (fbusy1a || fbusy1b);
   WordFL frs1_val_bypassed = frs1b;

   // FP Register rs2 read and bypass
   let frs2_val = fpr_regfile.read_rs2 (rs2);
   match { .fbusy2a, .frs2a } = fn_fpr_bypass (fbypass_from_stage3, rs2, frs2_val);
   match { .fbusy2b, .frs2b } = fn_fpr_bypass (fbypass_from_stage2, rs2, frs2a);
   Bool frs2_busy = (fbusy2a || fbusy2b);
   WordFL frs2_val_bypassed = frs2b;

   // FP Register rs3 read and bypass
   let rs3 = decoded_instr.rs3;
   let frs3_val = fpr_regfile.read_rs3 (rs3);
   match { .fbusy3a, .frs3a } = fn_fpr_bypass (fbypass_from_stage3, rs3, frs3_val);
   match { .fbusy3b, .frs3b } = fn_fpr_bypass (fbypass_from_stage2, rs3, frs3a);
   Bool frs3_busy = (fbusy3a || fbusy3b);
   WordFL frs3_val_bypassed = frs3b;
`endif

   // ALU function
   let alu_inputs = ALU_Inputs {cur_priv       : cur_priv,
				pc             : rg_stage_input.pc,
				is_i32_not_i16 : rg_stage_input.is_i32_not_i16,
				instr          : rg_stage_input.instr,
				tag	       : rg_stage_input.tag,				
`ifdef ISA_C
				instr_C        : rg_stage_input.instr_C,
`endif
				decoded_instr  : rg_stage_input.decoded_instr,
				rs1_val        : rs1_val_bypassed,
				rs2_val        : rs2_val_bypassed,
				rs1_val_tag    : rs1_val_tag_bypassed[3:0],
				rs2_val_tag    : rs2_val_tag_bypassed[3:0],
`ifdef ISA_F
				frs1_val       : frs1_val_bypassed,
				frs2_val       : frs2_val_bypassed,
				frs3_val       : frs3_val_bypassed,
				frm            : csr_regfile.read_frm,
`ifdef INCLUDE_TANDEM_VERIF
                                fflags         : csr_regfile.read_fflags,
`endif
`endif
				mstatus        : csr_regfile.read_mstatus,
				misa           : csr_regfile.read_misa };

   let alu_outputs = fv_ALU (alu_inputs);

   let data_to_stage2 = Data_Stage1_to_Stage2 {pc            : rg_stage_input.pc,
					       instr         : rg_stage_input.instr,
					       tag	     : rg_stage_input.tag,
					       op_stage2     : alu_outputs.op_stage2,
					       rd            : alu_outputs.rd,
					       addr          : alu_outputs.addr,
					       tag_addr	     : alu_outputs.tag_addr, // rgollap1 -- passing the computed the tag address to the execution stage
					       val1          : alu_outputs.val1,
					       val2          : alu_outputs.val2,
					       val1_tag      : alu_outputs.val1_tag,
					       val2_tag      : alu_outputs.val2_tag,
					       cfi_tprf      : zeroExtend (rg_cfi),
					       cfi_lbl       : zeroExtend (rg_source_lbl),
`ifdef ISA_F
					       fval1         : alu_outputs.fval1,
					       fval2         : alu_outputs.fval2,
					       fval3         : alu_outputs.fval3,
					       rd_in_fpr     : alu_outputs.rd_in_fpr,
					       rs_frm_fpr    : alu_outputs.rs_frm_fpr,
					       val1_frm_gpr  : alu_outputs.val1_frm_gpr,
					       rounding_mode : alu_outputs.rm,
`endif
`ifdef INCLUDE_TANDEM_VERIF
					       trace_data    : alu_outputs.trace_data,
`endif
					       priv          : cur_priv };

   // ----------------
   // Combinational output function

   function Output_Stage1 fv_out;
      Output_Stage1 output_stage1 = ?;
      
      let cfi_status = 0;
      let cfi_label = 0;
      let cfi_exec_code = 0;
     
      if (rg_cfi == cfi_TCHK_CAL) begin // rgollap1 - function call registered 
         if (rg_stage_input.tag == itag_TFC) // function call target
	    cfi_status = 0;
	 else
            cfi_exec_code = excep_CFI; // -- ravitheg Setting CPU Trap (Exception if check fails)
      end

      else if (rg_cfi == cfi_TCHK_IDJ) begin // rgollap1 - Indirect Jump registered
         if (rg_stage_input.tag == itag_TIJ) // indirect jump target
            cfi_status = 0;
         else
            cfi_exec_code = excep_CFI; // -- ravitheg Setting CPU Trap (Exception if check fails)
      end

      else if (rg_cfi == cfi_TCHK_RET) begin // rgollap1 - function return registered
         if (rg_stage_input.tag == itag_TFR) // function return target
            cfi_status = 0;
         else
            cfi_exec_code = excep_RAP; // -- ravitheg Setting CPU Trap (Exception if check fails)
      end

      else if (rg_cfi == 0) begin // rgollap1 - Checking for a fucntion call otr return
         if (rg_stage_input.tag == itag_CAL)
	    cfi_status = cfi_TCHK_CAL;
	 else if (rg_stage_input.tag == itag_RET) // function call or function return
            cfi_status = cfi_TCHK_RET;
	 else if (rg_stage_input.tag == itag_IDJ) // Indirect Jump
            cfi_status = cfi_TCHK_IDJ;
	 else if (rg_stage_input.tag == itag_LBL) // checking for function label
            if (rg_stage_input.instr[31] == 0) begin // checking if the lbl is source lbl not a dest lbl encountered in a pass through
	       cfi_status = cfi_TCHK_LBL_SRC; 
	       cfi_label = rg_stage_input.instr[30:13];
	    end
      end

      else if (rg_cfi == cfi_TCHK_LBL_SRC) begin // rgollap1 - checking for intermediate instruction or target instrtuction after source lbl
           if (rg_stage_input.tag == itag_CAL || rg_stage_input.tag == itag_RET || rg_stage_input.tag == itag_IDJ)
	       cfi_status = cfi_TCHK_LBL_CFI;
           else
	      cfi_exec_code = excep_CFI; // -- ravitheg Setting CPU Trap 
      end

      else if  (rg_cfi == cfi_TCHK_LBL_CFI) begin
	    if (rg_stage_input.tag == itag_LBL && rg_stage_input.instr[30:13] == rg_source_lbl[17:0]) begin
	       cfi_status = 0;
	       cfi_label = 0;
	    end
	    else
	       cfi_exec_code = excep_CFI; // -- ravitheg Setting CPU Trap
      end
	 
      // This stage is empty
      if (! rg_full) begin
	 output_stage1.ostatus = OSTATUS_EMPTY;
      end

      // Wrong branch-prediction epoch: discard instruction (convert into a NOOP)
      else if (rg_stage_input.epoch != cur_epoch || alu_outputs.isNop ) begin
	 output_stage1.ostatus = OSTATUS_PIPE;
	 output_stage1.control = CONTROL_DISCARD;

	 // For debugging only
	 let data_to_stage2 = Data_Stage1_to_Stage2 {pc:        rg_stage_input.pc,
						     instr:     rg_stage_input.instr,
						     tag:	rg_stage_input.tag,
						     op_stage2: OP_Stage2_ALU,
						     rd:        0,
						     addr:      ?,
						     tag_addr:  ?,  // rgollap1 -- initializing the tag address to remove stale addresses
						     val1:      ?,
						     val2:      ?,
						     val1_tag:  ?,
						     val2_tag:  ?,
						     cfi_tprf:  ?,
						     cfi_lbl:   ?,
`ifdef ISA_F
						     fval1           : ?,
						     fval2           : ?,
						     fval3           : ?,
						     rd_in_fpr       : ?,
					             rs_frm_fpr      : ?,
					             val1_frm_gpr    : ?,
						     rounding_mode   : ?,
`endif
`ifdef INCLUDE_TANDEM_VERIF
						     trace_data: alu_outputs.trace_data,
`endif
						     priv:      cur_priv
						     };

	 output_stage1.data_to_stage2 = data_to_stage2;
      end

      // Stall if bypass pending for GPR rs1 or rs2
      else if (rs1_busy || rs2_busy) begin
	 output_stage1.ostatus = OSTATUS_BUSY;
      end

`ifdef ISA_F
      // Stall if bypass pending for FPR rs1, rs2 or rs3
      else if (frs1_busy || frs2_busy || frs3_busy) begin
	 output_stage1.ostatus = OSTATUS_BUSY;
      end
`endif

      // Trap on fetch-exception
      else if (rg_stage_input.exc) begin
	 output_stage1.ostatus   = OSTATUS_NONPIPE;
	 output_stage1.control   = CONTROL_TRAP;
	 output_stage1.trap_info = Trap_Info {epc:      rg_stage_input.pc,
					      exc_code: rg_stage_input.exc_code,
					      tval:     rg_stage_input.tval};
	 output_stage1.data_to_stage2 = data_to_stage2;
      end

      // ALU outputs: pipe (straight/branch)
      // and non-pipe (CSRR_W, CSRR_S_or_C, FENCE.I, FENCE, SFENCE_VMA, xRET, WFI, TRAP)
      else begin
	 let ostatus = (  (   (alu_outputs.control == CONTROL_STRAIGHT)
			   || (alu_outputs.control == CONTROL_BRANCH))
			? OSTATUS_PIPE
			: OSTATUS_NONPIPE);

	 // Compute MTVAL in case of traps
	 let tval = 0;
	 if (alu_outputs.exc_code == exc_code_ILLEGAL_INSTRUCTION || alu_outputs.exc_code == excep_CFI || alu_outputs.exc_code == excep_RAP) begin
	    // The instruction
`ifdef ISA_C
	    tval = (rg_stage_input.is_i32_not_i16
		    ? zeroExtend (rg_stage_input.instr)
		    : zeroExtend (rg_stage_input.instr_C));
`else
	    tval = zeroExtend (rg_stage_input.instr);
`endif
	 end
	 else if (alu_outputs.exc_code == exc_code_INSTR_ADDR_MISALIGNED)
	    tval = alu_outputs.addr;                           // The branch target pc
	 else if (alu_outputs.exc_code == exc_code_BREAKPOINT)
	    tval = rg_stage_input.pc;                          // The faulting virtual address

	 let trap_info = Trap_Info {epc:      rg_stage_input.pc,
				    exc_code: alu_outputs.exc_code,
				    tval:     tval};

	 let fall_through_pc = rg_stage_input.pc + (rg_stage_input.is_i32_not_i16 ? 4 : 2);


	 let next_pc = ((alu_outputs.control == CONTROL_BRANCH)
			? alu_outputs.addr
			: fall_through_pc);
	 let redirect = (next_pc != rg_stage_input.pred_pc);

         output_stage1.data_to_stage2.cfi_tprf  = zeroExtend (cfi_status);
	 output_stage1.data_to_stage2.cfi_lbl   = zeroExtend (cfi_label);
	 output_stage1.ostatus        = ostatus;
	 output_stage1.control        = alu_outputs.control;
	 output_stage1.trap_info      = trap_info;
	 output_stage1.redirect       = redirect;
	 output_stage1.next_pc        = next_pc;
	 output_stage1.cf_info        = alu_outputs.cf_info;
	 output_stage1.data_to_stage2 = data_to_stage2;
      end

      return output_stage1;
   endfunction: fv_out

   // ================================================================
   // INTERFACE

   // ---- Reset
   interface server_reset = toGPServer (f_reset_reqs, f_reset_rsps);

   // ---- Output
   method Output_Stage1 out;
      return fv_out;
   endmethod

   method Action deq ();
   endmethod

   // ---- Input
   method Action enq (Data_StageD_to_Stage1  data);
      rg_stage_input <= data;
      if (verbosity > 1)
	 $display ("    CPU_Stage1.enq: 0x%08h", data.pc);
   endmethod

   method Action set_full (Bool full);
      rg_full <= full;
   endmethod
endmodule

// ================================================================

endpackage
