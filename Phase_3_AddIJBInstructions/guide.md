# RISC-V流水线CPU扩展指南：添加分支和访存指令

你好！本指南将引导你如何在现有的五级流水线RISC-V处理器（`riscvaddIRinstructions.sv`）基础上，增加更多的分支指令和访存指令。

我们将实现以下指令：
- **分支跳转指令**: `JALR`, `BNE`, `BLT`, `BGE`, `BLTU`, `BGEU` ( `BEQ` 和 `JAL` 已部分实现)
- **访存指令**: `LB`, `LH`, `LBU`, `LHU`, `SB`, `SH` ( `LW` 和 `SW` 已实现)

我们将遵循模块化的修改思路，逐步更新数据通路（Datapath）和控制器（Controller）。

---

## 准备工作：传递 `funct3`

为了区分新增的同`opcode`指令（例如 `BEQ` 和 `BNE`），我们需要将指令中的 `funct3` 字段（`Instr[14:12]`）传递到后续的流水线阶段。

1.  **向 `id_exe` 流水线寄存器添加 `funct3D` 输入和 `funct3E` 输出:**

    ```systemverilog
    // In id_exe module definition
    module id_exe(
        // ... existing ports
        input logic [2:0] funct3D,
        // ... existing ports
        output logic [2:0] funct3E
    );
    // ...
    flopr #(3) funct3_id_exe(clk, reset, funct3D, funct3E);
    // ...
    endmodule
    ```

2.  **更新 `id_exe` 模块的实例化:**

    ```systemverilog
    // In riscvpipeline module
    id_exe id_exe(
        // ...
        InstrD[14:12], InstrD[24:20], InstrD[11:7], InstrD[14:12], // Add funct3D
        // ...
        rs1E, rs2E, rdE, funct3E // Add funct3E
    );
    ```

3.  **将 `funct3` 传递到 MEM 和 WB 阶段 (为访存指令准备):**

    - 在 `exe_mem` 模块中添加 `funct3E` 输入和 `funct3M` 输出。
    - 在 `mem_wb` 模块中添加 `funct3M` 输入和 `funct3W` 输出。
    - 像 `id_exe` 一样，在模块内添加 `flopr` 寄存器并更新顶层的实例化。

---

## 第一步: 增强分支（Branch）和跳转（Jump）逻辑

当前的设计只处理 `BEQ` 和 `JAL`。我们需要扩展它以支持所有新的分支和跳转指令。

### 1. 更新 `maindec` (主译码器)

`maindec` 需要为新的指令生成正确的控制信号。

- **`JALR` (`op=1100111`)**: 这是一个I-类型的跳转指令。我们需要一个新的控制信号 `JumpReg` 来区分它和 `JAL`。当 `JumpReg=1` 时，跳转地址将来自ALU计算结果(`rs1 + imm`)，而不是PC相对地址。
- **分支指令 (`op=1100011`)**: 所有分支指令（`BEQ`, `BNE` 等）共享同一个 `opcode`。我们将 `ALUOp` 设置为一个新的值 `2'b11`，表示这是一个分支比较操作。具体的比较方式（如相等、小于等）将在 `aludec` 中根据 `funct3` 决定。

**修改 `maindec.sv`:**

```systemverilog
module maindec(input  logic [6:0] op,
               output logic [1:0] ResultSrc,
               output logic       MemWrite,
               output logic       Branch, ALUSrc,
               output logic       RegWrite, Jump,
               output logic [2:0] ImmSrc,
               output logic [1:0] ALUOp,
               output logic [1:0] SrcASrc,
               output logic       JumpReg); // <-- 新增 JumpReg 输出

  logic [14:0] controls; // <-- 宽度增加到 15

  // 增加 JumpReg
  assign {RegWrite, ImmSrc, ALUSrc, MemWrite,
          ResultSrc, Branch, ALUOp, Jump, SrcASrc, JumpReg} = controls;

  always_comb
    case(op)
    // RegWrite_ImmSrc_ALUSrc_MemWrite_ResultSrc_Branch_ALUOp_Jump_SrcASrc_JumpReg
      7'b0000011: controls = 15'b1_000_1_0_01_0_00_0_00_0; // lw
      7'b0100011: controls = 15'b0_001_1_1_00_0_00_0_00_0; // sw
      7'b0110011: controls = 15'b1_xxx_0_0_00_0_10_0_00_0; // R-type 
      7'b1100011: controls = 15'b0_010_0_0_00_1_11_0_00_0; // B-type (ALUOp=11)
      7'b0010011: controls = 15'b1_000_1_0_00_0_10_0_00_0; // I-type ALU
      7'b1101111: controls = 15'b1_011_0_0_10_0_00_1_00_0; // jal
      7'b1100111: controls = 15'b1_000_1_0_10_0_00_1_00_1; // jalr (JumpReg=1)
      7'b0110111: controls = 15'b1_100_1_0_00_0_00_0_01_0; // lui
      7'b0010111: controls = 15'b1_100_1_0_00_0_00_0_10_0; // auipc
      default:    controls = 15'b0_000_0_0_00_0_00_0_00_0;
    endcase
endmodule
```

**相应地，请在 `controller` 模块中也添加 `JumpReg` 输出，并将其连接到 `maindec`。**

### 2. 更新 `aludec` (ALU译码器)

`aludec` 现在需要根据 `ALUOp=11` 和 `funct3` 为分支指令生成正确的 `ALUControl`。

- `BEQ`/`BNE` 需要减法 (`SUB`) 来比较 `rs1` 和 `rs2`。
- `BLT`/`BGE` 需要有符号比较 (`SLT`)。
- `BLTU`/`BGEU` 需要无符号比较 (`SLTU`)。

**修改 `aludec.sv`:**

```systemverilog
module aludec(input  logic       opb5,
              input  logic [2:0] funct3,
              input  logic       funct7b5, 
              input  logic [1:0] ALUOp,
              output logic [3:0] ALUControl);

  // ... (localparam definitions remain the same) ...

  always_comb
    case(ALUOp)
      2'b00:  ALUControl = ALU_ADD; // lw, sw, addi
      2'b01:  ALUControl = ALU_SUB; // beq (Original design)
      // For R-type and I-type ALU instructions
      2'b10: case(funct3)
                 3'b000: ALUControl = RtypeSub ? ALU_SUB : ALU_ADD;
                 3'b010: ALUControl = ALU_SLT;
                 // ... other cases
                 default: ALUControl = 4'bxxxx;
             endcase
      // NEW: For Branch instructions
      2'b11: case(funct3)
                 3'b000, 3'b001: ALUControl = ALU_SUB;  // BEQ, BNE
                 3'b100, 3'b101: ALUControl = ALU_SLT;  // BLT, BGE
                 3'b110, 3'b111: ALUControl = ALU_SLTU; // BLTU, BGEU
                 default: ALUControl = 4'bxxxx;
             endcase
      default: ALUControl = 4'bxxxx;
    endcase
endmodule
```

### 3. 修改EXE阶段的控制逻辑

现在我们需要在EXE阶段根据ALU的输出和指令类型来决定是否进行跳转。

1.  **添加 `JumpReg` 到 `id_exe` 寄存器**，并将其从ID阶段传递到EXE阶段 (`JumpRegE`)。
2.  **修改EXE阶段的跳转地址选择和 `PCSrc` 生成逻辑**。

**在 `riscvpipeline` 模块的EXE阶段进行如下修改:**

```systemverilog
// --- EXE Stage ---

logic [31:0] PCTargetBranchE;
logic BranchTakenE;

// `pcbranch` adder now calculates only the target for B/J-type instructions
adder       pcbranch(PCE, ImmExtE, PCTargetBranchE);

// A new MUX selects the final jump/branch target
// For JALR, target is ALU result (rs1 + imm)
// For JAL/Branch, target is PC-relative
mux2 #(32)  pctargetmux(PCTargetBranchE, ALUResultE, JumpRegE, PCTargetE);

mux2 #(32)  srcbmux(ReadData2E, ImmExtE, ALUSrcE, SrcBE);
alu         alu(SrcAE, SrcBE, ALUControlE, ALUResultE, ZeroE);

// Logic to determine if a branch should be taken
always_comb
  case(funct3E) // We passed funct3 to EXE stage
    3'b000: BranchTakenE = ZeroE;       // BEQ: taken if zero
    3'b001: BranchTakenE = ~ZeroE;      // BNE: taken if not zero
    3'b100: BranchTakenE = ALUResultE[0]; // BLT: taken if slt is true
    3'b101: BranchTakenE = ~ALUResultE[0]; // BGE: taken if slt is false
    3'b110: BranchTakenE = ALUResultE[0]; // BLTU: taken if sltu is true
    3'b111: BranchTakenE = ~ALUResultE[0]; // BGEU: taken if sltu is false
    default: BranchTakenE = 1'b0;
  endcase

// PCSrc is now asserted for any jump, or for a taken branch
assign PCSrcE = JumpE | (BranchE & BranchTakenE);
```

---

## 第二步: 实现新的访存指令

我们将通过修改 `dmem` 模块和在WB（写回）阶段添加数据处理逻辑来实现 `L(B/H/BU/HU)` 和 `S(B/H)`。

### 1. 升级 `dmem` 以支持字节和半字写

当前的 `dmem` 只能进行32位读写。我们需要让它能够根据 `funct3` 信号写入不同大小的数据。我们将内存建模为字节数组。

**修改 `dmem.sv`:**

```systemverilog
module dmem(input  logic        clk, we,
            input  logic [31:0] a, wd,
            input  logic [2:0]  funct3, // <-- 新增 funct3 输入
            output logic [31:0] rd);

  logic [7:0] RAM[255:0]; // 256-byte memory

  initial
      $readmemh("sim/riscvtest.txt", RAM); // 注意: 如果测试文件是为32位内存写的，这里可能需要调整

  // Read Port: 总是读取一个32位的对齐字
  // Little-endian: Addr A, A+1, A+2, A+3
  assign rd = {RAM[{a[31:2], 2'b11}], RAM[{a[31:2], 2'b10}], 
               RAM[{a[31:2], 2'b01}], RAM[{a[31:2], 2'b00}]};

  // Write Port: 根据 funct3 和地址进行字节/半字/字写入
  always_ff @(posedge clk)
    if (we)
      case(funct3)
        3'b000: RAM[a] <= wd[7:0];                               // SB
        3'b001: {RAM[a+1], RAM[a]} <= wd[15:0];                  // SH
        3'b010: {RAM[a+3], RAM[a+2], RAM[a+1], RAM[a]} <= wd; // SW
      endcase
endmodule
```

**别忘了更新 `top` 模块中 `dmem` 的实例化**，将 `MEM` 阶段的 `funct3` 信号 (`funct3M`) 连接到 `dmem`。

### 2. 在WB阶段处理加载数据

`dmem` 总是返回一个32位的字。对于 `LB`, `LBU`, `LH`, `LHU`，我们需要从这个字中提取正确的字节/半字，并进行符号位或零扩展。这个逻辑最适合放在WB阶段，在数据写入寄存器之前完成。

**在 `riscvpipeline` 模块的WB阶段添加以下逻辑:**

```systemverilog
// --- WB Stage ---

logic [31:0] ProcessedReadDataW;
logic [1:0]  addr_lsb_W = ALUResultW[1:0]; // Get address's lower 2 bits

// Data processing logic for loads
always_comb begin
  logic [31:0] shifted_data = ReadDataW >> (addr_lsb_W * 8);
  case(funct3W) // We passed funct3 to WB stage
    3'b000: // LB: Load Byte Signed
      ProcessedReadDataW = {{24{shifted_data[7]}}, shifted_data[7:0]};
    3'b100: // LBU: Load Byte Unsigned
      ProcessedReadDataW = {{24{1'b0}}, shifted_data[7:0]};
    3'b001: // LH: Load Halfword Signed
      ProcessedReadDataW = {{16{shifted_data[15]}}, shifted_data[15:0]};
    3'b101: // LHU: Load Halfword Unsigned
      ProcessedReadDataW = {{16{1'b0}}, shifted_data[15:0]};
    3'b010: // LW: Load Word
      ProcessedReadDataW = ReadDataW;
    default: 
      ProcessedReadDataW = ReadDataW;
  endcase
end

// The final result MUX now needs to select from the processed load data
mux3 #(32) resmux(ALUResultW, ProcessedReadDataW, PCPlus4W, ResultSrcW, ResultW);
```

**注意:** 原来的 `resmux` 输入 `ReadDataW` 被替换为了 `ProcessedReadDataW`。

---

## 总结

完成以上修改后，你的处理器将能够支持所有指定的I5类分支和访存指令。

**后续步骤建议:**
1.  **编写测试用例**: 在 `riscvtest.s` 文件中为所有新指令编写汇编代码测试，以验证你的修改是否正确。
2.  **仿真和调试**: 使用 `modelsim` 或其他仿真工具运行测试，并根据波形图进行调试。
3.  **考虑实现冲突冒险（Hazard）**：目前的设计没有处理数据冒险和控制冒险。例如，一个紧跟在`LW`指令后的`ADD`指令可能会读到旧的寄存器值。这是流水线CPU设计的下一个重要步骤。

祝你编码愉快！
