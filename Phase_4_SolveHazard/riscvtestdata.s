# --- 初始化 ---
addi x1, x0, 0x64             # 基地址 x1 = 0x40
addi x2, x0, 10             # x2 = 10
addi x3, x0, 20             # x3 = 20
addi x0, x0, 0              # nop 清空流水线
addi x0, x0, 0
addi x0, x0, 0

# --- 1. 测试 EXE-EXE 前递 (距离为1) ---
add  x4, x2, x3             # x4 = 10 + 20 = 30 (在 EXE/MEM 寄存器中)
add  x5, x4, x2             # x5 = 30 + 10 = 40 (需要从 MEM 阶段前递 x4)
# 预期波形：ForwardAE 应变为 2'b10 (从 ALUResultM 前递)

# --- 2. 测试 MEM-WB 前递 (距离为2) ---
add  x6, x2, x3             # x6 = 30
addi x0, x0, 0              # 插入一个无关指令
add  x7, x6, x2             # x7 = 30 + 10 = 40 (需要从 WB 阶段前递 x6)
# 预期波形：ForwardAE 应变为 2'b01 (从 ResultW 前递)

# --- 3. 测试连续前递 (双重冒险) ---
add  x8, x2, x3             # x8 = 30
add  x8, x8, x2             # x8 = 40 (EXE-EXE 前递)
add  x9, x8, x2             # x9 = 50 (EXE-EXE 前递，验证优先级)
# 预期：始终拿取最新值

# --- 4. 测试 Load-Use 冒险 (触发 Stall) ---
sw   x2, 0(x1)              # 在地址 64 写入 10
lw   x10, 0(x1)             # x10 = 10 (从内存加载)
add  x11, x10, x2           # x11 = 10 + 10 = 20 (紧跟在 lw 后，必须 Stall)
# 预期波形：
# 1. StallF, StallD, FlushE 在一拍内同时跳变为 1
# 2. PC 和 InstrD 保持一拍不变
# 3. EXE 阶段控制信号（如 RegWriteE）清零一拍（产生 Bubble）

# --- 5. 测试 Store Data 冒险 (前递到 WriteData) ---
add  x12, x2, x3            # x12 = 30
sw   x12, 4(x1)             # 将 30 存入地址 68 (紧跟在计算后)
# 预期波形：WriteDataM 在执行 sw 时，应当拿到前递后的 30，而不是旧值

# --- 6. 验证最终结果 ---
lw   x13, 4(x1)             # x13 = 30 (验证上面的 sw 是否成功)
add  x14, x13, x11          # x14 = 30 + 20 = 50
addi x15, x0, 25            # Testbench 成功标志位
sw   x15, 100(x0)           # 如果一切正确，向地址 100 写入 25
