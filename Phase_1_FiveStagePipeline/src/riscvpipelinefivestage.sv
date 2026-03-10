// riscvsingle.sv

// RISC-V single-cycle processor
// From Section 7.6 of Digital Design & Computer Architecture
// 27 April 2020
// David_Harris@hmc.edu 
// Sarah.Harris@unlv.edu

// run 210
// Expect simulator to print "Simulation succeeded"
// when the value 25 (0x19) is written to address 100 (0x64)

// Single-cycle implementation of RISC-V (RV32I)
// User-level Instruction Set Architecture V2.2 (May 7, 2017)
// Implements a subset of the base integer instructions:
//    lw, sw
//    add, sub, and, or, slt, 
//    addi, andi, ori, slti
//    beq
//    jal
// Exceptions, traps, and interrupts not implemented
// little-endian memory

// 31 32-bit registers x1-x31, x0 hardwired to 0
// R-Type instructions
//   add, sub, and, or, slt
//   INSTR rd, rs1, rs2
//   Instr[31:25] = funct7 (funct7b5 & opb5 = 1 for sub, 0 for others)
//   Instr[24:20] = rs2
//   Instr[19:15] = rs1
//   Instr[14:12] = funct3
//   Instr[11:7]  = rd
//   Instr[6:0]   = opcode
// I-Type Instructions
//   lw, I-type ALU (addi, andi, ori, slti)
//   lw:         INSTR rd, imm(rs1)
//   I-type ALU: INSTR rd, rs1, imm (12-bit signed)
//   Instr[31:20] = imm[11:0]
//   Instr[24:20] = rs2
//   Instr[19:15] = rs1
//   Instr[14:12] = funct3
//   Instr[11:7]  = rd
//   Instr[6:0]   = opcode
// S-Type Instruction
//   sw rs2, imm(rs1) (store rs2 into address specified by rs1 + immm)
//   Instr[31:25] = imm[11:5] (offset[11:5])
//   Instr[24:20] = rs2 (src)
//   Instr[19:15] = rs1 (base)
//   Instr[14:12] = funct3
//   Instr[11:7]  = imm[4:0]  (offset[4:0])
//   Instr[6:0]   = opcode
// B-Type Instruction
//   beq rs1, rs2, imm (PCTarget = PC + (signed imm x 2))
//   Instr[31:25] = imm[12], imm[10:5]
//   Instr[24:20] = rs2
//   Instr[19:15] = rs1
//   Instr[14:12] = funct3
//   Instr[11:7]  = imm[4:1], imm[11]
//   Instr[6:0]   = opcode
// J-Type Instruction
//   jal rd, imm  (signed imm is multiplied by 2 and added to PC, rd = PC+4)
//   Instr[31:12] = imm[20], imm[10:1], imm[11], imm[19:12]
//   Instr[11:7]  = rd
//   Instr[6:0]   = opcode

//   Instruction  opcode    funct3    funct7
//   add          0110011   000       0000000
//   sub          0110011   000       0100000
//   and          0110011   111       0000000
//   or           0110011   110       0000000
//   slt          0110011   010       0000000
//   addi         0010011   000       immediate
//   andi         0010011   111       immediate
//   ori          0010011   110       immediate
//   slti         0010011   010       immediate
//   beq          1100011   000       immediate
//   lw	          0000011   010       immediate
//   sw           0100011   010       immediate
//   jal          1101111   immediate immediate

module testbench();

  logic        clk;
  logic        reset;

  logic [31:0] WriteData, DataAdr;
  logic        MemWrite;

  // instantiate device to be tested
  top dut(clk, reset, WriteData, DataAdr, MemWrite);
  
  // initialize test
  initial
    begin
      reset <= 1; # 22; reset <= 0;
    end

  // generate clock to sequence tests
  always
    begin
      clk <= 1; # 5; clk <= 0; # 5;
    end

  // check results
  always @(negedge clk)
    begin
      if(MemWrite) begin
        if(DataAdr === 100 & WriteData === 25) begin
          $display("Simulation succeeded");
          $stop;
        end else if (DataAdr !== 96) begin
          $display("Simulation failed");
          $stop;
        end
      end
    end
endmodule

module top(input  logic        clk, reset, 
           output logic [31:0] WriteData, DataAdr, 
           output logic        MemWrite);

  logic [31:0] PC, Instr, ReadData;
  
  // instantiate processor and memories
  riscvpipeline rv(clk, reset, PC, Instr, MemWrite, DataAdr, 
                    WriteData, ReadData);
  // Follow the principle of "Separating computation and storage"
  imem imem(PC, Instr);                                    // instruction memory
  dmem dmem(clk, MemWrite, DataAdr, WriteData, ReadData);  // data memory
endmodule

module riscvpipeline(input  logic        clk, reset,
                     output logic [31:0] PC,
                     input  logic [31:0] Instr,
                     output logic        MemWrite,
                     output logic [31:0] DataAdr, WriteData,
                     input  logic [31:0] ReadData);

// --- Internal Wires ---

// IF Stage
logic [31:0] PCNextF, PCPlus4F;  // PCTarget is putted in the Exe stage
logic        PCSrcE;

// ID Stage
logic [31:0] PCD, PCPlus4D, InstrD;
logic [1:0]  ResultSrcD, ImmSrcD;
logic        ALUSrcD, RegWriteD, MemWriteD, JumpD, BranchD;
logic [2:0]  ALUControlD;
logic [31:0] SrcAD, ReadData2D, ImmExtD; //PCTargetD; For now, let's design it in a simple pipeline

// EXE Stage
logic [31:0] SrcAE, ReadData2E, ImmExtE, PCPlus4E, PCE;
logic [4:0]  rs1E, rs2E, rdE;
logic [1:0]  ResultSrcE;
logic        ALUSrcE, RegWriteE, MemWriteE, JumpE, BranchE;
logic [2:0]  ALUControlE;
logic [31:0] SrcBE, ALUResultE;
logic        ZeroE;
logic [31:0] PCTargetE;    // PCSrc is produced in the Exe Stage

// MEM Stage
logic [31:0] ALUResultM, ReadDataM, PCPlus4M, WriteDataM;
logic [4:0]  rdM;
logic [1:0]  ResultSrcM;
logic        RegWriteM, MemWriteM;

// WB Stage
logic [31:0] ALUResultW, ReadDataW, PCPlus4W;
logic [4:0]  rdW;
logic [1:0]  ResultSrcW;
logic        RegWriteW;
logic [31:0] ResultW;

// --- Pipeline ---
if_id if_id(clk, reset,
             PC, PCPlus4F, Instr,
             PCD, PCPlus4D, InstrD);

id_exe id_exe(clk, reset,
              ResultSrcD, ALUSrcD, RegWriteD, MemWriteD, JumpD, BranchD,
              ALUControlD,
              SrcAD, ReadData2D, PCD, ImmExtD, PCPlus4D,
              InstrD[19:15], InstrD[24:20], InstrD[11:7],

              ResultSrcE, ALUSrcE, RegWriteE, MemWriteE, JumpE, BranchE,
              ALUControlE,
              SrcAE, ReadData2E, PCE, ImmExtE, PCPlus4E,
              rs1E, rs2E, rdE);

exe_mem exe_mem(clk, reset,
               RegWriteE, MemWriteE,
               ResultSrcE,
               ALUResultE, ReadData2E, PCPlus4E,
               rdE,

               RegWriteM, MemWriteM,
               ResultSrcM,
               ALUResultM, WriteDataM, PCPlus4M,
               rdM);

mem_wb mem_wb(clk, reset,
              RegWriteM,
              ResultSrcM,
              ALUResultM, ReadDataM, PCPlus4M,
              rdM,

              RegWriteW,
              ResultSrcW,
              ALUResultW, ReadDataW, PCPlus4W,
              rdW);

// --- IF ---
flopr #(32) pcreg(clk, reset, PCNextF, PC);
adder       pcadd4(PC, 32'd4, PCPlus4F);
mux2 #(32)  pcmux(PCPlus4F, PCTargetE, PCSrcE, PCNextF);

// --- ID ---
controller controller(InstrD[6:0], InstrD[14:12], InstrD[30],
                      ResultSrcD, MemWriteD, BranchD, ALUSrcD, RegWriteD, JumpD,
                      ImmSrcD, ALUControlD);
// Watch out the Write-before-Read hazard in the register file, and we can change the writing into signal as negedge clk.
regfile     rf(clk, RegWriteW, InstrD[19:15], InstrD[24:20], 
                 rdW, ResultW, SrcAD, ReadData2D);
extend      ext(InstrD[31:7], ImmSrcD, ImmExtD);

// --- EXE ---
adder       pcbranch(PCE, ImmExtE, PCTargetE);
mux2 #(32)  srcbmux(ReadData2E, ImmExtE, ALUSrcE, SrcBE);
alu         alu(SrcAE, SrcBE, ALUControlE, ALUResultE, ZeroE);
assign PCSrcE = BranchE & ZeroE | JumpE;

// --- MEM ---
// Uniform output to the deme in the top module
assign DataAdr = ALUResultM;
assign WriteData = WriteDataM;
assign MemWrite = MemWriteM;
assign ReadDataM = ReadData; // This is the output of the dmem, and it should be assigned to the ReadDataM which is the input of the mem_wb pipeline register.

// --- WB ---
mux3 #(32) resmux(ALUResultW, ReadDataW, PCPlus4W, ResultSrcW, ResultW);

endmodule

module controller(input  logic [6:0] op,
                  input  logic [2:0] funct3,
                  input  logic       funct7b5,
                  // remove the Zero input
                  output logic [1:0] ResultSrc,
                  output logic       MemWrite,
                  // Delete PCSrc, and Branch output
                  output logic       Branch, ALUSrc,
                  output logic       RegWrite, Jump,
                  output logic [1:0] ImmSrc,
                  output logic [2:0] ALUControl
);

  logic [1:0] ALUOp;

  // main decoder: parse instruction type.
  maindec md(op, 
             ResultSrc, MemWrite, Branch,
             ALUSrc, RegWrite, Jump, ImmSrc, ALUOp);

  // ALU decoder: generate ALU control signals.
  aludec  ad(op[5], funct3, funct7b5, ALUOp, ALUControl);

  // Delete assign PCSrc = Branch & Zero | Jump;
  // The controller's responsibility is only to generate control signals, and the datapath should be responsible for generating PCSrc. So we can move the logic of PCSrc to the Exe stage, and it will be generated by BranchE, ZeroE, and JumpE.
  // The controller's work ends here, and its sole responsibility is to generate 'static' control signals.
endmodule

module maindec(input  logic [6:0] op,
               output logic [1:0] ResultSrc,
               output logic       MemWrite,
               output logic       Branch, ALUSrc,
               output logic       RegWrite, Jump,
               output logic [1:0] ImmSrc,
               output logic [1:0] ALUOp);

  logic [10:0] controls;

  assign {RegWrite, ImmSrc, ALUSrc, MemWrite,
          ResultSrc, Branch, ALUOp, Jump} = controls;

  always_comb
    case(op)
    // RegWrite_ImmSrc_ALUSrc_MemWrite_ResultSrc_Branch_ALUOp_Jump
      7'b0000011: controls = 11'b1_00_1_0_01_0_00_0; // lw
      7'b0100011: controls = 11'b0_01_1_1_00_0_00_0; // sw
      7'b0110011: controls = 11'b1_xx_0_0_00_0_10_0; // R-type 
      7'b1100011: controls = 11'b0_10_0_0_00_1_01_0; // beq
      7'b0010011: controls = 11'b1_00_1_0_00_0_10_0; // I-type ALU
      7'b1101111: controls = 11'b1_11_0_0_10_0_00_1; // jal
      default:    controls = 11'b0_00_0_0_00_0_00_0; 
      //default:    controls = 11'bx_xx_x_x_xx_x_xx_x; // non-implemented instruction
    endcase
endmodule

module aludec(input  logic       opb5,
              input  logic [2:0] funct3,
              input  logic       funct7b5, 
              input  logic [1:0] ALUOp,
              output logic [2:0] ALUControl);

  logic  RtypeSub;
  assign RtypeSub = funct7b5 & opb5;  // TRUE for R-type subtract instruction

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
endmodule

// 32x32-bit register file with two read ports and one write port
// What amazing!
module regfile(input  logic        clk, 
               input  logic        we3, 
               input  logic [ 4:0] a1, a2, a3, 
               input  logic [31:0] wd3, 
               output logic [31:0] rd1, rd2);

  logic [31:0] rf[31:0];  // register file array

  // three ported register file
  // read two ports combinationally (A1/RD1, A2/RD2)
  // write third port on rising edge of clock (A3/WD3/WE3)
  // register 0 hardwired to 0

  always_ff @(negedge clk)
    if (we3) rf[a3] <= wd3;	

  // Where is the data in the register file?
  assign rd1 = (a1 != 0) ? rf[a1] : 0;
  assign rd2 = (a2 != 0) ? rf[a2] : 0;
endmodule

module adder(input  [31:0] a, b,
             output [31:0] y);

  assign y = a + b;
endmodule

module extend(input  logic [31:7] instr,
              input  logic [1:0]  immsrc,
              output logic [31:0] immext);
 
  always_comb
    case(immsrc) 
               // I-type 
      2'b00:   immext = {{20{instr[31]}}, instr[31:20]};  
               // S-type (stores)
      2'b01:   immext = {{20{instr[31]}}, instr[31:25], instr[11:7]}; 
               // B-type (branches)
      2'b10:   immext = {{20{instr[31]}}, instr[7], instr[30:25], instr[11:8], 1'b0}; 
               // J-type (jal)
      2'b11:   immext = {{12{instr[31]}}, instr[19:12], instr[20], instr[30:21], 1'b0}; 
      default: immext = 32'bx; // undefined
    endcase             
endmodule

module flopr #(parameter WIDTH = 8)
              (input  logic             clk, reset,
               input  logic [WIDTH-1:0] d, 
               output logic [WIDTH-1:0] q);

  always_ff @(posedge clk, posedge reset)
    if (reset) q <= 0;
    else       q <= d;
endmodule

module mux2 #(parameter WIDTH = 8)
             (input  logic [WIDTH-1:0] d0, d1, 
              input  logic             s, 
              output logic [WIDTH-1:0] y);

  assign y = s ? d1 : d0; 
endmodule

module mux3 #(parameter WIDTH = 8)
             (input  logic [WIDTH-1:0] d0, d1, d2,
              input  logic [1:0]       s, 
              output logic [WIDTH-1:0] y);

  assign y = s[1] ? d2 : (s[0] ? d1 : d0); 
endmodule

module imem(input  logic [31:0] a,
            output logic [31:0] rd);

  logic [31:0] RAM[63:0];

  initial
      $readmemh("sim/riscvtest.txt",RAM);  // add the way sim

  assign rd = RAM[a[31:2]]; // word aligned
endmodule

module dmem(input  logic        clk, we,
            input  logic [31:0] a, wd,
            output logic [31:0] rd);

  logic [31:0] RAM[63:0];

  assign rd = RAM[a[31:2]]; // word aligned

  always_ff @(posedge clk)
    if (we) RAM[a[31:2]] <= wd;
endmodule

module alu(input  logic [31:0] a, b,
           input  logic [2:0]  alucontrol,
           output logic [31:0] result,
           output logic        zero);

  logic [31:0] condinvb, sum;
  logic        v;              // overflow
  logic        isAddSub;       // true when is add or subtract operation

  assign condinvb = alucontrol[0] ? ~b : b;
  assign sum = a + condinvb + alucontrol[0];
  assign isAddSub = ~alucontrol[2] & ~alucontrol[1] |
                    ~alucontrol[1] & alucontrol[0];

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

  assign zero = (result == 32'b0);
  assign v = ~(alucontrol[0] ^ a[31] ^ b[31]) & (a[31] ^ sum[31]) & isAddSub;
  
endmodule

// IF->ID pipeline register
module if_id(input  logic        clk, reset,
             input  logic [31:0] PCF, PCPlus4F, InstrF,
             output logic [31:0] PCD, PCPlus4D, InstrD);

  flopr #(32) pc_if_id(clk, reset, PCF, PCD);
  flopr #(32) pcplus4_if_id(clk, reset, PCPlus4F, PCPlus4D);
  flopr #(32) instr_if_id(clk, reset, InstrF, InstrD);

endmodule

// ID->Exe pipeline register
module id_exe(input logic        clk, reset,
              // Control Signals
              input logic [1:0]  ResultSrcD,
              input logic        ALUSrcD, RegWriteD, MemWriteD, JumpD, BranchD,
              input logic [2:0]  ALUControlD,
              // Data
              input logic [31:0] SrcAD, ReadData2D, PCD, ImmExtD, PCPlus4D,
              // rs1 and rs2 for forwarding
              input logic [4:0]  rs1D, rs2D, rdD,
              
              output logic [1:0]  ResultSrcE,
              output logic        ALUSrcE, RegWriteE, MemWriteE, JumpE, BranchE,
              output logic [2:0]  ALUControlE,
              output logic [31:0] SrcAE, ReadData2E, PCE, ImmExtE, PCPlus4E,
              output logic [4:0]  rs1E, rs2E, rdE);

  // Control
  flopr #(2)   resultsrc_id_exe(clk, reset, ResultSrcD, ResultSrcE);
  flopr #(1)   alusrc_id_exe(clk, reset, ALUSrcD, ALUSrcE);
  flopr #(1)   regwrite_id_exe(clk, reset, RegWriteD, RegWriteE);
  flopr #(1)   memwrite_id_exe(clk, reset, MemWriteD, MemWriteE);
  flopr #(1)   jump_id_exe(clk, reset, JumpD, JumpE);
  flopr #(1)   branch_id_exe(clk, reset, BranchD, BranchE);
  flopr #(3)   alucontrol_id_exe(clk, reset, ALUControlD, ALUControlE);
  // Data
  flopr #(32) srca_id_exe(clk, reset, SrcAD, SrcAE);
  flopr #(32) readdata2_id_exe(clk, reset, ReadData2D, ReadData2E);
  flopr #(32) pc_id_exe(clk, reset, PCD, PCE);
  flopr #(32) immext_id_exe(clk, reset, ImmExtD, ImmExtE);
  flopr #(32) pcplus4_id_exe(clk, reset, PCPlus4D, PCPlus4E);
  flopr #(5)  rs1_id_exe(clk, reset, rs1D, rs1E);
  flopr #(5)  rs2_id_exe(clk, reset, rs2D, rs2E);
  flopr #(5)  rd_id_exe(clk, reset, rdD, rdE);

endmodule

// EXE->MEM pipeline register
// PCSrc is produced in the Exe stage
module exe_mem(input logic       clk, reset,
               // Control Signals
               input logic        RegWriteE, MemWriteE,
               input logic [1:0]  ResultSrcE,
               // Data
               input logic [31:0] ALUResultE, WriteDataE, PCPlus4E,
               input logic [4:0]  rdE,

               output logic        RegWriteM, MemWriteM,
               output logic [1:0]  ResultSrcM,
               output logic [31:0] ALUResultM, WriteDataM, PCPlus4M,
               output logic [4:0]  rdM);

  // Control
  flopr #(1)   regwrite_exe_mem(clk, reset, RegWriteE, RegWriteM);
  flopr #(1)   memwrite_exe_mem(clk, reset, MemWriteE, MemWriteM);
  flopr #(2)   resultsrc_exe_mem(clk, reset, ResultSrcE, ResultSrcM);
  // Data
  flopr #(32) aluresult_exe_mem(clk, reset, ALUResultE, ALUResultM);
  flopr #(32) writedata_exe_mem(clk, reset, WriteDataE, WriteDataM);
  flopr #(32) pcplus4_exe_mem(clk, reset, PCPlus4E, PCPlus4M);
  flopr #(5)  rd_exe_mem(clk, reset, rdE, rdM);

endmodule

// MEM->WB pipeline register 
module mem_wb(input logic      clk, reset,
              // Control Signals
              input logic        RegWriteM,
              input logic [1:0]  ResultSrcM,
              // Data
              input logic [31:0] ALUResultM, ReadDataM, PCPlus4M,
              input logic [4:0]  rdM,

              output logic        RegWriteW,
              output logic [1:0]  ResultSrcW,
              output logic [31:0] ALUResultW, ReadDataW, PCPlus4W,
              output logic [4:0]  rdW);

  // Control
  flopr #(1)   regwrite_mem_wb(clk, reset, RegWriteM, RegWriteW);
  flopr #(2)   resultsrc_mem_wb(clk, reset, ResultSrcM, ResultSrcW);
  // Data
  flopr #(32) aluresult_mem_wb(clk, reset, ALUResultM, ALUResultW);
  flopr #(32) readdata_mem_wb(clk, reset, ReadDataM, ReadDataW);
  flopr #(32) pcplus4_mem_wb(clk, reset, PCPlus4M, PCPlus4W);
  flopr #(5)  rd_mem_wb(clk, reset, rdM, rdW);

endmodule