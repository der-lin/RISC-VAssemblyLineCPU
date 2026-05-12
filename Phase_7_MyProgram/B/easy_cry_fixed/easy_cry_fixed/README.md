# easy_cry_fixed：固定向量 Feistel 加密/解密板级验证工程

## 1. 工程目标

本版本用于优先验证 CPU 能否正确执行主要加密/解密程序。程序不需要用户输入，复位后自动运行：

```text
plaintext       = 0x12345678
master_key      = 0x00002B7E
expected_cipher = 0x36C8930C
```

程序会执行：

```text
plaintext -> Feistel encrypt -> computed_cipher
computed_cipher -> Feistel decrypt -> decrypted_plaintext
```

若 `computed_cipher == expected_cipher` 且 `decrypted_plaintext == plaintext`，数码管显示：

```text
600D600D
```

否则显示：

```text
BAD0BAD0
```

## 2. Feistel 算法

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

## 3. 数据内存结果区

| 地址 | 内容 |
|---|---|
| `0x180` | plaintext |
| `0x184` | master key |
| `0x188` | expected ciphertext |
| `0x18C` | computed ciphertext |
| `0x190` | decrypted plaintext |
| `0x194` | PASS/FAIL flag |
| `0x198` | K0 |
| `0x19C` | K1 |
| `0x1A0` | K2 |
| `0x1A4` | K3 |

## 4. Vivado 使用说明

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
   - 初始化文件选择 `easy_cry_fixed.coe`
3. 数据 RAM 已在 `dm.v` 中扩展为 256 word：
   - `reg [31:0] RAM[255:0]`
   - `ram_addr = cpu_data_addr[9:2]`
4. 下载 bitstream 后，令 `SW[5:0] = 000000` 查看程序主动输出。
5. 复位后程序自动运行，最终应显示 `600D600D`。

## 5. 文件说明

| 文件 | 说明 |
|---|---|
| `easy_cry_fixed.asm` | 固定向量版汇编源码，含详细注释 |
| `easy_cry_fixed.txt` | 每行一条 32-bit 机器码 |
| `easy_cry_fixed.coe` | Vivado 指令 ROM 初始化文件 |
| `assemble_rv32i.py` | 小型 RV32I 汇编器，可重新生成 txt/coe |
| `*.v/*.sv/*.xdc` | 配套 FPGA 工程文件 |

重新汇编：

```bash
python3 assemble_rv32i.py easy_cry_fixed.asm
```
