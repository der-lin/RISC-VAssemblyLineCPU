# --- Initiallization ---
addi x1, x0, 0x40          # Add test basic address, x1 = 0x100
lui  x2, 0xf4f3f
addi x0, x0, 0
addi x0, x0, 0
addi x0, x0, 0
addi x2, x2, 0x2f1
addi x0, x0, 0
addi x0, x0, 0
addi x0, x0, 0
add  x3, x0, x2
addi x0, x0, 0
addi x0, x0, 0

# --- test save ---
sb x2, 1(x1)                # Write 0xF1 into 0x101
sh x3, 2(x1)                # Write 0xF2F1 into 0x102
addi x0, x0, 0
addi x0, x0, 0
addi x0, x0, 0

# --- test load ---
lb x4, 1(x1)                # Read 0xF1 from 0x101 and x3 = 0xFFFFFFF1
lbu x5, 1(x1)               # Read 0xF1 from 0x101 and x4 = 0x000000F1
lh x6, 2(x1)                # Read 0xFFF2 from 0x102 and x5 = 0xFFFFF2F1
lhu x7, 2(x1)               # Read 0xFFF2 from 0x102 and x6 = 0x0000F2F1

# --- test ---
addi x10, x0, 25
addi x0, x0, 0
addi x0, x0, 0
addi x0, x0, 0
sw x10, 100(x0)
