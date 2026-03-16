# --- 初始化 ---
addi x1, x0, 0          # x1 是我们的积分器，预期最终得分为 3
addi x2, x0, 10         # x2 = 10
addi x3, x0, 10         # x3 = 10

# --- 测试 1: Branch Not Taken (不跳转，不应冲刷) ---
bne x2, x3, fail        # 10 == 10，条件不成立，PCSrcE 应为 0
addi x1, x1, 1          # 积分 +1：x1 = 1 (这条指令必须正常执行)

# --- 测试 2: Branch Taken (跳转，必须冲刷两条指令) ---
beq x2, x3, pass_1      # 10 == 10，条件成立，跳转到 pass_1！PCSrcE 变为 1
addi x1, x0, 99         # ☠️ 毒药指令 1 (在 ID 阶段，必须被 FlushD 杀掉)
addi x1, x0, 99         # ☠️ 毒药指令 2 (在 IF 阶段，必须被 FlushE 杀掉)

pass_1:
addi x1, x1, 1          # 积分 +1：x1 = 2 (跳转成功后执行的第一条有效指令)

# --- 测试 3: 无条件跳转 jal (必须冲刷) ---
jal x5, pass_2          # 无条件跳转到 pass_2，返回地址存入 x5
addi x1, x0, 99         # ☠️ 毒药指令 3
addi x1, x0, 99         # ☠️ 毒药指令 4

pass_2:
addi x1, x1, 1          # 积分 +1：x1 = 3

# --- 结果验证 ---
# 如果所有的 Flush 都成功了，毒药指令被抹除，x1 的值应该是 3
addi x4, x0, 3          # 预期分数
bne x1, x4, fail        # 如果 x1 != 3，跳到失败逻辑
addi x10, x0, 25        # 成功标志 25
sw x10, 100(x0)         # 写入 100 地址，触发 testbench 的 "Simulation succeeded"
end:
beq x0, x0, end         # 正常结束后的死循环

fail:
addi x10, x0, 0         # 失败代码 0
sw x10, 100(x0)         # 写入 100 地址，不会触发 success
fail_loop:
beq x0, x0, fail_loop   # 失败死循环
