    .text
    .globl _start

    # Copyright (c) 2026 Qin Liu, Wuhan University
    #
    # RV32I 37-instruction pipelined CPU test program (test37).
    # All rights reserved.

    # =========================================================================
    # RV32I 37-Instruction Pipelined CPU Test Program 
    #
    # *** IMPORTANT: This program MUST be loaded starting at address 0x00000000.
    # *** AUIPC, JAL, and JALR expected values depend on absolute PC addresses.
    # *** If the start address is different, those results will NOT match!
    #
    # Target: 5-stage pipeline, branch/jump resolved in EX stage,
    #         forwarding + load-use stall + branch flush.
    #
    # Instructions covered (37):
    #   U-type:     LUI, AUIPC
    #   I-type ALU: ADDI, SLTI, SLTIU, XORI, ORI, ANDI, SLLI, SRLI, SRAI
    #   R-type:     ADD, SUB, SLL, SLT, SLTU, XOR, SRL, SRA, OR, AND
    #   Jump:       JAL, JALR
    #   Branch:     BEQ, BNE, BLT, BGE, BLTU, BGEU
    #   Load:       LB, LH, LW, LBU, LHU
    #   Store:      SB, SH, SW
    #
    # Verification: ALL 37 instructions verifiable through final register
    #               values alone.
    #
    # Test operands:
    #   x1 = 5, x2 = -15 (0xFFFFFFF1), x3 = 0x80000000
    #   x20 = 0x300 (data base), x31 = accumulator
    #
    # Success condition:
    #   (1) Testbench: PC reaches END loop (0x24C) and x31 == 507 (accumulator).
    #   (2) Not sufficient alone: compare ALL expected final registers (x0–x31)
    #       and data memory (0x300–0x314) against the table below. Instructions
    #       whose results sit only in x3–x27 etc. are not proved by x31 only.
    #
    # Total: 148 instructions = 592 bytes
    # Data memory: 0x300 – 0x314 (6 words, sequential)
    #
    # Sections:
    #   §1  Setup constants                                (6 instr)
    #   §2  Forward branch tests (compact)                 (24 instr)
    #   §3  Backward branch / loop tests                   (27 instr)
    #   §4  JAL / JALR tests (incl. JAL backward)          (16 instr)
    #   §5  Memory tests (SW/SB/SH + loads + LW→SW RAW)    (15 instr)
    #   §5b Verify 0-gap LW→SW store result                (3 instr)
    #   §6  Negative offset SW/LW + load-use stall test    (4 instr)
    #   §7  x0 hardwired-zero test                         (2 instr)
    #   §8  Comparison & SRA tests → x31                   (15 instr)
    #   §9  I-type & R-type ALU tests → registers          (15 instr)
    #   §10 Pipeline hazard tests                          (20 instr)
    #   END Infinite loop (testbench checks x31 here)      (1 instr)
    # =========================================================================

_start:
    # =====================  §1  Setup Constants  (6)  ========================
    lui   x3,  0x80000          # x3  = 0x80000000
    addi  x1,  x0, 5            # x1  = 5
    addi  x2,  x0, -15          # x2  = 0xFFFFFFF1
    addi  x20, x0, 0x300        # x20 = 0x300
    addi  x31, x0, 0            # x31 = 0
    auipc x4,  0xFFFFF          # x4  = PC + 0xFFFFF000 → 0xFFFFF014

    # =====================  §2  Forward Branch Tests  (24)  ==================
    # Compact 4-instruction scheme per branch type:
    #   [NT branch]  should fall through
    #   [T branch]   should take → skip ERR to OK
    #   addi ERR     reached only if either branch misbehaves
    #   addi OK      correct-path contribution
    # Boundary cases (equal operands) covered by §3 loops.

    # BEQ
    beq   x1, x2, S2_beq_err    # 5 == -15?  NO → fall through
    beq   x1, x1, S2_beq_ok     # 5 == 5?   YES → taken
S2_beq_err:
    addi  x31, x31, 1000
S2_beq_ok:
    addi  x31, x31, 3           # +1+2

    # BNE
    bne   x1, x1, S2_bne_err    # 5 != 5?    NO → fall through
    bne   x1, x2, S2_bne_ok     # 5 != -15? YES → taken
S2_bne_err:
    addi  x31, x31, 1001
S2_bne_ok:
    addi  x31, x31, 7           # +3+4

    # BLT
    blt   x1, x2, S2_blt_err    # 5 <s -15?  NO → fall through
    blt   x2, x1, S2_blt_ok     # -15 <s 5? YES → taken
S2_blt_err:
    addi  x31, x31, 1002
S2_blt_ok:
    addi  x31, x31, 11          # +5+6

    # BGE
    bge   x2, x1, S2_bge_err    # -15 >=s 5? NO → fall through
    bge   x1, x2, S2_bge_ok     # 5 >=s -15? YES → taken
S2_bge_err:
    addi  x31, x31, 1003
S2_bge_ok:
    addi  x31, x31, 15          # +7+8

    # BLTU
    bltu  x2, x1, S2_bltu_err   # big <u 5?   NO → fall through
    bltu  x1, x2, S2_bltu_ok    # 5 <u big?  YES → taken
S2_bltu_err:
    addi  x31, x31, 1004
S2_bltu_ok:
    addi  x31, x31, 19          # +9+10

    # BGEU
    bgeu  x1, x2, S2_bgeu_err   # 5 >=u big?  NO → fall through
    bgeu  x2, x1, S2_bgeu_ok    # big >=u 5? YES → taken
S2_bgeu_err:
    addi  x31, x31, 1005
S2_bgeu_ok:
    addi  x31, x31, 23          # +11+12
    # §2 subtotal: 3+7+11+15+19+23 = 78

    # =====================  §3  Backward Branch / Loop Tests  (27)  ==========
    # One loop per branch type.  Equal-operand boundary cases are tested
    # at loop exit/continuation points (marked ★).

    # BEQ loop: x5 = 2→1→0
    addi  x5, x0, 2
S3_beq_top:
    addi  x5, x5, -1
    beq   x5, x0, S3_beq_done
    beq   x0, x0, S3_beq_top
S3_beq_done:
    addi  x31, x31, 16

    # BNE loop: x6 = 2→1→0
    addi  x6, x0, 2
S3_bne_top:
    addi  x6, x6, -1
    bne   x6, x0, S3_bne_top
    addi  x31, x31, 32

    # BLT loop: x7 = -1→0→1  (★ exit: 1<1 false)
    addi  x7, x0, -1
    addi  x8, x0, 1
S3_blt_top:
    addi  x7, x7, 1
    blt   x7, x8, S3_blt_top
    addi  x31, x31, 48

    # BGE loop: x9 = 1→0→-1  (★ continues at 0>=0 true)
    addi  x9, x0, 1
S3_bge_top:
    addi  x9, x9, -1
    bge   x9, x0, S3_bge_top
    addi  x31, x31, 64

    # BLTU loop: x10 = 0→1→2  (★ exit: 2<u2 false)
    addi  x10, x0, 0
    addi  x11, x0, 2
S3_bltu_top:
    addi  x10, x10, 1
    bltu  x10, x11, S3_bltu_top
    addi  x31, x31, 80

    # BGEU loop: x12 = 2→1→0  (★ continues at 1>=u1 true; reuses x8=1)
    addi  x12, x0, 2
S3_bgeu_top:
    addi  x12, x12, -1
    bgeu  x12, x8, S3_bgeu_top
    addi  x31, x31, 96
    # §3 subtotal: 16+32+48+64+80+96 = 336.  Running x31 = 414.

    # =====================  §4  JAL / JALR Tests  (16)  ======================

    # 4A: JAL forward + backward, JALR returns
    #     Flow: [57]jal fwd→[60] → [60]jal back→[58] → [58]jalr→[61]
    jal   x0, S4A_setup          # JAL forward (skip callee)
S4A_callee:
    jalr  x29, x28, 0           # JALR returns to x28 (= S4A_return)
    addi  x31, x31, 2000        # ERR: only reached if JALR fails
S4A_setup:
    jal   x28, S4A_callee       # ★ JAL backward (negative immediate)
S4A_return:
    addi  x31, x31, 1

    # 4B: JALR with positive offset (+4)
    auipc x30, 0
    addi  x30, x30, 12
    jalr  x5, x30, 4
    addi  x31, x31, 2001
S4_pos_target:
    addi  x31, x31, 2

    # 4C: JALR with negative offset (-8)
    jal   x0, S4_neg_setup
S4_neg_target:
    addi  x31, x31, 4
    jal   x0, S4_after_neg
S4_neg_setup:
    auipc x6, 0
    jalr  x7, x6, -8
    addi  x31, x31, 2003
S4_after_neg:
    # §4 subtotal: 1+2+4 = 7.  Running x31 = 421.

    # =====================  §5  Memory Tests  (15)  ==========================
    lui   x11, 0x11223
    addi  x11, x11, 0x344       # x11 = 0x11223344

    sw    x11, 0(x20)           # mem[0x300] = 0x11223344  (LE: 44 33 22 11)
    sb    x2, 1(x20)            # byte 0xF1 → byte[1]     (LE: 44 F1 22 11)
    sh    x2, 2(x20)            # half 0xFFF1 → byte[2:3] (LE: 44 F1 F1 FF)
                                # word = 0xFFF1F144

    lb    x12, 1(x20)           # x12 = sign_ext(0xF1)    = 0xFFFFFFF1
    lbu   x13, 1(x20)           # x13 = zero_ext(0xF1)    = 0x000000F1
    lh    x14, 2(x20)           # x14 = sign_ext(0xFFF1)  = 0xFFFFFFF1
    lhu   x15, 2(x20)           # x15 = zero_ext(0xFFF1)  = 0x0000FFF1
    lw    x16, 0(x20)           # x16 = 0xFFF1F144

    # LW→SW 0-gap (load-use stall for store data)
    lw    x17, 0(x20)
    sw    x17, 4(x20)           # mem[0x304] = 0xFFF1F144

    # LW→SW 1-gap (forwarding for store data; filler = §6 base setup)
    lw    x18, 0(x20)
    addi  x19, x20, 20          # x19 = 0x314 — 1-gap filler
    sw    x18, 8(x20)           # mem[0x308] = 0xFFF1F144

    # =====================  §5b  Verify 0-gap Store  (3)  ====================
    lw    x6, 4(x20)            # x6 = mem[0x304]  (should == x16)
    xor   x6, x6, x16           # 0 if correct
    add   x31, x31, x6          # x31 += 0  (or large error)

    # =====================  §6  Negative Offset + Load-Use Test  (4)  ========
    addi  x22, x0, -1           # known stale value for x22
    sw    x1, -8(x19)           # mem[0x30C] = 5
    lw    x22, -8(x19)          # x22 = 5  (0-gap load-use stall)
    add   x31, x31, x22         # x31 += 5
    # §6 subtotal: +5.  Running x31 = 426.

    # =====================  §7  x0 Hardwired-Zero Test  (2)  =================
    addi  x0, x1, 0x123
    add   x31, x31, x0          # x31 unchanged (x0 must remain 0)

    # =====================  §8  Comparison & SRA Tests  (15)  ================
    slt   x6, x2, x1            # 1
    slt   x8, x1, x2            # 0
    sub   x6, x6, x8            # 1
    add   x31, x31, x6          # +1

    sltu  x6, x1, x3            # 1
    sltu  x8, x2, x1            # 0
    sub   x6, x6, x8            # 1
    add   x31, x31, x6          # +1

    sltiu x6, x1, -1            # 1
    sltiu x8, x1, 5             # 0
    sub   x6, x6, x8            # 1
    add   x31, x31, x6          # +1

    sra   x6, x3, x1            # 0xFC000000
    srli  x6, x6, 26            # 63
    add   x31, x31, x6          # +63
    # §8 subtotal: 66.  Running x31 = 492.

    # =====================  §9  ALU Tests → Registers  (15)  =================
    xori  x6,  x1, -1           # x6  = 0xFFFFFFFA
    ori   x7,  x1, -3           # x7  = 0xFFFFFFFD
    andi  x8,  x2, 0x1F         # x8  = 0x00000011
    slli  x9,  x1, 10           # x9  = 0x00001400
    srli  x10, x3, 24           # x10 = 0x00000080
    srai  x17, x2, 4            # x17 = 0xFFFFFFFF
    add   x18, x1, x2           # x18 = 0xFFFFFFF6
    sub   x19, x1, x2           # x19 = 0x00000014
    xor   x21, x1, x2           # x21 = 0xFFFFFFF4
    sll   x22, x2, x1           # x22 = 0xFFFFFE20
    srl   x23, x3, x1           # x23 = 0x04000000
    or    x25, x1, x2           # x25 = 0xFFFFFFF5
    and   x26, x1, x2           # x26 = 0x00000001
    sltu  x24, x1, x3           # x24 = 0x00000001
    slti  x27, x2, 0            # x27 = 0x00000001

    # =====================  §10  Pipeline Hazard Tests  (20)  ================
    # 10A: ALU→Branch forwarding
    addi  x28, x0, 0
    beq   x28, x0, S10A_OK
    addi  x31, x31, 1010
S10A_OK:
    addi  x31, x31, 1

    # 10B: Load→Branch hazard (stall)
    sw    x0, 20(x20)
    lw    x29, 20(x20)
    beq   x29, x0, S10B_OK
    addi  x31, x31, 1011
S10B_OK:
    addi  x31, x31, 2

    # 10C: ALU→JALR forwarding
    auipc x30, 0
    addi  x30, x30, 16
    jalr  x0, x30, 0
    addi  x31, x31, 1012
S10C_TARGET:
    addi  x31, x31, 4

    # 10D: Load→JALR hazard (stall, uses JALR offset +20)
    auipc x28, 0
    sw    x28, 16(x20)          # mem[0x310] = auipc value
    lw    x29, 16(x20)          # load-use hazard
    jalr  x0, x29, 20           # target = x29 + 20
    addi  x31, x31, 1013
S10D_TARGET:
    addi  x31, x31, 8
    # §10 subtotal: 1+2+4+8 = 15.  Total x31 = 507 = 0x1FB.

    # =====================  END  ============================================
    # Testbench detects this loop (PC = 0x24C) and checks x31 == 507.
END:
    beq   x0, x0, END

    # =========================================================================
    # EXPECTED FINAL REGISTER VALUES
    #
    #   Reg   Hex Value    Source
    #   ----  ----------   -----------------------------------------
    #   x0  = 0x00000000   hardwired zero
    #   x1  = 0x00000005   §1 ADDI
    #   x2  = 0xFFFFFFF1   §1 ADDI
    #   x3  = 0x80000000   §1 LUI
    #   x4  = 0xFFFFF014   §1 AUIPC
    #   x5  = 0x00000104   §4B JALR rd save
    #   x6  = 0xFFFFFFFA   §9 XORI
    #   x7  = 0xFFFFFFFD   §9 ORI
    #   x8  = 0x00000011   §9 ANDI
    #   x9  = 0x00001400   §9 SLLI
    #   x10 = 0x00000080   §9 SRLI
    #   x11 = 0x11223344   §5 LUI + ADDI
    #   x12 = 0xFFFFFFF1   §5 LB  sign_ext(0xF1)
    #   x13 = 0x000000F1   §5 LBU zero_ext(0xF1)
    #   x14 = 0xFFFFFFF1   §5 LH  sign_ext(0xFFF1)
    #   x15 = 0x0000FFF1   §5 LHU zero_ext(0xFFF1)
    #   x16 = 0xFFF1F144   §5 LW
    #   x17 = 0xFFFFFFFF   §9 SRAI
    #   x18 = 0xFFFFFFF6   §9 ADD
    #   x19 = 0x00000014   §9 SUB
    #   x20 = 0x00000300   §1 ADDI (mem base)
    #   x21 = 0xFFFFFFF4   §9 XOR
    #   x22 = 0xFFFFFE20   §9 SLL
    #   x23 = 0x04000000   §9 SRL
    #   x24 = 0x00000001   §9 SLTU
    #   x25 = 0xFFFFFFF5   §9 OR
    #   x26 = 0x00000001   §9 AND
    #   x27 = 0x00000001   §9 SLTI
    #   x28 = 0x00000234   §10D auipc
    #   x29 = 0x00000234   §10D load→JALR target
    #   x30 = 0x00000230   §10C ALU→JALR target
    #   x31 = 0x000001FB   accumulator (507)
    #
    # EXPECTED FINAL MEMORY
    #
    #   Address   Value        Source
    #   --------  ----------   ------------------------------------
    #   0x300     0xFFF1F144   §5 SW→SB→SH overlap
    #   0x304     0xFFF1F144   §5 LW→SW 0-gap  (verified by §5b)
    #   0x308     0xFFF1F144   §5 LW→SW 1-gap
    #   0x30C     0x00000005   §6 negative offset SW
    #   0x310     0x00000234   §10D auipc value
    #   0x314     0x00000000   §10B zero
    # =========================================================================
