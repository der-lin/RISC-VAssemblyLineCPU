好的，理解了您的目标。要将现有的单周期CPU改造为五级流水线CPU，核心任务是**切分数据通路**并**插入流水线寄存器**。

这是一个分阶段的详细指南，帮助您完成第一阶段的改造。

### 1. 模块与流水线阶段的对应关系

首先，我们将您 `riscvsingle.sv` 中的模块和逻辑对应到经典的五级流水线（IF, ID, EXE, MEM, WB）中：

*   **IF (Instruction Fetch - 取指)**
    *   `pcreg`: PC寄存器
    *   `pcadd4`: PC+4 加法器
    *   `pcaddbranch`: 分支目标地址加法器
    *   `pcmux`: 下一条PC选择器
    *   `imem`: 指令存储器 (在 `top` 模块中)

*   **ID (Instruction Decode - 译码)**
    *   `regfile`: 寄存器堆（读取 `rs1`, `rs2`）
    *   `extend`: 立即数扩展单元
    *   `controller`: 控制器，生成所有控制信号 (`maindec` 和 `aludec`)

*   **EXE (Execute - 执行)**
    *   `srcbmux`: ALU的B输入选择器
    *   `alu`: 算术逻辑单元

*   **MEM (Memory Access - 访存)**
    *   `dmem`: 数据存储器 (在 `top` 模块中)

*   **WB (Write Back - 写回)**
    *   `resultmux`: 写回寄存器堆的数据选择器
    *   `regfile`: 寄存器堆（写入 `rd`）

### 2. 改造步骤与代码实现

我们将修改 `riscvsingle.sv` 文件，用新的流水线结构代替原有的 `riscvsingle` 模块。

#### 步骤 1: 定义四个流水线寄存器模块

首先，在 `riscvsingle.sv` 文件的末尾（但在 `endmodule` 之外）或开头添加以下四个流水线寄存器模块。它们的作用是在每个时钟周期，将当前阶段的计算结果和控制信号传递给下一个阶段。

```systemverilog
// 1. IF/ID Pipeline Register
module if_id_reg(
    input  logic        clk, reset,
    input  logic [31:0] PCPlus4_if, Instr_if,
    output logic [31:0] PCPlus4_id, Instr_id
);
    flopr #(32) pcplus4_reg(clk, reset, PCPlus4_if, PCPlus4_id);
    flopr #(32) instr_reg(clk, reset, Instr_if, Instr_id);
endmodule

// 2. ID/EXE Pipeline Register
module id_exe_reg(
    input  logic        clk, reset,
    // Control Signals
    input  logic [1:0]  ResultSrc_id,
    input  logic        ALUSrc_id, RegWrite_id, MemWrite_id, Jump_id, Branch_id,
    input  logic [2:0]  ALUControl_id,
    // Data
    input  logic [31:0] SrcA_id, RegData2_id, ImmExt_id, PCPlus4_id,
    input  logic [4:0]  rs1_id, rs2_id, rd_id,

    output logic [1:0]  ResultSrc_exe,
    output logic        ALUSrc_exe, RegWrite_exe, MemWrite_exe, Jump_exe, Branch_exe,
    output logic [2:0]  ALUControl_exe,
    output logic [31:0] SrcA_exe, RegData2_exe, ImmExt_exe, PCPlus4_exe,
    output logic [4:0]  rs1_exe, rs2_exe, rd_exe
);
    // Control
    flopr #(2) resultsrc_reg(clk, reset, ResultSrc_id, ResultSrc_exe);
    flopr #(1) alusrc_reg(clk, reset, ALUSrc_id, ALUSrc_exe);
    flopr #(1) regwrite_reg(clk, reset, RegWrite_id, RegWrite_exe);
    flopr #(1) memwrite_reg(clk, reset, MemWrite_id, MemWrite_exe);
    flopr #(1) jump_reg(clk, reset, Jump_id, Jump_exe);
    flopr #(1) branch_reg(clk, reset, Branch_id, Branch_exe);
    flopr #(3) alucontrol_reg(clk, reset, ALUControl_id, ALUControl_exe);
    // Data
    flopr #(32) srca_reg(clk, reset, SrcA_id, SrcA_exe);
    flopr #(32) regdata2_reg(clk, reset, RegData2_id, RegData2_exe);
    flopr #(32) immext_reg(clk, reset, ImmExt_id, ImmExt_exe);
    flopr #(32) pcplus4_reg(clk, reset, PCPlus4_id, PCPlus4_exe);
    flopr #(5) rs1_reg(clk, reset, rs1_id, rs1_exe);
    flopr #(5) rs2_reg(clk, reset, rs2_id, rs2_exe);
    flopr #(5) rd_reg(clk, reset, rd_id, rd_exe);
endmodule

// 3. EXE/MEM Pipeline Register
module exe_mem_reg(
    input  logic        clk, reset,
    // Control
    input  logic [1:0]  ResultSrc_exe,
    input  logic        RegWrite_exe, MemWrite_exe,
    // Data
    input  logic [31:0] ALUResult_exe, WriteData_exe, PCPlus4_exe,
    input  logic [4:0]  rd_exe,

    output logic [1:0]  ResultSrc_mem,
    output logic        RegWrite_mem, MemWrite_mem,
    output logic [31:0] ALUResult_mem, WriteData_mem, PCPlus4_mem,
    output logic [4:0]  rd_mem
);
    // Control
    flopr #(2) resultsrc_reg(clk, reset, ResultSrc_exe, ResultSrc_mem);
    flopr #(1) regwrite_reg(clk, reset, RegWrite_exe, RegWrite_mem);
    flopr #(1) memwrite_reg(clk, reset, MemWrite_exe, MemWrite_mem);
    // Data
    flopr #(32) aluresult_reg(clk, reset, ALUResult_exe, ALUResult_mem);
    flopr #(32) writedata_reg(clk, reset, WriteData_exe, WriteData_mem);
    flopr #(32) pcplus4_reg(clk, reset, PCPlus4_exe, PCPlus4_mem);
    flopr #(5) rd_reg(clk, reset, rd_exe, rd_mem);
endmodule

// 4. MEM/WB Pipeline Register
module mem_wb_reg(
    input  logic        clk, reset,
    // Control
    input  logic [1:0]  ResultSrc_mem,
    input  logic        RegWrite_mem,
    // Data
    input  logic [31:0] ReadData_mem, ALUResult_mem, PCPlus4_mem,
    input  logic [4:0]  rd_mem,

    output logic [1:0]  ResultSrc_wb,
    output logic        RegWrite_wb,
    output logic [31:0] ReadData_wb, ALUResult_wb, PCPlus4_wb,
    output logic [4:0]  rd_wb
);
    // Control
    flopr #(2) resultsrc_reg(clk, reset, ResultSrc_mem, ResultSrc_wb);
    flopr #(1) regwrite_reg(clk, reset, RegWrite_mem, RegWrite_wb);
    // Data
    flopr #(32) readdata_reg(clk, reset, ReadData_mem, ReadData_wb);
    flopr #(32) aluresult_reg(clk, reset, ALUResult_mem, ALUResult_wb);
    flopr #(32) pcplus4_reg(clk, reset, PCPlus4_mem, PCPlus4_wb);
    flopr #(5) rd_reg(clk, reset, rd_mem, rd_wb);
endmodule
```

#### 步骤 2: 替换 `riscvsingle` 为 `riscvpipeline` 模块

用下面这个全新的 `riscvpipeline` 模块**完全替换**掉文件中旧的 `riscvsingle` 模块。这个新模块内部已经划分好了五个阶段。

```systemverilog
module riscvpipeline(input  logic        clk, reset,
                   output logic [31:0] PC,
                   input  logic [31:0] Instr,
                   output logic        MemWrite,
                   output logic [31:0] ALUResult, WriteData,
                   input  logic [31:0] ReadData);

  // --- Internal Wires ---

  // IF Stage & IF/ID Register
  logic [31:0] PCNext_if, PCPlus4_if, PCTarget_if;
  logic [31:0] PCPlus4_id, Instr_id;
  logic        PCSrc_exe;
  
  // ID Stage & ID/EXE Register
  logic [1:0]  ResultSrc_id, ImmSrc_id, ALUOp_id;
  logic        ALUSrc_id, RegWrite_id, Jump_id, Branch_id;
  logic [2:0]  ALUControl_id;
  logic [31:0] SrcA_id, RegData2_id, ImmExt_id;
  logic [1:0]  ResultSrc_exe;
  logic        ALUSrc_exe, RegWrite_exe, MemWrite_exe, Jump_exe, Branch_exe;
  logic [2:0]  ALUControl_exe;
  logic [31:0] SrcA_exe, RegData2_exe, ImmExt_exe, PCPlus4_exe;
  logic [4:0]  rs1_exe, rs2_exe, rd_exe;

  // EXE Stage & EXE/MEM Register
  logic [31:0] SrcB_exe, ALUResult_exe;
  logic        Zero_exe;
  logic [1:0]  ResultSrc_mem;
  logic        RegWrite_mem, MemWrite_mem;
  logic [31:0] ALUResult_mem, WriteData_mem, PCPlus4_mem;
  logic [4:0]  rd_mem;

  // MEM Stage & MEM/WB Register
  logic [1:0]  ResultSrc_wb;
  logic        RegWrite_wb;
  logic [31:0] ReadData_wb, ALUResult_wb, PCPlus4_wb;
  logic [4:0]  rd_wb;
  
  // WB Stage
  logic [31:0] Result_wb;
  
  // --- Pipeline Registers Instantiation ---
  if_id_reg     ifid_reg(clk, reset, PCPlus4_if, Instr, PCPlus4_id, Instr_id);
  id_exe_reg    idexe_reg(clk, reset, 
                ResultSrc_id, ALUSrc_id, RegWrite_id, MemWrite, Jump_id, Branch_id, ALUControl_id,
                SrcA_id, RegData2_id, ImmExt_id, PCPlus4_id,
                Instr_id[19:15], Instr_id[24:20], Instr_id[11:7],
                ResultSrc_exe, ALUSrc_exe, RegWrite_exe, MemWrite_exe, Jump_exe, Branch_exe, ALUControl_exe,
                SrcA_exe, RegData2_exe, ImmExt_exe, PCPlus4_exe,
                rs1_exe, rs2_exe, rd_exe);
  exe_mem_reg   exemem_reg(clk, reset, 
                ResultSrc_exe, RegWrite_exe, MemWrite_exe,
                ALUResult_exe, RegData2_exe, PCPlus4_exe, rd_exe,
                ResultSrc_mem, RegWrite_mem, MemWrite_mem,
                ALUResult_mem, WriteData_mem, PCPlus4_mem, rd_mem);
  mem_wb_reg    memwb_reg(clk, reset,
                ResultSrc_mem, RegWrite_mem, ReadData, ALUResult_mem, PCPlus4_mem, rd_mem,
                ResultSrc_wb, RegWrite_wb, ReadData_wb, ALUResult_wb, PCPlus4_wb, rd_wb);

  // --- STAGE 1: INSTRUCTION FETCH (IF) ---
  flopr #(32) pcreg(clk, reset, PCNext_if, PC);
  adder       pcadd4(PC, 32'd4, PCPlus4_if);
  adder       pcaddbranch(PC, ImmExt_id, PCTarget_if); // NOTE: Hazard! PC and ImmExt from different stages
  mux2 #(32)  pcmux(PCPlus4_if, PCTarget_if, PCSrc_exe, PCNext_if);

  // --- STAGE 2: INSTRUCTION DECODE (ID) ---
  controller c(Instr_id[6:0], Instr_id[14:12], Instr_id[30], Zero_exe, // NOTE: Hazard! Zero from EXE stage
               ResultSrc_id, MemWrite, PCSrc_exe,
               ALUSrc_id, RegWrite_id, Jump_id, Branch_id,
               ImmSrc_id, ALUControl_id);

  regfile    rf(clk, RegWrite_wb, Instr_id[19:15], Instr_id[24:20], // NOTE: Hazard! Write happens in WB
                rd_wb, Result_wb, SrcA_id, RegData2_id);
  extend     ext(Instr_id[31:7], ImmSrc_id, ImmExt_id);

  // --- STAGE 3: EXECUTE (EXE) ---
  mux2 #(32) srcbmux(RegData2_exe, ImmExt_exe, ALUSrc_exe, SrcB_exe);
  alu        alu(SrcA_exe, SrcB_exe, ALUControl_exe, ALUResult_exe, Zero_exe);
  
  // ALUResult is an output of the top module
  assign ALUResult = ALUResult_exe; 

  // --- STAGE 4: MEMORY (MEM) ---
  // Connect EXE/MEM outputs to top-level outputs for dmem in top.sv
  assign WriteData = WriteData_mem;
  assign MemWrite = MemWrite_mem;
  // The DataAdr for dmem is now ALUResult_mem. Let's adjust top.
  
  // --- STAGE 5: WRITE BACK (WB) ---
  mux3 #(32) resultmux(ALUResult_wb, ReadData_wb, PCPlus4_wb, ResultSrc_wb, Result_wb);
  // Write back to regfile is wired in the ID stage's rf instantiation
endmodule
```

#### 步骤 3: 修改 `top` 模块

由于流水线化后，访存地址来自于 `EXE/MEM` 寄存器，我们需要修改 `top` 模块，将正确的 `ALUResult` 传递给 `dmem`。

将 `top` 模块修改为：
```systemverilog
module top(input  logic        clk, reset, 
           output logic [31:0] WriteData, DataAdr, 
           output logic        MemWrite);

  logic [31:0] PC, Instr, ReadData;
  
  // instantiate processor and memories
  // The old 'riscvsingle' is replaced by 'riscvpipeline'
  riscvpipeline rv(clk, reset, PC, Instr, MemWrite, DataAdr, 
                   WriteData, ReadData);
  imem imem(PC, Instr);                                    // instruction memory
  dmem dmem(clk, MemWrite, DataAdr, WriteData, ReadData);  // data memory
endmodule
```
**注意**: 在 `riscvpipeline` 中，我将 `ALUResult_mem` 作为了 `dmem` 的地址 `DataAdr`。但是顶层模块的 `riscvsingle` 声明没有变。为了让它通过，我将 `riscvpipeline` 的 `ALUResult` 输出连接到了 `DataAdr`，并将 `ALUResult_exe` 连接到了 `ALUResult`。这需要修改 `riscvpipeline` 的接口。

一个更清晰的修改是直接在 `top` 模块里连接正确的信号。我们来修改 `top` 和 `riscvpipeline` 的接口。

**修正后的 `riscvpipeline` 和 `top` 模块：**

```systemverilog
// 替换 riscvpipeline 模块
module riscvpipeline(input  logic        clk, reset,
                   output logic [31:0] PC,
                   input  logic [31:0] Instr,
                   output logic        MemWrite,
                   output logic [31:0] MemAddress, // NEW: Address for dmem
                   output logic [31:0] WriteData,
                   input  logic [31:0] ReadData);

  // ... (模块内部的 wires 和逻辑和上面一样) ...

  // --- STAGE 4: MEMORY (MEM) ---
  assign MemAddress = ALUResult_mem;
  assign WriteData = WriteData_mem;
  assign MemWrite = MemWrite_mem;
  
  // ... (其他阶段逻辑) ...

endmodule

// 替换 top 模块
module top(input  logic        clk, reset, 
           output logic [31:0] WriteData, DataAdr, 
           output logic        MemWrite);

  logic [31:0] PC, Instr, ReadData;
  
  // instantiate processor and memories
  riscvpipeline rv(clk, reset, PC, Instr, MemWrite, DataAdr, 
                   WriteData, ReadData);
  imem imem(PC, Instr);                                    // instruction memory
  dmem dmem(clk, MemWrite, DataAdr, WriteData, ReadData);  // data memory
endmodule

```
将 `riscvsingle` 模块的 `ALUResult` 输出改名为 `MemAddress` 会更清晰地反映其用途。我们上面的代码已经将 `DataAdr` 连接到了 `MemAddress`，所以这是正确的。

### 3. 重要提醒：关于“冒险”(Hazards)

恭喜！通过以上修改，您已经成功将单周期CPU的**硬件结构**拆分为了五级流水线。

**但是，请注意：这个新的CPU还不能正常工作！**

这版设计充满了“冒险”（Hazards），会导致指令执行出错。这正是流水线设计需要解决的核心问题。主要有两类：

1.  **数据冒险 (Data Hazards)**:
    *   **问题**: 一条指令（如 `add`）在WB阶段才会把结果写入寄存器，但紧随其后的指令可能在ID阶段就需要读取这个结果。由于时序错开，后一条指令会读到旧的、错误的数据。
    *   **代码体现**: `regfile` 的写操作 (`RegWrite_wb`, `rd_wb`, `Result_wb`) 来自WB阶段，但读操作 (`Instr_id[19:15]`, `Instr_id[24:20]`) 发生在ID阶段。

2.  **控制冒险 (Control Hazards)**:
    *   **问题**: 分支指令（如 `beq`）在EXE阶段才能判断是否要跳转。但此时，IF和ID阶段已经取了两条错误的指令进入流水线。
    *   **代码体现**: 计算 `PCSrc` 需要 `Zero` 信号，它来自EXE阶段的ALU。但 `PCSrc` 需要在IF阶段就用来选择下一条PC。这个跨阶段的反馈是典型的控制冒险。

要让流水线CPU真正正确工作，下一步（很可能是您课程的Phase Two）就需要引入**转发（Forwarding）**来解决数据冒险，以及**暂停（Stalling）**和**分支预测（Branch Prediction）**来解决控制冒险。

您当前完成的，是搭建流水线CPU框架最关键的第一步。

### 4. 关于修改模块接口的说明

您可能会问，为什么在“修正后的方案”中，我建议修改 `riscvpipeline` 模块的接口（将 `ALUResult` 改为 `MemAddress`）。

答案是：**为了让代码更清晰、准确地反映流水线CPU的工作方式，尤其是在处理内存访问时。**

详细解释如下：

*   **在单周期CPU中**：ALU计算出的结果（`ALUResult`）在**同一个时钟周期内**立刻就被用于内存地址（对应 `dmem` 的 `DataAdr` 输入）。因此，将`ALUResult`直接作为CPU核心的输出给`dmem`是完全正确的。

*   **在流水线CPU中**：情况发生了根本性的变化。
    1.  ALU在 **执行（EXE）** 阶段为 `lw` 或 `sw` 指令计算出内存地址。
    2.  而实际的内存读写发生在 **访存（MEM）** 阶段。
    3.  这意味着，当一条 `lw` 或 `sw` 指令到达MEM阶段时，它需要使用的内存地址，是它在**上一个时钟周期**于EXE阶段计算出的ALU结果。这个结果已经被锁存（Latch）在了 `EXE/MEM` 流水线寄存器中。

因此，在流水线设计中，需要从CPU核心（`riscvpipeline`模块）输出给外部`dmem`的地址，应该是**MEM阶段**正在使用的地址（即来自 `EXE/MEM` 寄存器的 `ALUResult_mem`），而不是**EXE阶段**刚刚算出来的新地址（`ALUResult_exe`）。

将这个输出端口从原来的`ALUResult`改名为`MemAddress`，有以下两个主要好处：

1.  **语义更清晰**：`MemAddress`这个名字直接地、毫无歧义地表明了这个端口的唯一用途——提供给数据存储器（dmem）作为访问地址。这避免了它与ALU在执行阶段计算的、用于算术运算的“结果”相混淆。
2.  **易于理解和调试**：当其他开发者（或者未来的您）阅读顶层模块 `top.sv` 时，看到 `rv.MemAddress` 连接到 `dmem.DataAdr`，就能立刻明白数据流的意图，清晰地知道访存地址是在MEM阶段确定的。这大大降低了因误解信号含义而出错的可能性。

总而言之，这个接口的修改是为了适应流水线设计带来的**时序结构变化**，并通过**更准确的命名**来提升代码的可读性、可维护性和健壮性。这是一个优秀硬件设计的良好实践。