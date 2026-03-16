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

* 3. During the test, what I need to do is pay attention to `rdW`, `ResultW`, `ALUResultM` and `WriteDataM` (the last two signal and data are necessary for `slt` and `sltu`).

## The Phase Three: Add more I (lb, lh ...) \ J \ B instructions

添加跳转指令: I5={JAL, JALR, BEQ, BNE, BLT, BGE, BLTU, BGEU}	分支跳转指令，8条
添加访存指令: I5={LB, LH, LW, LBU, LHU, SB, SH, SW}          访存指令，8条

### 1. Add more Branch Jump Instructions

Before we start the progree, let's determine the specific meaning of each branch jump instruction.

* `jal`: 1101111 --- -------: jal rd, label (jump and link): PC = JTA   rd = PC(previous) + 4
* `jalr`: 1100111 000 -------: jalr rd, rs1, imm (jump and link register): PC = rs1 + SignExt(imm)   rd = PC(previous) + 4
* `beq`: 1100011 000 -------: beq rs1, rs2, label (branch if =): if (rs1 == rs2), PC = BTA
* `bne`: 1100011 001 -------: bne rs1, rs2, label (branch if !=)
* `blt`: 1100011 100 -------: blt rs1, rs2, label (branch if <)
* `bge`: 1100011 101 -------: bge rs1, rs2, label (branch if >=)
* `bltu`: 1100011 110 -------: bltu rs1, rs2, label (branch if < unsigned)
* `bgeu`: 1100011 111 -------: bgeu rs1, rs2, label (branch if >= unsigned)

* 1. And we are forced to recgnize a fact: when the Branch Jumping happens, the target address to jump to actually is produced from adding between PC and imm (except for the jalr command, it's target-address = rs1 + SignExt(imm)). 
* For this reason, we need to add a new control signal `JumpReg` to the `maindec-module`, which play an essential role on selecting a more suitable `PCTarget` from `ALUResult` and `PCImmResult`.
* So we add a new mux2 into Exe stage:

```systemverilog
7'b1100111: controls = 15'b1_000_1_0_10_0_00_1_00_1; // jalr: ImmSrc = 000 -> I-Type, JumpReg = 1
```
```systemverilog
// Mainly for jalr (PC = rs1 + Signed(imm)). Other Branch Jump instructions will use the PCImmResultE as the target address.
mux2 #(32)  pctargetmux(PCImmResultE, ALUResultE, JumpRegE, PCTargetE);
```
* 2. Now, let's watch the B-type instructions. Based on the machine code above, we can clearly see that their instruction opcodes are all the same. And the operations required by these six instructions can be devided into three groups. It means that the ALUOP given by maindec-module cna't satisfy the computation requirements.
* However, their funct3 codes are different. It's a good way to tell further in aludec-module.
* So we make maindec-module give B-type instructions `ALUOP = 2'b11` and make the further telling in aludec-module. 

```systemverilog
7'b1100011: controls = 15'b0_010_0_0_00_1_11_0_00_0; // B-type for further telling
```
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

* Then based on the jump conditions of each B-type instructions, we can obtain the following code:
```systemverilog
always_comb
  case (funct3)
    3'b000: BranchTaken = Zero;  // beq
    3'b001: BranchTaken = ~Zero; // bne
    3'b100: BranchTaken = ALUResult0; // blt
    3'b101: BranchTaken = ~ALUResult0; // bge
    3'b110: BranchTaken = ALUResult0; // bltu
    3'b111: BranchTaken = ~ALUResult0; // bgeu
    default: BranchTaken = 1'b0;
  endcase
```

* **ATTENTION**
    In our RISC-V pipeline CPU, the address strictly adhere to four-byte alignment, which can also be seem from imem-module (Instruction Memory) :
    ```systemverilog
    module imem(input  logic [31:0] a,
            output logic [31:0] rd);

        logic [31:0] RAM[63:0];

        initial
            $readmemh("sim/riscvtest.txt",RAM);  // add the way sim

        assign rd = RAM[a[31:2]]; // word aligned
    endmodule
    ```

    Therefore, we must perform the `four-byte alignment` to the ALUResult = rs1 + imm from the jalr instruction.
    We can choose the way as follow:
    ```systemverilog
    assign JarlTargetE = ALUResultE & 32'hfffffffc;
    ```

### 2. Add cache instructions

On this step, we are going to expand lw and sw to `lb, lh, lw, lbu, lhu and sb, sh, sw` and let's see the machine code of these cache instructions.

* `lb`: 0000011 000 -------: lb rd, imm(rs1) (load byte): rd = SignExt([Address][7:0])
* `lh`: 0000011 001 -------: lh rd, imm(rs1) (load half): rd = SignExt([Address][15:0])
* `lw`: 0000011 010 -------: lw rd, imm(rs1) (load word): rd = [Address][31:0]
* `lbu`: 0000011 100 -------: lbu rd, imm(rs1) (load byte unsigned): rd = ZeroExt([Address][7:0])
* `lhu`: 0000011 101 -------: lhu rd, imm(rs1) (load half unsigned): rd = ZeroExt([Address][15:0])

* `sb`: 0100011 000 -------: sb rs2, imm(rs1) (store byte): [Address][7:0] = rs2[7:0]
* `sh`: 0100011 001 -------: sh rs2, imm(rs1) (store half): [Address][15:0] = rs2[15:0]
* `sw`: 0100011 010 -------: sw rs2, imm(rs1) (store word): [Address][31:0] = rs2[31:0]

* **Load Instructions**

To implement more Load-Instructions, it's neccessary for us to set different writing data methods based on their `funct3` machine code and represent the setting results using `LReadData`. I choose to make a module `readdata_load` to achieve this goal. The specific implementation code is as follows:
```systemverilog
module readdata_load (input logic [31:0] ReadDataW,
                      input logic [2:0]  funct3W,
                      input logic [1:0]  addr_lsb,

                      output logic [31:0] LReadData);

logic [31:0] shifted_data;

always_comb begin
  shifted_data = ReadDataW >> (addr_lsb * 8);
  case (funct3W)
    3'b000: LReadData = {{24{shifted_data[7]}}, shifted_data[7:0]};   // lb
    3'b001: LReadData = {{16{shifted_data[15]}}, shifted_data[15:0]}; // lh
    3'b010: LReadData = ReadDataW;  // lw
    3'b100: LReadData = {{24{1'b0}}, shifted_data[7:0]};              // lbu
    3'b101: LReadData = {{16{1'b0}}, shifted_data[15:0]};             // lhu
    default: LReadData = ReadDataW;
  endcase
end

endmodule
```

I am sure it's easy for you to understand the input `ReadDataW` and `funct3W`. What about `addr_lsb`?
* In my code, `addr_lsb` reflects `the offset of the address of the data loaded into rd`. ( This CPU uses Little-Endian Order! ) And it's possible for us to use the offset to right_shift `(Signed OR Unsigned)` the data readed in the address ending with 00 in Data Memory to obtain the data that is actually to be loaded.

* **Save Instructions**

For Sava Instructions, we will do different saving based on their funct3 machine code.

* `sb` (3'b000): Because sb means saving byte. For this reason, we use the passed dataadr[1:0] to represent the actual location where we are going to save data. And we should write `wd[7:0]` (WriteData[7:0]) into the location.
* `sh` (3'b001): The instruction of sh will write half-word into the address. Therefore, what we need to do is focusing on the `dataadr[1]` and `wd[15:0]`.
* `sw` (3'b010): This instruction is familiar to you.
```systemverilog
module dmem(input  logic        clk, we,
            input  logic [31:0] dataadr, wd,
            input  logic [2:0]  funct3,
            output logic [31:0] readdata);

  logic [31:0] RAM[63:0];

  assign readdata = RAM[dataadr[31:2]]; // word aligned

  always_ff @(posedge clk) begin
    if (we) begin
      case (funct3)
        3'b000: begin  // sb
          case(dataadr[1:0])
            2'b00: RAM[dataadr[31:2]][7:0]   <= wd[7:0];
            2'b01: RAM[dataadr[31:2]][15:8] <= wd[7:0];
            2'b10: RAM[dataadr[31:2]][23:16] <= wd[7:0];
            2'b11: RAM[dataadr[31:2]][31:24] <= wd[7:0];
          endcase
        end
        3'b001: begin  // sh
          if (dataadr[1]) RAM[dataadr[31:2]][31:16] <= wd[15:0];
          else      RAM[dataadr[31:2]][15:0]  <= wd[15:0];
        end
        3'b010: RAM[dataadr[31:2]] <= wd;  // sw
      endcase
    end
  end
endmodule
```

* In this code, we have to pay attention to the `Four Byte Alligned` principle. The datadr[1:0] represents the offset in the word. And we only need to think about dataadr[31:2] as the address.

## The Phase Four: Deal with the Data Hazard and Control Hazard

用前递技术解决数据冲突
用冒险检测+停顿解决冲突
控制冲突

### The Data Hazard

A data hazard occurs when an instruction tries to read a register that has not yet been written back by a previous instruction.

* **1. Solving Data Hazards with Forwarding**

Some data hazards can be solved by forwarding(also called bypassing) a result from the `Memory` or `Write Back` stage to a dependent instruction in the `Execute` stage. This requires adding multiplexers `in front of the ALU` to select its operands from the register file or the Mem or WB stage.
From my perspective, forwarding is necessary when an instruction in Exe has a source register matching the destination register of an instruction in Mem or WB.To support forwarding, we can add `Hazard Unit` and `two forwarding multiplexers` as the picture in the book named DDCA.
The hazard detection unit receives the two source registers from the instruction in Exe, `Rs1E` and `Rs2E`, and the destination registers from the instructions in Mem and WB, `RdM` and `RdW`. Of course, it also receive the `RegWrite` signals from the Mem and WB stages (RegWriteM and RegWriteW) to know whether the destination register will actually be written (take sw and beq for example, their instructions do not write results to register file and, hence, do not have their results forwarded).
The hazard unit computes control signals for the forwarding multiplexers to choose operands from the register file or from the results in Mem or WB (actually `ALUResultM` or `ResultW`).
And remember that `x0` is hardwired to 0 and should never be forwarded.
What's more, the result from Mem has a priority comparing with that from WB because we need a `recent` data.
All in all, we get the telling-logic for forwarding as follows:
* if      `((Rs1E == RdM) & RegWriteM) & (Rs1E != 0)`, then ForwardAE = 2'b10  // Forward from Mem Stage
* else if `((Rs1E == RdW) & RegWriteW) & (Rs1E != 0)`, then ForwardAE = 2'b01  // Forward from WB Stage
* else                                               , then ForwardAE = 2'b00  // No forwarding

* `the simultaneity of transimmion`: think about instructions:addi x1, x2, x3; sw x1, 0(x4): sw instruction will get the forwarding result from Mem of addi in Exe, and we should pass the result to Mem stage. So, we change `exe_mem(...ReadData2E...)` to `exe_mem(...ForwardSrcBE...)`.

* **2. Solving Data Hazards with Stalls**

Forwarding is sufficient to solve `RAW` data hazards when the result is computed in the Execute stage of an instruction because ist result can be then be forwarded to Exe of the next instruction. Unforunately, the `lw` instruction does not finish reading data until `the end of the Memory stage`, so its result cannot be forwarded to the Exe of the next instruction.
Consider the following instructions:
```assemble
lw  s7, 40(s5)
and s8, s7, t3
```
`To solve the problem that data readed from the end of the cycle will be used in the begining of the current cycle`, we can `stall` the pipeline, holding up operation until the data is available.
Stalls degrade performance, so they should be used only when necessray.
In conclusion, we get the logic to compute the stalls and flushes as follows:
* `loadStall` = `ResultSrcE[0] & ((Rs1D == RdE) | (Rs2D) == RdE)`
* `StallF` = `StallD` = `FlushE` = `loadStall`
`StallF` and `StallD` freeze PCreg and IF->IDreg, respectively. `FlushE` will make the control signals from ID to Exe become `zero` to make sure no registers will get a data. Therefore, with the cooperation of these three signals, the instruction using source register which is the destination regiter of load-instruction and instructions after it will be `stopped`.
```systemverilog
// in riscvpipeline
// IF
//...
flopren #(32) pcreg(clk, reset, ~StallF, PCNextF, PC);
//...
//ID
//...
stalltell  stalltell(InstrD[19:15], InstrD[24:20], rdE, ResultSrcE[0], StallF, StallD, FlushE);
//...

// add en = ~StallD into if_id-module

// add clear = FlushE into id_exe-module

```

### The Control Hazard

A control hazard occurs when the decision of what instruction to fetch next has not been made by the time the fetch takes place.