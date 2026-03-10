# riscvtest.s
# Test for RISC-V Five-Stage Pipeline Processor
#
# This test is based on the machine code from sim/riscvtest.txt

#       RISC-V Assembly         Description                       Address   Machine Code
main:   addi x1, x0, 10         # x1 = 10                         0         00A00093
        nop                     #                                 4         00000013
        nop                     #                                 8         00000013
        addi x2, x0, 15         # x2 = 15                         C         00F00113
        nop                     #                                 10        00000013
        nop                     #                                 14        00000013
        add x2, x1, x2          # x2 = x1 + x2 (10 + 15 = 25)     18        00208133
        nop                     #                                 1C        00000013
        nop                     #                                 20        00000013
        addi x3, x0, 100        # x3 = 100                        24        06400193
        nop                     #                                 28        00000013
        nop                     #                                 2C        00000013
        sw   x2, 0(x3)          # mem[100] = x2 (25)              30        0021A023
        nop                     #                                 34        00000013
        nop                     #                                 38        00000013
done:   beq  x0, x0, done       # infinite loop                   3C        00000063
        nop                     #                                 40        00000013
        nop                     #                                 44        00000013
