# Build a five stage pipeline CPU framework

## The Phase One: Building a five-stage pipeline CPU framwork

1. 阅读并理解单周期CPU的代码：建议对照PPT/课本中流水线CPU的框图，对照代码划分出属于IF/ID/EXE/MEM/WB各个阶段的模块。
2. 搭建流水线CPU框架：插入流水级寄存器，将单周期CPU拆分为五个阶段
3. 确保原有指令功能无误：梳理CPU各个阶段的逻辑，确保原单周期CPU里已经实现的指令仍能正常运行

### 1. Modules belonging to each stage of IF / ID / Exe / Mem / WB 

First of all, we make sure Modules belonging to each stage of `IF / ID / EXE / MEM / WB` according to the original code and the picture of a five-stage pipeline CPU framwork. (F / D / E / M / W)

*  **IF (Instruction Fetch)**

    1. A pcmux decided by PCSrcE (produced in Exe): `If PCSrcE = 0`, PCF' (Next PCF) = PCPlus4-F (PCF + 4); `If PCSrcE = 1`, PCF' = PCTargetE (PCE + ImmExtE in Exe).
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
        JumpD (J-Type), BranchD (B-Type), [2:0]ALUControlD, ALUSrcD (Exe)
        [1:0]ImmSrcD (ID)
    3. `Register File` get `rs1` and `rs2` and read out the data which is address or the data will be calculated from the two(?) registers. We call them separately `RD1` and `RD2`. What's more, Register File will receive rd, Result and RegWrite from `WB`: `If RegWrite = 1`, Result will be writed into rd; Else, nothing will happen.
    4. `Extend` receive [1:0]ImmSrcD to determine the type of immediate and perform immediate expansion, then produce ImmExt.

    *  `regfile`: Regiter File (read `rs1` and `rs2`)
    *  `extend`: the Unit extending immediate
    *  `controller`: produce the control signals with the help of maindec and aludec

*  **Exe (Execute)**
    
    1. In `ALU-plusimm`, PCE + ImmExtE = PCTargetE (go to PC selection in IF).
    2. A mux for SrcB, we call it `SrcBmux`. SrcBmux get ALUSrcE (from ID): `If ALUSrcE = 0`, SrcB = RD2E; `If ALUSrcE = 1`, SrcB = ImmExtE.
    3. `ALU` get the signal [2:0]ALUControlE and operate SrcA and SrcB:

    ```systemverilog
    assign condinvb = alucontrol[0] ? ~b : b;
    assign sum = a + condinvb + alucontrol[0];

    always_comb
        case (alucontrol)
            3'b000:  result = sum;         // add
            3'b001:  result = sum;         // subtract
            3'b010:  result = a & b;       // and
            3'b011:  result = a | b;       // or
            3'b100:  result = a ^ b;       // xor
            3'b101:  result = sum[31] ^ v; // slt
            3'b110:  result = a << b[4:0]; // sll
            3'b111:  result = a >> b[4:0]; // srl
            default: result = 32'bx;
        endcase
    ```

    4. `ALU` will produce a signal named `Zero`. Then PCSrcE = JumpE | (ZeroE & BranchE) and it will go to IF as a signal indicating whether a address jump should occur.

    *  `srcbmux`: the SrcB selection
    *  `alu`: the ALU
    *  `pcaddbranch`: branch target address adder

* **Mem(Memory)**

    1. ALUResultM from ALU will enter `Data Memory` or enter the WB stage as the data writed into rd.
    2. In `Data Memory`, the ALUResultM is treated as an address and is raeded out the data (If the address is effective, such as the `lw` order). 
    What's more, Data Memory will get the signal MemWriteM as `WE`, `If WE == 1`, Data Memory will write the data from WriteDataM into the address(provided by ALUResultM) (such as `sw`).

    *  `dmem`: Data Memory(top)

* **WB(Write Back)**

    1. We call the mux selecting the result to write back `resultmux`. It will receive the signal [1:0]ResultSrcW:
    case (ResultSrcW):
        2'b00: choose the ALUResultM as the result write back.
        2'b01: choose the ReadDataW readed out in Data Memory.
        2'b10: choose the PCPlus4W as memory for the situation a fiction end and the program needs to go back to the main code.
    2. Secnd RegWriteW and RdW to Register File.

    *  `reusultmux`: Data selector written back to register file.
    *  `regfile`: Register File (Write the result into rd).