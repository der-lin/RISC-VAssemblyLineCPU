# riscvtest.s
# Test for RISC-V Five-Stage Pipeline Processor
#
# This test is based on the machine code from sim/riscvtest.txt

#       RISC-V Assembly         Description                       Address   Machine Code
main:   addi x1, x0, 10         # x1 = 10                         0         00a00093
        nop                     #                                 4         00000013
        nop                     #                                 8         00000013
        addi x2, x0, 20         # x2 = 20                         C         01400113
        nop                     #                                 10        00000013
        nop                     #                                 14        00000013
        sub x3, x2, x1          # x3 = 20 - 10 = 10               18        401101b3
        nop                     #                                 1C        00000013
        nop                     #                                 20        00000013
        slti x4, x3, 11         # x4 = (10 < 11) ? 1 : 0          24        00b1a213
        nop                     #                                 28        00000013
        nop                     #                                 2C        00000013
        slli x5, x4, 4          # x5 = 1 << 4 = 16                30        00421293
        nop                     #                                 34        00000013
        nop                     #                                 38        00000013
        addi x6, x0, 8          # x6 = 8                          3C        00800313
        nop                     #                                 40        00000013
        nop                     #                                 44        00000013
        add x5, x5, x6          # x5 = 16 + 8 = 24                48        006282b3
        nop                     #                                 4C        00000013
        nop                     #                                 50        00000013
        addi x7, x0, -1         # x7 = -1                         54        fff00393
        nop                     #                                 58        00000013
        nop                     #                                 5C        00000013
        sltu x9, x0, x7         # x9 = (x0 < (unsigned)x7) ? 1:0  60        007034b3
        nop                     #                                 64        00000013
        nop                     #                                 68        00000013
        add x5, x5, x9          # x5 = 24 + 1 = 25                6C        009282b3
        nop                     #                                 70        00000013
        nop                     #                                 74        00000013
done:   sw x5, 100(x0)          # mem[100] = 25                   78        06502223
