# easy_cry_interactive：交互式 Feistel 加密/解密工程

## 1. 工程目标

本版本支持两种模式：

```text
SW14 = 0：加密模式，输入明文和密钥，输出密文
SW14 = 1：解密模式，输入密文和密钥，输出明文
```

输入通过拨码开关完成：

```text
SW[9:6] = 当前输入的 1 位十六进制数字，范围 0~F
SW13    = 确认当前这一位；确认后需要拨回 0
SW14    = 模式选择；建议在复位前设置好
SW[5:0] = 000000 时显示 CPU 程序输出
```

## 2. 使用流程

### 加密模式

1. 设 `SW14 = 0`。
2. 设 `SW[5:0] = 000000`。
3. 复位 CPU。
4. 板子先显示 `E0000000`，表示加密模式。
5. 使用 `SW[9:6] + SW13` 输入 8 位明文，例如 `12345678`。
6. 板子显示 `A0000000`，表示开始输入 key。
7. 使用 `SW[9:6] + SW13` 输入 4 位 key，例如 `2B7E`。
8. 程序输出并保持显示密文。若输入 `plaintext=12345678, key=2B7E`，应显示：

```text
36C8930C
```

### 解密模式

1. 设 `SW14 = 1`。
2. 设 `SW[5:0] = 000000`。
3. 复位 CPU。
4. 板子先显示 `D0000000`，表示解密模式。
5. 使用 `SW[9:6] + SW13` 输入 8 位密文，例如 `36C8930C`。
6. 板子显示 `A0000000`，表示开始输入 key。
7. 使用 `SW[9:6] + SW13` 输入 4 位 key，例如 `2B7E`。
8. 程序输出并保持显示明文。若输入 `ciphertext=36C8930C, key=2B7E`，应显示：

```text
12345678
```

## 3. Feistel 算法

32-bit 分组拆成两个 16-bit 半块：

```text
L = block[31:16]
R = block[15:0]
```

轮函数：

```text
F(R,K) = ((R xor K) + ((R << 3) xor (R >> 2))) & 0xFFFF
```

加密轮：

```text
L' = R
R' = L xor F(R,K)
```

解密轮使用反向密钥，并执行逆轮：

```text
oldR = L'
oldL = R' xor F(L',K)
```

轮密钥由 16-bit master key 派生：

```text
K0 = key
K1 = ((key << 3) xor 0x1357) & 0xFFFF
K2 = ((key >> 1) xor 0x2468) & 0xFFFF
K3 = ((key << 5) xor (key >> 3) xor 0x55AA) & 0xFFFF
```

本算法仅用于教学演示和 CPU 功能验证，不作为真实安全密码算法使用。

## 4. 数据内存结果区

| 地址 | 加密模式内容 | 解密模式内容 |
|---|---|---|
| `0x180` | plaintext | 未使用 |
| `0x184` | master key | master key |
| `0x188` | ciphertext output | 未使用 |
| `0x18C` | 未使用 | ciphertext input |
| `0x190` | 未使用 | plaintext output |
| `0x194` | final result | final result |
| `0x198` | K0 | K0 |
| `0x19C` | K1 | K1 |
| `0x1A0` | K2 | K2 |
| `0x1A4` | K3 | K3 |

## 5. Vivado 使用说明

1. 将本文件夹中的 HDL 文件加入工程：
   - `RVCPUSOC_Top.v`
   - `riscvEnd.sv`
   - `parts.sv`
   - `dm.v`
   - `MIO_BUS.v`
   - `Multi_CH32.v`
   - `seg7x16.v`
   - `clk_div.v`
   - `Nexys4DDR_CPU.xdc`
2. 指令 ROM IP：
   - `Data Width = 32`
   - `Depth = 512`
   - 初始化文件选择 `easy_cry_interactive.coe`
3. 数据 RAM 已在 `dm.v` 中扩展为 256 word：
   - `reg [31:0] RAM[255:0]`
   - `ram_addr = cpu_data_addr[9:2]`
4. 建议操作时：
   - 每确认一位后，将 `SW13` 拨回 0。
   - 模式 `SW14` 建议在复位前设置好，程序启动后只读取一次。

## 6. 文件说明

| 文件 | 说明 |
|---|---|
| `easy_cry_interactive.asm` | 交互式加密/解密汇编源码，含详细注释 |
| `easy_cry_interactive.txt` | 每行一条 32-bit 机器码 |
| `easy_cry_interactive.coe` | Vivado 指令 ROM 初始化文件 |
| `assemble_rv32i.py` | 小型 RV32I 汇编器，可重新生成 txt/coe |
| `*.v/*.sv/*.xdc` | 配套 FPGA 工程文件 |

重新汇编：

```bash
python3 assemble_rv32i.py easy_cry_interactive.asm
```
