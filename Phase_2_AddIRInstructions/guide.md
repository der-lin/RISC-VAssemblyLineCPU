# Phase Two: 添加新指令的指南

你好！本指南将一步步引导你完成 Phase Two 的任务：为你现有的五级流水线 RISC-V 处理器添加 `U-Type`, `I-Type`, 和 `R-Type` 的新指令。

请严格按照以下步骤操作，这将涉及到对数据通路和控制逻辑的修改。

---

### 第 1 步: 扩展控制信号

为了支持新指令的复杂性，我们首先需要扩展几个关键的控制信号。

1.  **扩展 `ALUControl`**:
    *   在 `riscvpipelinefivestage.sv` 文件中，找到 `controller`, `aludec`, `id_exe`, 和 `riscvpipeline` 模块的定义。
    *   将所有 `ALUControl` 信号的宽度从 `[2:0]` 修改为 `[3:0]`。
    *   例如, 在 `controller` 模块中: `output logic [2:0] ALUControl` -> `output logic [3:0] ALUControl`。
    *   确保在 `id_exe` 流水线寄存器中也进行同样的修改。

2.  **扩展 `ImmSrc`**:
    *   在 `controller` 和 `maindec` 模块中，将 `ImmSrc` 信号的宽度从 `[1:0]` 修改为 `[2:0]`。这将帮助我们为 U-Type 指令定义一种新的立即数格式。

3.  **添加 `SrcASrc`**:
    *   为了给 ALU 的第一个操作数提供 PC 寄存器或 0，我们需要一个新的控制信号。
    *   在 `controller` 和 `maindec` 模块中，添加一个新的 `output logic [1:0] SrcASrc` 信号。

---

### 第 2 步: 修改 `extend` 模块

我们需要让 `extend` 模块能够识别和扩展 U-Type 指令的 20 位立即数。

*   在 `extend` 模块中，将 `immsrc` 输入的宽度改为 `[2:0]`。
*   添加一个新的 `case` 来处理 U-Type 立即数。我们将 `3'b100` 分配给 U-Type。
*   U-Type 立即数被扩展为 `imm[31:12]` 在高位，低 12位补 0。

```systemverilog
// extend 模块修改示例
module extend(input  logic [31:7] instr,
              input  logic [2:0]  immsrc, // <--- 宽度改为 3 位
              output logic [31:0] immext);
 
  always_comb
    case(immsrc) 
      // ... (保留 I, S, B-type 的 case)
      2'b00:   immext = {{20{instr[31]}}, instr[31:20]};  
      2'b01:   immext = {{20{instr[31]}}, instr[31:25], instr[11:7]}; 
      2'b10:   immext = {{20{instr[31]}}, instr[7], instr[30:25], instr[11:8], 1'b0};
      // J-type 的编码需要改变
      3'b011:  immext = {{12{instr[31]}}, instr[19:12], instr[20], instr[30:21], 1'b0}; // J-type
      3'b100:  immext = {instr[31:12], 12'b0};                                       // U-type (新)
      default: immext = 32'bx;
    endcase             
endmodule
```
**注意**: 为了给 U-Type 腾出编码空间，我们可能需要调整 J-Type 的 `ImmSrc` 编码，例如从 `2'b11` 改为 `3'b011`。

---

### 第 3 步: 修改 `maindec` 模块

`maindec` 需要解码 `LUI` 和 `AUIPC`，并为它们以及其他指令生成正确的控制信号。

*   更新 `controls` 向量的宽度以包含 3 位的 `ImmSrc` 和 2 位的 `SrcASrc`。
*   为 `LUI` (`7'b0110111`) 和 `AUIPC` (`7'b0010111`) 添加 `case`。
*   为所有指令设置 `SrcASrc`：`LUI` 为 `10` (选择0)，`AUIPC` 为 `01` (选择PC)，其他指令为 `00` (选择寄存器 `rs1`)。

```systemverilog
// maindec 模块修改示例
module maindec(input  logic [6:0] op,
               output logic [1:0] ResultSrc,
               // ... (其他输出)
               output logic [2:0] ImmSrc,    // <--- 宽度改为 3 位
               output logic [1:0] ALUOp,
               output logic [1:0] SrcASrc);  // <--- 新增信号

  logic [12:0] controls; // <--- 调整宽度

  // 定义 SrcASrc 编码
  localparam SRC_RS1 = 2'b00;
  localparam SRC_PC  = 2'b01;
  localparam SRC_ZERO= 2'b10;

  assign {RegWrite, ImmSrc, ALUSrc, MemWrite,
          ResultSrc, Branch, ALUOp, Jump, SrcASrc} = controls;

  always_comb
    case(op)
    // RegWrite_ImmSrc_ALUSrc_MemWrite_ResultSrc_Branch_ALUOp_Jump_SrcASrc
      7'b0110111: controls = 13'b1_100_1_0_00_0_00_0_10; // LUI
      7'b0010111: controls = 13'b1_100_1_0_00_0_00_0_01; // AUIPC
      7'b0000011: controls = 13'b1_000_1_0_01_0_00_0_00; // lw
      7'b0100011: controls = 13'b0_001_1_1_00_0_00_0_00; // sw
      7'b0110011: controls = 13'b1_000_0_0_00_0_10_0_00; // R-type
      7'b1100011: controls = 13'b0_010_0_0_00_1_01_0_00; // beq
      7'b0010011: controls = 13'b1_000_1_0_00_0_10_0_00; // I-type ALU
      7'b1101111: controls = 13'b1_011_0_0_10_0_00_1_00; // jal
      default:    controls = 13'b0; 
    endcase
endmodule
```

---

### 第 4 步: 修改 `aludec` 模块

`aludec` 需要利用扩展后的 4 位 `ALUControl` 来为所有新的 ALU 操作生成唯一的控制码。

```systemverilog
// aludec 模块修改示例
module aludec(input  logic       opb5,
              input  logic [2:0] funct3,
              input  logic       funct7b5, 
              input  logic [1:0] ALUOp,
              output logic [3:0] ALUControl); // <--- 宽度改为 4 位

  // ...
  // 定义新的 ALUControl 编码
  localparam ALU_ADD  = 4'b0000;
  localparam ALU_SUB  = 4'b0001;
  localparam ALU_AND  = 4'b0010;
  localparam ALU_OR   = 4'b0011;
  localparam ALU_XOR  = 4'b0100; // 新
  localparam ALU_SLT  = 4'b0101;
  localparam ALU_SLL  = 4'b0110; // 新
  localparam ALU_SLTU = 4'b0111; // 新
  localparam ALU_SRL  = 4'b1000; // 新
  localparam ALU_SRA  = 4'b1001; // 新

  always_comb
    case(ALUOp)
      2'b00:                ALUControl = ALU_ADD; // for lw, sw, addi, lui, auipc
      2'b01:                ALUControl = ALU_SUB; // for beq
      default: case(funct3) // R-type or I-type ALU
                 3'b000:  if (RtypeSub) ALUControl = ALU_SUB; // sub
                          else          ALUControl = ALU_ADD; // add, addi
                 3'b001:    ALUControl = ALU_SLL;  // sll, slli
                 3'b010:    ALUControl = ALU_SLT;  // slt, slti
                 3'b011:    ALUControl = ALU_SLTU; // sltu, sltiu
                 3'b100:    ALUControl = ALU_XOR;  // xor, xori
                 3'b110:    ALUControl = ALU_OR;   // or, ori
                 3'b111:    ALUControl = ALU_AND;  // and, andi
                 3'b101:  if (funct7b5) ALUControl = ALU_SRA; // sra, srai
                          else          ALUControl = ALU_SRL; // srl, srli
                 default:   ALUControl = 4'bx;
               endcase
    endcase
endmodule
```

---

### 第 5 步: 修改 `alu` 模块

现在 `alu` 必须实现 `XOR`, `SLL`, `SRL`, `SRA` 和 `SLTU` 的运算逻辑。

```systemverilog
// alu 模块修改示例
module alu(input  logic [31:0] a, b,
           input  logic [3:0]  alucontrol, // <--- 宽度改为 4 位
           output logic [31:0] result,
           output logic        zero);
    
    // ...
    // 使用新的 ALUControl 编码
    always_comb
      case (alucontrol)
        4'b0000:  result = sum;          // ADD
        4'b0001:  result = sum;          // SUB
        4'b0010:  result = a & b;        // AND
        4'b0011:  result = a | b;        // OR
        4'b0100:  result = a ^ b;        // XOR (新)
        4'b0101:  result = (a < b) ? 32'd1 : 32'd0; // SLT (有符号)
        4'b0110:  result = a << b[4:0];  // SLL (新)
        4'b0111:  result = (a < b) ? 32'd1 : 32'd0; // SLTU (无符号)
        4'b1000:  result = a >> b[4:0];  // SRL (新, 逻辑)
        4'b1001:  result = signed'(a) >>> b[4:0]; // SRA (新, 算术)
        default: result = 32'bx;
      endcase
    // ...
    // 注意: SLT 和 SLTU 的 Verilog 实现有差异
    // 在 case 语句中，a 和 b 会被当做无符号数进行比较
    // 为了实现有符号比较 SLT，你需要:
    // logic signed [31:0] signed_a = a;
    // logic signed [31:0] signed_b = b;
    // 然后在 SLT 的 case 中使用 (signed_a < signed_b)
endmodule
```
**重要提示**: 在 `alu` 模块中，为了正确实现 `slt` (有符号比较)，你需要将输入操作数转换为有符号类型再进行比较。`sltu` (无符号比较) 可以直接使用 `a < b`。

---

### 第 6 步: 修改 `riscvpipeline` 数据通路

最后，我们将所有修改集成到主数据通路中。

1.  **更新模块实例化**:
    *   在 `riscvpipeline` 模块中，更新 `controller` 的实例化，确保 `ALUControl`, `ImmSrc`, 和 `SrcASrc` 的端口连接正确。
    *   更新 `id_exe` 实例化，传递 4 位的 `ALUControl`。

2.  **添加 `SrcA` 选择逻辑**:
    *   在 ID 阶段，`regfile` 和 `extend` 模块之后，`id_exe` 寄存器之前，添加一个 Mux 用于选择 ALU 的第一个操作数。
    *   这个 Mux 的输入是：从寄存器文件读出的 `SrcAD`，当前的 `PCD`，以及常量 `0`。
    *   选择信号是来自控制器的 `SrcASrcD`。

```systemverilog
// riscvpipeline ID 阶段修改示例

// --- ID ---
// ... (controller, regfile, extend 实例化)

logic [31:0] SrcAD_from_rf; // 来自 regfile 的原始 rd1
logic [31:0] Muxed_SrcAD;   // Mux 的输出

// 重命名 regfile 的输出
regfile     rf(clk, RegWriteW, InstrD[19:15], InstrD[24:20], 
                 rdW, ResultW, SrcAD_from_rf, ReadData2D);

// 新增的 SrcA Mux
mux3 #(32)  srcamux(SrcAD_from_rf, PCD, 32'd0, SrcASrcD, Muxed_SrcAD);

// 将 Mux 的输出连接到 id_exe 寄存器
id_exe id_exe(clk, reset,
              // ...
              Muxed_SrcAD, ReadData2D, PCD, ImmExtD, PCPlus4D,
              // ...
             );
```
**注意**: 你需要相应地在 `riscvpipeline` 模块的内部信号声明区添加 `SrcASrcD`, `SrcAD_from_rf`, `Muxed_SrcAD` 等信号。`SrcASrcD` 来自 `controller`。同时 `mux3` 可能需要你根据自己的实现进行调整。

---

完成以上所有修改后，你的流水线处理器就应该能够支持这些新添加的指令了。祝你成功！
