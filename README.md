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

### 2. Change the code and devide the CPU into five stage

* **BASICCHANGE**
* 1. Set the stage1_stage2 modules to reflect the transmission of the signals and data at each stage of the pipeline. Take if_id module for example:
```systemverilog
module if_id(input  logic        clk, reset,
             input  logic [31:0] PCF, PCPlus4F, InstrF,
             output logic [31:0] PCD, PCPlus4D, InstrD);

  flopr #(32) pc_if_id(clk, reset, PCF, PCD);
  flopr #(32) pcplus4_if_id(clk, reset, PCPlus4F, PCPlus4D);
  flopr #(32) instr_if_id(clk, reset, InstrF, InstrD);

endmodule
```
* 2. To satisfy the transmission, I choose to set the necessary `logics` for every stage.

* 3. Give up the original datapath module, and implement its functionality in the riscvpipeline module. The overall design remains unchanged, although some details have been altered. They are as follows:

    1. For the ID stage `rf` module, I choose to write date in the falling edge of the clock (`negedge clk`). And this change is made to resolve the `RAW` hazard (Read After Write).
    * You can imagine the scenarior: the `old instruction` is in `WB` phase, writing the result back to register x1; the `new instruction` is in `ID` phase, reading the data from register x1.You can see that they are operating the same register. 
    * `If we still use the posedge clk in the WB phase, writing result and reading data will happen at the same time.` And the new instruction usually read the old data in ID (not the one we actually need).
    * If we choose the negedge clk for writing back, we can see:
    `0 -> 1 -> 1`: The instruction keeps going along;
    `1 -> 0`: The reasult selected in WB can be writed into register in advance;
    `second half of the cycle (0)`: Because the read operation is combinational logic, it immediately detects changes within the register. Before the next rising edge arrives, the ID stage has already reliably read the newly written value.

    2. Mainly assign values to the Mem stage: 
    ```systemverilog
    assign DataAdr = ALUResultM;
    assign WriteData = WriteDataM;
    assign MemWrite = MemWriteM;
    assign ReadDataM = ReadData;
    ```
    * For the instruction lw (lw rd imm(rs1)) and sw (sw rs2 imm(rs1)), ALUResultM is the address for reading data (lw) or writing data (sw) in the Data Memory. So we have the code: `assign DataAdr = ALUResultM;`
    * The operation of reading data in Data Memory occurs in dmem module and ReadData from dmem is an input for riscvpipeline.

* **CHALLENGE**
* 1. Put the progress computing PCTarget in ID to optimize the pipeline?
* 2. In the regfile module, think about avoiding the data conflicts caused by writing before reading within the same cycle.

* **VECTORY**
* 1. In the progree of Mem in riscvpipeline-module, adding the code:
```systemverilog
assign ReadDataM = ReadData;
```
    make sure data read back from memory can be transferred to write-back stage in the time of running `lw` code, otherwise, register-file will get X and all of the computing-logic will be polluted.

* 2. In the maindec module, I have changed the parsing instructions of the default-case (machine code that can't be recognized by the current code) from `all illegal values x` to `all zero`.

* 3. Change the controller module and put the progress of computing PCSrc in Exe in accord with the classic RISC-V pipeline CPU.

## The Phase Two: Add I\R instructions

添加设置常量指令: I1={LUI, AUIPC}  设置常量指令，2条
添加I-type算术逻辑运算指令: I2={ADDI, SLTI, SLTIU, XORI, ANDI, ALLI, SRLI, SRALI, SRAI} I型指令，9条
添加R-type算术逻辑运算指令: I3={ADD, SUB, SLL, SLT, SLTU, XOR, SRL, SRA, OR, AND} R型指令，10条

### 1. Add lui and auipc

Add a new type of ImmExt: U-type: `imm = {Instr[31:20], 12'b0}`and implement the add-operation of lui and auipc.

* `lui`: lui rd, upim -> rd = {upimm, 12'b0}. (load upper immediate)
* `auipc`: auipc rd, upimm -> rd = {upimm, 12'b0} + PC. (add upper immediate to PC)

* 1. Expand the ImmSrc signals to 3 bits, get [2:0]ImmSrc and ImmExt will choose the U-type when ImmSrc == 3'b100.
* 2. Add a new satic signal `SrcASrc` and add a new selection selecting the `SrcA` within the help of SrcASrc:
    According to the definition for mux3-module, I create three different scenarios for SrcA: (1) `If SrcASrc == 2'b00`, SrcA = ReadData1D = original SrcAD; (2) `If SrcASrc == 2'b01`, SrcA = 32'b0 (for lui); (3) `If SrcASrc == 2'b10`, SrcA = PCD (for auipc).

### 2. Add more instructions of I-type and R-type

Now the aludec-module only decodes a little instructions as follows: 
```systemverilog
  always_comb
    case(ALUOp)
      2'b00:                ALUControl = 3'b000; // addition
      2'b01:                ALUControl = 3'b001; // subtraction
      default: case(funct3) // R-type or I-type ALU
                 3'b000:  if (RtypeSub) 
                            ALUControl = 3'b001; // sub
                          else          
                            ALUControl = 3'b000; // add, addi
                 3'b010:    ALUControl = 3'b101; // slt, slti
                 3'b110:    ALUControl = 3'b011; // or, ori
                 3'b111:    ALUControl = 3'b010; // and, andi
                 default:   ALUControl = 3'bxxx; // ???
               endcase
    endcase
```
And we are going to add instructions as: `sltiu, xori, slli, srli, srai` and  `sll, sltu, xor, sra, srl`

* `slt`: slt rd, rs1: rs2 -> rd = -> (rs1 < rs2). (set less than)
* `sll`: sll rd, rs1, rs2 -> rd = rs1 << rs2(4:0). (shift left logical)
* `sra & srl`: sra rd, rs1, rs2 -> rd = rs1 >>> rs2(4:0).(shift right arithmetic) & srl rd, rs1, rs2 -> rd = rs1 >> rs2(4:0). (shift right logical)

```systemverilog
module aludec(input  logic       opb5,
              input  logic [2:0] funct3,
              input  logic       funct7b5, 
              input  logic [1:0] ALUOp,
              output logic [3:0] ALUControl);

  logic  RtypeSub;
  assign RtypeSub = funct7b5 & opb5;  // TRUE for R-type subtract instruction

  // Define new ALUControls for the new instructions of I-type and R-type.
  localparam ALU_ADD = 4'b0000;
  localparam ALU_SUB = 4'b0001;
  localparam ALU_AND = 4'b0010;
  localparam ALU_OR  = 4'b0011;
  localparam ALU_XOR = 4'b0100;
  localparam ALU_SLT = 4'b0101;
  localparam ALU_SLL = 4'b0110;
  localparam ALU_SLTU = 4'b0111;
  localparam ALU_SRL = 4'b1000;
  localparam ALU_SRA = 4'b1001;

  always_comb
    case(ALUOp)
      2'b00:                ALUControl = ALU_ADD; // addition
      2'b01:                ALUControl = ALU_SUB; // subtraction
      default: case(funct3) // R-type or I-type ALU
                 3'b000:  if (RtypeSub) 
                            ALUControl = ALU_SUB; // sub
                          else          
                            ALUControl = ALU_ADD; // add, addi
                 3'b010:    ALUControl = ALU_SLT; // slt, slti
                 3'b011:    ALUControl = ALU_SLTU; // sltu, sltiu
                 3'b110:    ALUControl = ALU_OR; // or, ori
                 3'b111:    ALUControl = ALU_AND; // and, andi
                 3'b001:    ALUControl = ALU_SLL; // sll, slli
                 3'b100:    ALUControl = ALU_XOR; // xor, xori
                 3'b101:   if (funct7b5) 
                            ALUControl = ALU_SRA; // sra, srai
                          else          
                            ALUControl = ALU_SRL; // srl, srli
                 default:   ALUControl = 4'bxxxx; // ???
               endcase
    endcase
endmodule
```

* 1. A and b are declared as logic so that comparing their size will be an unsigned comparison. Based on this rule, the way we take to implement sll(signed) and sll(unsigned) is:
```systemverilog
      4'b0101:  result = ($signed(a) < $signed(b)) ? 32'd1 : 32'd0;       // slt, slti (signed)
      4'b0111:  result = (a < b) ? 32'd1 : 32'd0;       // sltu, sltiu (unsigned
```
* 2. To distingguish between sra and srl, we can observe the `funct7` of the two kinds of instructions, and find that `sra` is `01000000` and `srl` is `0000000`. Therefore, we can use `funct7b5` (the sixth bit) to determine whether ALUControl signal points to sra or srl.