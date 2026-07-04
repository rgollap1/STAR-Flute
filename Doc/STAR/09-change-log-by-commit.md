# 09 — STAR Change Log by Commit

Per-commit history of the STAR modifications on base Flute (in-order 5-stage RV64GC).
Base boundary = `c6f66da`; the **59 commits after it are STAR**, all by
`Whiskeyjac` / `rgollap1` / `ravitheg`, oldest = `b0dbd64` (2021-07-20), newest =
`04a5327` (HEAD). Hashes and dates below are from `git log` and are verified.

Development happened in three phases separated by ~2-year gaps, plus a **2026
source-audit / spec-alignment layer**.

> ⚠️ **The entire 2026 layer is source-audited only and has NOT been `bsc`-compiled.**
> Several 2026 commits fix bugs introduced by earlier commits in the same layer. Do not
> present these as verified-in-silicon; build with `bsc` first.

---

## Phase 1 — Inline tagging + data-tag memory (Jul–Aug 2021)

Establishes the tag-carrying data path: a 2nd I-cache read port extracts the inline
instruction tag, the tag rides every stage, fetch/predict/ALU skip the tag container, a
parallel DT-cache (DTCache + DT_MMU_Cache) is created and wired into the hierarchy, the
memory stage issues a parallel tag request, EX computes the tag address, and
context-switch instructions are added.

| Hash | Date | Title |
|---|---|---|
| `b0dbd64` | 2021-07-20 | ICache.bsv: copied Cache.bsv, renamed ICache.bsv |
| `0e2f943` | 2021-07-20 | I_MMU_Cache uses the new ICache.bsv |
| `721d2f8` | 2021-07-20 | ICache 2nd read port extracts the inline tag |
| `b43b0a1` | 2021-07-20 | ICache debug displays |
| `952c919` | 2021-07-21 | CPU_Globals: add `tag` field to stage structs |
| `b56b5ca` | 2021-07-21 | Carry the tag through every stage |
| `de1e7ac` | 2021-07-21 | Trace the tag alongside the instruction |
| `84d8e2c` | 2021-07-23 | Branch predictor skips the inline tag |
| `879b95d` | 2021-07-23 | Pass current priv to fetch + execute |
| `64d59c1` | 2021-07-23 | ALU fall-through skips the inline tag |
| `422fdef` | 2021-07-26 | Disable tag-skipping (for testing) |
| `c7f4b5e` | 2021-07-26 | DTCache.bsv created from Cache.bsv |
| `18d85fc` | 2021-07-26 | DT_MMU_Cache.bsv created |
| `696acf2` | 2021-07-26 | DT_MMU_Cache: D-cache does DT page walks |
| `eed64a5` | 2021-07-27 | D_MMU_Cache services DT page walks |
| `def99b1` | 2021-07-27 | PTW services DT walk requests |
| `b5e6587` | 2021-07-27 | MMIO adapter: 4 clients |
| `4953506` | 2021-07-27 | DTCache interface declarations |
| `e416727` | 2021-07-27 | LLC child-cache count = 3; comments |
| `11b87df` | 2021-07-27 | Fix comment typos |
| `1d53916` | 2021-07-27 | Connect DTCache to LLC + MMIO |
| `3dabfcd` | 2021-07-27 | DTCache invocation interfaces |
| `0efb34c` | 2021-07-27 | Fix interface-name typos |
| `7c762a1` | 2021-07-27 | Change tag alignment (compiler change) |
| `8477179` | 2021-07-27 | Change ICache verbosity |
| `22807b5` | 2021-07-28 | Pass dtcache instance to Stage2 |
| `5d38dc9` | 2021-07-28 | Stage2 issues parallel DT request + stall |
| `9158460` | 2021-07-28 | Remove debug print |
| `bc0f057` | 2021-08-12 | Globals: add `tag_addr` to Stage2→3 struct |
| `b5d133f` | 2021-08-12 | Stage1 copies computed `tag_addr` forward |
| `455be17` | 2021-08-12 | Initialize `tag_addr` |
| `a1470e9` | 2021-08-12 | EX: `ALU_Outputs.tag_addr`; LOAD/STORE compute it |
| `d1cbab4` | 2021-08-12 | Mem stage uses `tag_addr`, byte-sized DT access |
| `2a3f44a` | 2021-08-12 | Context-switch instruction opcodes |
| `8f9c84f` | 2021-08-12 | Context-switch processing functions |
| `b68d58a` | 2021-08-12 | component.xml: add DT caches + LLC (GFE) |
| `638080f` | 2021-08-12 | Add WB-cache test files + default ISA backup |
| `80d70da` | 2021-08-12 | Branch-predictor tag-skip logic |
| `e7e0bef` | 2021-08-12 | Next-PC tag-skip logic |
| `65c5e37` | 2021-08-12 | ALU tag-skip logic |
| `1d67863` | 2021-08-12 | Hard tag-skip check in user mode (fetch) |

**Significant commits**

- **`b0dbd64` / `0e2f943`** — Copy `Cache.bsv` → `ICache.bsv`; re-point `I_MMU_Cache` at
  `mkICache`. ([ch 03](03-icache-inline-tag.md))
- **`721d2f8`** — First real STAR logic: adds `final_ld_tag` to `Cache_Result` and a
  `tag` word to `Valid_Info`; repurposes the data RAM's **B port** to read the
  16-byte-aligned tag container in parallel (gated off during refill); slices the 8-bit
  tag by the instruction's line offset.
- **`952c919` / `b56b5ca`** — Add `Bit#(8) tag` to the four inter-stage structs and to
  `ALU_Inputs`, and copy it through every stage. ([ch 06](06-pipeline-integration.md))
- **`84d8e2c` / `879b95d` / `64d59c1`** — Inline-tag *skip* for predict/fetch/EX: give
  the predictor and StageF a `cur_priv` argument and bump the PC by 4 when a user-mode
  fall-through lands on a 16-byte-aligned tag slot. `422fdef` temporarily disables it.
- **`c7f4b5e` / `18d85fc` / `696acf2`** — Create `DTCache.bsv` (from `Cache.bsv`) and
  `DT_MMU_Cache.bsv` (from `D_MMU_Cache.bsv`, then trimmed). `696acf2` turns DT's PTW
  *server* into a *client* — DT queues walk requests and waits on the D-cache to walk;
  removes `WATCH_TOHOST`; adds the exception-drop path. ([ch 04](04-dtcache-and-tlb.md))
- **`eed64a5` / `def99b1`** — D-cache side of the shared walk + PTW's DT stream, gated so
  DT can't walk until D-cache confirms no exception.
- **`e416727` / `b5e6587` / `1d53916`** — LLC learns it has 3 children; MMIO grows to 4
  clients; DT↔LLC / DT↔MMIO connections completed.
- **`5d38dc9` (+`22807b5`)** — Stage2 takes `DTMem_IFC dtcache`, issues a parallel tag
  request on user-mode LD/ST, and stalls until both caches complete (`ostatus1`).
- **`a1470e9` / `d1cbab4`** — Tag-address compute `(eaddr>>4)+0x003c_0000_0000` in EX;
  memory stage uses it with `f3=byte` and gates to `addr < 0x003c_0000_0000`.
- **`2a3f44a` / `8f9c84f`** — First context-switch support: `op_LOAD_CONTEXT`,
  `op_STORE_CONTEXT`, `op_TAG` opcodes + funct3s; draft `fv_LDC`/`fv_STC`.

---

## Phase 2 — Control-flow integrity (May–Aug 2023)

Adds the Stage-1 CFI state machine, the three tag register files (integer TRF, FP TRF,
TPRF), the forwarding paths, and the memory-tag encoding. Concludes by packing CFI status
+ label into one TPRF register.

| Hash | Date | Title |
|---|---|---|
| `3f3ca3a` | 2023-05-09 | CFI checks in EX + Stage1 FSM; tag regfiles imported |
| `990a0ce` | 2023-05-09 | Stage1 CFI logic tweak |
| `b9a0250` | 2023-06-19 | Create GPR/FPR TAG regfiles + TPRF; fix Stage1 CFI; add forwarding |
| `d092280` | 2023-06-23 | Complete CFI validations (Stage2/Stage3) |
| `18bec3f` | 2023-06-23 | Fix Tag/Exception naming conventions |
| `5c02582` | 2023-07-24 | Fix compilation issues |
| `f7329f4` | 2023-08-21 | Pack CFI status + label into one TPRF register |

**Significant commits**

- **`3f3ca3a`** — First CFI logic: imports the tag regfiles into `CPU.bsv`/`Stage1`/
  `Stage3`; adds `val1_tag`/`val2_tag`/`rd_val_tag` and `isNop`; first draft of the
  Stage-1 CFI target-check FSM; defines the instruction-tag constants. (Has BSV syntax
  errors cleaned up later.)
- **`b9a0250`** — Creates `GPR_TAG_RegFile.bsv`, `FPR_TAG_RegFile.bsv`,
  `TPRF_RegFile.bsv` ([ch 05](05-tag-regfiles.md)); rewrites the FSM; adds the CFI
  status/label/tag **forwarding paths** from Stage2/3 into Stage1. Introduces the
  memory-tag encoding (initially `CP=01, DP=10` — corrected later in `8aa5e13`).
- **`d092280`** — Completes CFI validations across Stage2 (+129) and Stage3.
- **`f7329f4`** — Packs CFI status + label into a single TPRF register to avoid two
  same-cycle writes.

---

## Phase 3 — Pointer integrity + finalization (2024) & fixes (2026)

### 2024 (pointer integrity)

| Hash | Date | Title |
|---|---|---|
| `0bde341` | 2024-05-27 | Makefile: new BSC library paths |
| `659ec00` | 2024-05-27 | Add all SSITH source files (shared libs + generated RTL) |
| `9c06672` | 2024-07-31 | Add missing HDL file |
| `51f112d` | 2024-08-07 | component.xml: include TPRF + TAG RF files |
| `0e89fcc` | 2024-08-07 | Pointer-integrity instruction tags |
| `65645e2` | 2024-08-07 | HARD exceptions (excep_CFI/RAP) added to ISA |
| `913161e` | 2024-08-07 | CFI state machine: indirect jump (IDJ/TIJ) |
| `de91b2b` | 2024-08-07 | Control-integrity checks on control-flow + mem instrs |
| `709344d` | 2024-08-07 | Memory-stage pointer-integrity checks |
| `04054cc` | 2024-08-07 | Rank-based destination-tag computation |
| `64bfd9f` | 2024-08-07 | Gate tag checks to user mode; update LOAD/STORE context |

**Significant commits**

- **`659ec00`** — Adds SSITH P2 build inputs incl. `bsc`-generated `Verilog_RTL/*.v`
  (`mkDTCache.v`, `mkDT_MMU_Cache.v`, big `mkCPU.v`) — **artifacts, not design**.
- **`0e89fcc`** — Pointer-integrity instruction tags (`DPO/CPO/RAP/CLR/EQR/IDJ`) + CFI
  TCHK states incl. `cfi_TCHK_IDJ`.
- **`65645e2`** — Widens `Exc_Code` 4→5 bits; defines `excep_CFI=16`, `excep_RAP=17`.
- **`913161e`** — Extends the CFI FSM for indirect jumps (`cfi_TCHK_IDJ` expects `TIJ`).
- **`de91b2b`** — Control-integrity checks in EX (`fv_JAL`/`fv_JALR`/`fv_LD`/`fv_ST`):
  `[CAL]`→`[CP]` src / produce `[RA]`; `[IDJ]`→`[CP]`; `[RET]`→`[RA]`.
- **`04054cc`** — Rank-based dest-tag `MIN(MAX(rs1,rs2), inst-rank)`; makes failed
  CFI/RAP checks set `CONTROL_TRAP`. **Note:** the rank block was placed in the
  illegal-opcode `else` — dead for legal instructions — relocated live in `d13d3c0`.
- **`709344d`** — Memory-stage pointer-integrity checks (`[RAP]`/`[DPO]`/`[CPO]`). **Note:**
  the RAP clause was joined with `&&` (always false) — fixed in `6f67e3e`.
- **`64bfd9f`** — Gates the tag machinery to user mode (`priv==0`); reworks the context
  path (later re-targeted in `b6f2fa2`/`8b68a36`).

### 2026 (fix / spec-alignment layer — source-audited, NOT `bsc`-compiled)

| Hash | Date | Title |
|---|---|---|
| `8aa5e13` | 2026-06-19 | Data-tag encoding rank order (DT<DP<CP<RA) |
| `6f67e3e` | 2026-06-19 | Fix dead [RAP] check (`&&`→`\|\|`) |
| `e75cb8d` | 2026-06-19 | Structured bit-field instruction-tag encoding + combined tags |
| `fd93f80` | 2026-06-19 | EX rejects [RA] source on [GEN] ops |
| `2eab4f6` | 2026-06-19 | Stage2 packs DT load-control word |
| `3f7c56f` | 2026-06-19 | DT-cache in-cache [CLR] validate-then-scrub + nibble-select fix |
| `c80e0a7` | 2026-06-19 | Add STAR TSRF S-mode CSRs |
| `b6f2fa2` | 2026-06-19 | Re-target STORE/LOAD_CONTEXT to TPRF; drop latch CSR |
| `6280c1a` | 2026-06-19 | Stage1: enforce CFI target-check violations as traps |
| `54afe51` | 2026-06-19 | Docs: comment STAR ISA-layer definitions |
| `09ce3ed` | 2026-06-19 | Docs: comment STAR regfile/cache/pipeline additions |
| `ebf18f6` | 2026-06-19 | Docs: comment STAR CFI/tag logic in EX_ALU_functions |
| `8b68a36` | 2026-06-19 | Context switch saves BOTH TRF + TPRF; CLR-on-store scrub |
| `d13d3c0` | 2026-06-22 | Live rank resolution + CFI trap fixes; fix 2 compile-breaking regressions |
| `04a5327` | 2026-06-26 | Widen CFI label signature 18→19 bits (S&P 2023) |

**Significant commits**

- **`8aa5e13`** — Corrects data-tag encoding to `DT(0)<DP(1)<CP(2)<RA(3)` (was
  `CP=1,DP=2`, which let a data pointer outrank a code pointer). ([ch 02](02-isa-and-tags.md))
- **`6f67e3e`** — Fixes the dead `[RAP]` memory check: the two mutually-exclusive
  violation clauses were `&&`-joined (always false); changed to `||`.
  ([ch 07](07-cfi-and-pointer-integrity.md))
- **`e75cb8d`** — Replaces the flat tag enum with the **structured 6-bit bit-field**
  (`op[2:0]`, `CLR[3]`, `target[5:4]`) + `itag_op/target/is_clr` extractors + combined
  tags; removes standalone `itag_IDJ` (indirect jump = `op_GEN`+JALR) and `itag_CLR`.
  ([ch 02](02-isa-and-tags.md))
- **`fd93f80`** — Adds explicit `[GEN]`-op rejection of an `[RA]` source in `fv_ALU`.
- **`2eab4f6` / `3f7c56f`** — In-cache `[CLR]` validate-then-scrub: load carries a control
  word `{addr[3], CLR, expected[1:0]}`; Stage2 fixes the nibble-select read (`addr[3]`);
  DT-cache strips the matching nibble to `[DT]` via RMW. ([ch 04](04-dtcache-and-tlb.md))
- **`c80e0a7`** — TPRF exposed as S-mode CSRs (`_latch=0x5C0`, `_pc=0x5C1`, `_svc=0x5C2`);
  `csr_trap_actions` latches PC+SVC on `excep_CFI`/`excep_RAP`. ([ch 02](02-isa-and-tags.md))
- **`b6f2fa2`** — Re-targets context ops to the TPRF; drops the latch CSR (latch now
  saved via the instructions); gates the U-mode latch commit. ([ch 08](08-context-switch.md))
- **`6280c1a`** — Enforces Stage-1 CFI violations: `cfi_exec_code != 0` now sets
  `exc_code` + `CONTROL_TRAP` (was computed but never applied).
  ([ch 07](07-cfi-and-pointer-integrity.md))
- **`54afe51` / `09ce3ed` / `ebf18f6`** — Comment-only doc passes across ISA / regfiles /
  caches / pipeline / EX.
- **`8b68a36`** — Context switch saves **both** TRF and TPRF (funct3 selects); adds
  symmetric **CLR-on-store** register scrub. ([ch 08](08-context-switch.md))
- **`d13d3c0`** — Relocates rank resolution out of the dead illegal-opcode branch to run
  for legal arithmetic; fixes `fv_JALR [CAL]` trap (set `exc_code` but not `control`);
  removes a bogus `fv_JAL` rs1 check; fixes 2 compile-breaking regressions (a dropped
  `csr_addr_medeleg:` case; a Stage1 label-bypass `match` merged onto a comment line).
- **`04a5327`** — Widens the CFI label signature 18→19 bits (20-bit LUI imm = 1 type +
  19 sig): Stage1 extracts `instr[30:12]`, TPRF entry-1 label slice `[21:3]`, Stage3
  packs 19 bits. ([ch 02](02-isa-and-tags.md), [ch 07](07-cfi-and-pointer-integrity.md))

---

## File → commits cross-reference

**Six new STAR files** (`src_Core/`):

| File | Created by | Later touched by |
|---|---|---|
| `Near_Mem_VM_WB_L1_L2/ICache.bsv` | `b0dbd64` | `721d2f8`, `b43b0a1`, `7c762a1`, `9158460`, `09ce3ed` |
| `Near_Mem_VM_WB_L1_L2/DTCache.bsv` | `c7f4b5e` | `0efb34c`, `3f7c56f`, `09ce3ed` |
| `Near_Mem_VM_WB_L1_L2/DT_MMU_Cache.bsv` | `18d85fc` | `696acf2`, `0efb34c`, `09ce3ed` |
| `RegFiles/GPR_TAG_RegFile.bsv` | `b9a0250` | `5c02582`, `09ce3ed` |
| `RegFiles/FPR_TAG_RegFile.bsv` | `b9a0250` | `09ce3ed` |
| `RegFiles/TPRF_RegFile.bsv` | `b9a0250` | `09ce3ed`, `04a5327` |

**Main modified base-Flute files:**

| File | STAR commits (oldest→newest) |
|---|---|
| `CPU/EX_ALU_functions.bsv` | `b56b5ca`, `64d59c1`, `422fdef`, `a1470e9`, `8f9c84f`, `65c5e37`, `3f3ca3a`, `b9a0250`, `d092280`, `18bec3f`, `5c02582`, `de91b2b`, `04054cc`, `64bfd9f`, `e75cb8d`, `fd93f80`, `b6f2fa2`, `ebf18f6`, `8b68a36`, `d13d3c0` |
| `CPU/CPU_Stage1.bsv` | `b56b5ca`, `879b95d`, `422fdef`, `b5d133f`, `455be17`, `e7e0bef`, `3f3ca3a`, `990a0ce`, `b9a0250`, `18bec3f`, `5c02582`, `f7329f4`, `913161e`, `04054cc`, `64bfd9f`, `e75cb8d`, `b6f2fa2`, `6280c1a`, `d13d3c0`, `04a5327` |
| `CPU/CPU_Stage2.bsv` | `b56b5ca`, `5d38dc9`, `d1cbab4`, `3f3ca3a`, `d092280`, `18bec3f`, `5c02582`, `f7329f4`, `709344d`, `6f67e3e`, `e75cb8d`, `2eab4f6`, `3f7c56f` |
| `CPU/CPU_Stage3.bsv` | `3f3ca3a`, `d092280`, `18bec3f`, `5c02582`, `f7329f4`, `0bde341`, `64bfd9f`, `b6f2fa2`, `8b68a36`, `04a5327` |
| `CPU/CPU_Globals.bsv` | `952c919`, `bc0f057`, `3f3ca3a`, `b9a0250`, `d092280`, `5c02582`, `09ce3ed`, `04a5327` |
| `CPU/CPU_StageF.bsv` | `b56b5ca`, `879b95d`, `1d67863`, `09ce3ed` |
| `CPU/CPU_StageD.bsv` | `b56b5ca`, `09ce3ed` |
| `CPU/CPU.bsv` | `879b95d`, `22807b5`, `3f3ca3a`, `18bec3f`, `5c02582`, `09ce3ed`, `04a5327` |
| `CPU/Branch_Predictor.bsv` | `84d8e2c`, `80d70da`, `3f3ca3a`, `09ce3ed` |
| `ISA/ISA_Decls.bsv` | `2a3f44a`, `3f3ca3a`, `b9a0250`, `d092280`, `18bec3f`, `5c02582`, `0e89fcc`, `8aa5e13`, `e75cb8d`, `54afe51`, `8b68a36` |
| `ISA/ISA_Decls_Priv_M.bsv` | `65645e2`, `54afe51` |
| `ISA/ISA_Decls_Priv_S.bsv` | `c80e0a7`, `b6f2fa2` |
| `RegFiles/CSR_RegFile_MSU.bsv` | `c80e0a7`, `b6f2fa2`, `d13d3c0` |
| `Near_Mem_VM_WB_L1_L2/D_MMU_Cache.bsv` | `eed64a5`, `09ce3ed` |
| `Near_Mem_VM_WB_L1_L2/PTW.bsv` | `def99b1`, `e416727`, `09ce3ed` |
| `Near_Mem_VM_WB_L1_L2/MMIO_AXI4_Adapter.bsv` | `b5e6587`, `e416727` |
| `Near_Mem_VM_WB_L1_L2/src_LLCache/LLCache_Aux.bsv` | `e416727` |

---

## Caveats for whoever continues this

1. **Phases split by ~2-year gaps.** 2021 = data-tag memory path; 2023 = CFI; 2024 =
   pointer integrity; 2026 = source-audit refinement.
2. **The entire 2026 layer is source-audited only** — every 2026 commit message ends with
   "NOT bsc-compiled." Several fix bugs from earlier 2026 commits (`d13d3c0` fixes two
   compile-breaking regressions; `3f7c56f`/`8b68a36` build on `e75cb8d`/`2eab4f6`).
   **Build with `bsc` before relying on any of it.**
3. **`659ec00` includes `bsc`-generated RTL** (`Verilog_RTL/*.v`) — artifacts, not design.
4. **The memory-tag encoding order was wrong from Phase 2 until `8aa5e13`** (`CP=01,
   DP=10`) — any rank comparison over that window used the swapped order.
5. **Several policy checks were present-but-non-functional between 2024 and their 2026
   fixes**: the dead RAP `&&`, the dead rank block, the unenforced CFI trap. This log
   states that per-commit rather than implying the 2024 code was correct.
6. **TPRF reset** is not in the `mkCPU` reset handshake (see
   [chapter 05 §5.5](05-tag-regfiles.md)) — low-risk today, trivially closeable with a
   build in the loop.
