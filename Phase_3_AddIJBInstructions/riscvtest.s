# RISC-V 测试集: 测试访存、分支、跳转指令
# 包含 3 个 nop 以适配简单的 5 级流水线延迟

# === 1. 初始化阶段 ===
addi x1, x0, 10       # x1 = 10
nop
nop
nop
addi x2, x0, 20       # x2 = 20
nop
nop
nop

# === 2. 测试 B-Type 分支指令 (bne) ===
bne x1, x2, 20        # 因为 10 != 20，条件成立，跳转到 Target 1 (PC + 20)
nop
nop
nop
# 以下指令应该被跳过 (如果执行了，说明 bne 失败)
addi x1, x0, 100      

# ---> Target 1 (PC = 0x34)
# === 3. 测试访存指令 (sb, lb) ===
addi x3, x0, 64       # 设定一个安全的内存基地址 x3 = 64
nop
nop
nop
sb x1, 0(x3)          # 将 x1 (10) 的低字节存入地址 64
nop
nop
nop
lb x4, 0(x3)          # 从地址 64 加载字节到 x4，此时 x4 应该等于 10
nop
nop
nop

# === 4. 测试 J-Type 跳转指令 (jal) ===
jal x5, 20            # 无条件跳转到 Target 2 (PC + 20)
nop
nop
nop
# 以下指令应该被跳过 (如果执行了，说明 jal 失败)
addi x4, x0, 100

# ---> Target 2 (PC = 0x78)
# === 5. 触发 Testbench 成功条件 ===
# testbench 要求: MemWrite=1 时, DataAdr=100 且 WriteData=25
addi x6, x0, 100      # x6 = 100 (目标地址)
addi x7, x0, 25       # x7 = 25  (目标数据)
nop
nop
nop
sw x7, 0(x6)          # 触发成功！写入 25 到地址 100

# === 6. 结束 (死循环) ===
end_loop:
beq x0, x0, 0         # 无限循环当前指令