# Test for LUI and AUIPC instructions.
# The goal is to write the value 25 to memory address 100.
# This is verified by the testbench in riscvaddIRinstructions.sv.

.globl _start

_start:
    # Instruction at 0x00
    # Load 0 into x5 using LUI. This tests LUI with a zero immediate.
    # Although 'mv x5, x0' would be equivalent, this specifically tests LUI.
    lui x5, 0           # x5 = 0

    # Instruction at 0x04
    # Add 25 to x5. Now x5 holds the value to be stored.
    addi x5, x5, 25     # x5 = 25

    # Instruction at 0x08
    # Use AUIPC to get the current PC value into a register.
    # PC-relative addressing test.
    auipc x6, 0         # x6 = PC + 0 = 0x8

    # Instruction at 0x0C
    # Adjust x6 to become the target address 100 (0x64).
    # We need to add 100 - 8 = 92.
    addi x6, x6, 92     # x6 = 8 + 92 = 100

    # Instruction at 0x10
    # Store the value in x5 (25) at the address in x6 (100).
    sw x5, 0(x6)        # Memory[100] = 25

    # Instruction at 0x14
    # Infinite loop to end the simulation.
loop:
    beq x0, x0, loop    # branch to self
