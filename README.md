# Build a five stage pipeline CPU framework

## The Phase One: Building a five-stage pipeline CPU framwork

1. 阅读并理解单周期CPU的代码：建议对照PPT/课本中流水线CPU的框图，对照代码划分出属于IF/ID/EXE/MEM/WB各个阶段的模块。
2. 搭建流水线CPU框架：插入流水级寄存器，将单周期CPU拆分为五个阶段
3. 确保原有指令功能无误：梳理CPU各个阶段的逻辑，确保原单周期CPU里已经实现的指令仍能正常运行

### 1. Modules belonging to each stage of IF / ID / EXE / Mem / WB 

First of all, we make sure Modules belonging to each stage of `IF / ID / EXE / Mem / WB` according to the original code and the picture of a five-stage pipeline CPU framwork. (F / D / E / M / W)

*  **IF (Instruction Fetch)**

    1. A pcmux decided by PCSrcE (produced in EXE): `If PCSrcE = 0`, PCF' (Next PCF) = PCPlus4-F (PCF + 4); `If PCSrcE = 1`, PCF' = PCTargetE (PCE + ImmExtE in EXE).
    2. As the posedge clk, PC was updated to PC'
    3. Then the PCF having already been enter the `Instruction Memory` and `ALU-plus4`:Instruction Memory read out the instruction from PCF; ALU-plus4 make PCF + 4 to prepare for next PCF.

    *  `pcreg`: PC register
    *  `pcadd4`: PC ALU-plis4
    *  `pcmux`: NextPC selector(mux)
    *  `imem`: Instruction Memory(in `top`)

*  **ID (Instruction Decode)**

    1. Devide [31:0]InstrD into 
        [6:0]op / [14:12]funct3 / [30]funct7_5, 
        [19:15]rs1 / [24:20]rs2 / [11:7]rd,
        [31:7]forimmext
    2. Op, funct3, funct7_5 enter `Control Unit` and produce:
        RegWriteD, [1:0]ResultSrcD (WB)
        MemWriteD (for Data Memory) (Mem)
        JumpD (J-Type), BranchD (B-Type), [2:0]ALUControlD, ALUSrcD (EXE)
        [1:0]ImmSrcD (ID)
    3.    
 