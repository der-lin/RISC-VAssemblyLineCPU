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
        end /*else if (DataAdr !== 96) begin
          $display("Simulation failed");
          $stop;
        end*/
      end
    end
endmodule

module top(input  logic        clk, reset, 
           output logic [31:0] WriteData, DataAdr, 
           output logic        MemWrite);

  logic [31:0] PC, Instr, ReadData;
  logic [2:0]      funct3M;
  
  // instantiate processor and memories
  riscvpipeline rv(clk, reset, PC, Instr, MemWrite, DataAdr, 
                    WriteData, ReadData, funct3M);
  // Follow the principle of "Separating computation and storage"
  imem imem(PC, Instr);                                    // instruction memory
  dmem dmem(clk, MemWrite, DataAdr, WriteData, funct3M, ReadData);  // data memory
endmodule

module riscvpipeline(input  logic        clk, reset,
                     output logic [31:0] PC,
                     input  logic [31:0] Instr,
                     output logic        MemWrite,
                     output logic [31:0] DataAdr, WriteData,
                     input  logic [31:0] ReadData,

                     output logic [2:0]  funct3M);

// --- Internal Wires ---

// IF Stage
logic [31:0] PCNextF, PCPlus4F;  // PCTarget is putted in the Exe stage
logic        PCSrcE;

// ID Stage
logic [31:0] PCD, PCPlus4D, InstrD;
logic [1:0]  ResultSrcD;
logic [2:0]  ImmSrcD;
logic        ALUSrcD, RegWriteD, MemWriteD, JumpD, BranchD;
logic [3:0]  ALUControlD;
logic [31:0] ReadData1D, SrcAD, ReadData2D, ImmExtD; //PCTargetD; For now, let's design it in a simple pipeline
logic [1:0]  SrcASrcD; // For auipc and lui, we need to select the source of SrcA, which can be either zero or PC.
logic        JumpRegD; // For jalr, we need to set the JumpReg signal to 1. And the selection use this signal in Exe.

// EXE Stage
logic [31:0] SrcAE, ReadData2E, ImmExtE, PCPlus4E, PCE;
logic [4:0]  rs1E, rs2E, rdE;
logic [1:0]  ResultSrcE;
logic        ALUSrcE, RegWriteE, MemWriteE, JumpE, BranchE;
logic [3:0]  ALUControlE;
logic [31:0] SrcBE, ALUResultE;
logic        ZeroE;
logic [31:0] PCTargetE;    // PCSrc is produced in the Exe Stage
logic        JumpRegE;
logic [31:0] PCImmResultE; // The result of PC + Imm.
logic [2:0]  funct3E;      // For telling B-type instructions in details.
logic        BranchTaken;
logic [31:0] JalrTargetE;  // To align the address.
logic [4:0]  ForwardAE, ForwardBE;
logic [31:0] ForwardSrcAE, ForwardSrcBE;  

// MEM Stage
logic [31:0] ALUResultM, ReadDataM, PCPlus4M, WriteDataM;
logic [4:0]  rdM;
logic [1:0]  ResultSrcM;
logic        RegWriteM, MemWriteM;
//logic [2:0]  funct3M;

// WB Stage
logic [31:0] ALUResultW, ReadDataW, PCPlus4W;
logic [4:0]  rdW;
logic [1:0]  ResultSrcW;
logic        RegWriteW;
logic [31:0] ResultW;
logic [31:0] LReadDataW;  // For load instructions
logic [2:0]  funct3W;     // For telling load instructions in details, such as lb, lh and lw.

// --- Pipeline ---
if_id if_id(clk, reset,
             PC, PCPlus4F, Instr,
             PCD, PCPlus4D, InstrD);

id_exe id_exe(clk, reset,
              ResultSrcD, ALUSrcD, RegWriteD, MemWriteD, JumpD, BranchD,
              ALUControlD,
              SrcAD, ReadData2D, PCD, ImmExtD, PCPlus4D,
              InstrD[19:15], InstrD[24:20], InstrD[11:7],
              JumpRegD,
              InstrD[14:12],

              ResultSrcE, ALUSrcE, RegWriteE, MemWriteE, JumpE, BranchE,
              ALUControlE,
              SrcAE, ReadData2E, PCE, ImmExtE, PCPlus4E,
              rs1E, rs2E, rdE,
              JumpRegE,
              funct3E);

exe_mem exe_mem(clk, reset,
               RegWriteE, MemWriteE,
               ResultSrcE,
               ALUResultE, ForwardSrcBE, PCPlus4E,
               rdE,
               funct3E,

               RegWriteM, MemWriteM,
               ResultSrcM,
               ALUResultM, WriteDataM, PCPlus4M,
               rdM,
               funct3M);

mem_wb mem_wb(clk, reset,
              RegWriteM,
              ResultSrcM,
              ALUResultM, ReadDataM, PCPlus4M,
              rdM,
              funct3M,

              RegWriteW,
              ResultSrcW,
              ALUResultW, ReadDataW, PCPlus4W,
              rdW,
              funct3W);

// --- IF ---
flopr #(32) pcreg(clk, reset, PCNextF, PC);
adder       pcadd4(PC, 32'd4, PCPlus4F);
mux2 #(32)  pcmux(PCPlus4F, PCTargetE, PCSrcE, PCNextF);

// --- ID ---
controller controller(InstrD[6:0], InstrD[14:12], InstrD[30],
                      ResultSrcD, MemWriteD, BranchD, ALUSrcD, RegWriteD, JumpD,
                      ImmSrcD, ALUControlD, SrcASrcD, JumpRegD);
// Watch out the Write-before-Read hazard in the register file, and we can change the writing into signal as negedge clk.
regfile     rf(clk, RegWriteW, InstrD[19:15], InstrD[24:20], 
                 rdW, ResultW, ReadData1D, ReadData2D);
extend      ext(InstrD[31:7], ImmSrcD, ImmExtD);
// For auipc and lui, we need to select the source of SrcA, which can be either zero or PC.
// When SrcASrcD is 00, SrcAD = SrcA; When SrcASrcD is 01, SrcAD = 0; When SrcASrcD is 10, SrcAD = PCD. 
mux3 #(32) srcamux(ReadData1D, 32'b0, PCD, SrcASrcD, SrcAD);

// --- EXE ---
forwarding  forwarding(rs1E, rs2E, rdM, rdW, RegWriteM, RegWriteW,
                       ForwardAE, ForwardBE);
mux3 #(32)  forward_srcamux(SrcAE, ResultW, ALUResultM, ForwardAE, ForwardSrcAE);
mux3 #(32)  forward_srcbmux(ReadData2E, ResultW, ALUResultM, ForwardBE, ForwardSrcBE);

mux2 #(32)  srcbmux(ForwardSrcBE, ImmExtE, ALUSrcE, SrcBE);
alu         alu(ForwardSrcAE, SrcBE, ALUControlE, ALUResultE, ZeroE);

adder       pcbranch(PCE, ImmExtE, PCImmResultE);
assign JalrTargetE = ALUResultE & 32'hfffffffc;
// Mainly for jalr (PC = rs1 + Signed(imm)). Other Branch Jump instructions will use the PCImmResultE as the target address.
mux2 #(32)  pctargetmux(PCImmResultE, JalrTargetE, JumpRegE, PCTargetE);
branch_available branchava(funct3E, ZeroE, ALUResultE[0], BranchTaken);
assign PCSrcE = JumpE | (BranchE & BranchTaken);

// --- MEM ---
// Uniform output to the deme in the top module
assign DataAdr = ALUResultM;
assign WriteData = WriteDataM;
assign MemWrite = MemWriteM;
assign ReadDataM = ReadData; // This is the output of the dmem, and it should be assigned to the ReadDataM which is the input of the mem_wb pipeline register.

// --- WB ---
readdata_load readload(ReadDataW, funct3W, ALUResultW[1:0], LReadDataW);
mux3 #(32) resmux(ALUResultW, LReadDataW, PCPlus4W, ResultSrcW, ResultW);

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
                  output logic [2:0] ImmSrc,
                  output logic [3:0] ALUControl,
                  output logic [1:0] SrcASrc,
                  output logic       JumpReg
);

  logic [1:0] ALUOp;

  // main decoder: parse instruction type.
  maindec md(op, 
             ResultSrc, MemWrite, Branch,
             ALUSrc, RegWrite, Jump, ImmSrc, ALUOp, SrcASrc, JumpReg);

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
               output logic [2:0] ImmSrc,
               output logic [1:0] ALUOp,
               output logic [1:0] SrcASrc,
               output logic       JumpReg);

  logic [14:0] controls;

  assign {RegWrite, ImmSrc, ALUSrc, MemWrite,
          ResultSrc, Branch, ALUOp, Jump, SrcASrc, JumpReg} = controls;

  always_comb
    case(op)
    // RegWrite_ImmSrc_ALUSrc_MemWrite_ResultSrc_Branch_ALUOp_Jump_SrcASrc_JumpReg
      7'b0000011: controls = 15'b1_000_1_0_01_0_00_0_00_0; // lw
      7'b0100011: controls = 15'b0_001_1_1_00_0_00_0_00_0; // sw
      7'b0110011: controls = 15'b1_xxx_0_0_00_0_10_0_00_0; // R-type 
      7'b1100011: controls = 15'b0_010_0_0_00_1_11_0_00_0; // B-type for further telling
      7'b0010011: controls = 15'b1_000_1_0_00_0_10_0_00_0; // I-type ALU
      7'b1101111: controls = 15'b1_011_0_0_10_0_00_1_00_0; // jal
      7'b1100111: controls = 15'b1_000_1_0_10_0_00_1_00_1; // jalr: ImmSrc = 000 -> I-Type, JumpReg = 1
      7'b0110111: controls = 15'b1_100_1_0_00_0_00_0_01_0; // lui: ImmSrc = 100 -> U-Type, SrcASrc = 01 -> zero
      7'b0010111: controls = 15'b1_100_1_0_00_0_00_0_10_0; // auipc: ImmSrc = 100 -> U-Type, SrcASrc = 10 -> PC
      default:    controls = 15'b0_000_0_0_00_0_00_0_00_0;
      //default:    controls = 12'bx_xx_x_x_xx_x_xx_x; // non-implemented instruction
    endcase
endmodule

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
      // R-type or I-type ALU
      2'b10: case(funct3) 
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
      2'b11: case(funct3)
                 3'b000, 3'b001: ALUControl = ALU_SUB; // beq, bne
                 3'b100, 3'b101: ALUControl = ALU_SLT; // blt, bge
                 3'b110, 3'b111: ALUControl = ALU_SLTU; //bltu, bgeu
                 default:        ALUControl = 4'bxxxx;
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
              input  logic [2:0]  immsrc,
              output logic [31:0] immext);
 
  always_comb
    case(immsrc) 
               // I-type 
      3'b000:   immext = {{20{instr[31]}}, instr[31:20]};  
               // S-type (stores)
      3'b001:   immext = {{20{instr[31]}}, instr[31:25], instr[11:7]}; 
               // B-type (branches)
      3'b010:   immext = {{20{instr[31]}}, instr[7], instr[30:25], instr[11:8], 1'b0}; 
               // J-type (jal)
      3'b011:   immext = {{12{instr[31]}}, instr[19:12], instr[20], instr[30:21], 1'b0};
               // U-type (lui, auipc)
      3'b100:   immext = {instr[31:12], 12'b0}; 
      default:  immext = 32'bx; // undefined
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

module alu(input  logic [31:0] a, b,
           input  logic [3:0]  alucontrol,
           output logic [31:0] result,
           output logic        zero);

  logic [31:0] condinvb, sum;
  logic        v;              // overflow
  logic        isAddSub;       // true when is add or subtract operation

  assign condinvb = alucontrol[0] ? ~b : b;
  assign sum = a + condinvb + alucontrol[0];
  assign isAddSub = ~alucontrol[2] & ~alucontrol[1] |
                    ~alucontrol[1] & alucontrol[0];

  always_comb begin  
    case (alucontrol)
      4'b0000:  result = sum;         // add, addi
      4'b0001:  result = sum;         // sub
      4'b0010:  result = a & b;       // and, andi
      4'b0011:  result = a | b;       // or, ori
      4'b0100:  result = a ^ b;       // xor, xori
      4'b0101:  result = ($signed(a) < $signed(b)) ? 32'd1 : 32'd0;       // slt, slti (signed)
      4'b0111:  result = (a < b) ? 32'd1 : 32'd0;       // sltu, sltiu (unsigned) Beacause a and b are declared as logic so that comparing their size will be an unsigned comparison.
      4'b0110:  result = a << b[4:0]; // sll, slli
      4'b1000:  result = a >> b[4:0]; // srl, srli
      4'b1001:  result = $signed(a) >>> b[4:0]; // sra, srai

    endcase
  end

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
              input logic [3:0]  ALUControlD,
              // Data
              input logic [31:0] SrcAD, ReadData2D, PCD, ImmExtD, PCPlus4D,
              // rs1 and rs2 for forwarding
              input logic [4:0]  rs1D, rs2D, rdD,
              input logic        JumpRegD,
              input logic [2:0]  funct3D,
              
              output logic [1:0]  ResultSrcE,
              output logic        ALUSrcE, RegWriteE, MemWriteE, JumpE, BranchE,
              output logic [3:0]  ALUControlE,
              output logic [31:0] SrcAE, ReadData2E, PCE, ImmExtE, PCPlus4E,
              output logic [4:0]  rs1E, rs2E, rdE,
              output logic        JumpRegE,
              output logic [2:0]  funct3E);

  // Control
  flopr #(2)   resultsrc_id_exe(clk, reset, ResultSrcD, ResultSrcE);
  flopr #(1)   alusrc_id_exe(clk, reset, ALUSrcD, ALUSrcE);
  flopr #(1)   regwrite_id_exe(clk, reset, RegWriteD, RegWriteE);
  flopr #(1)   memwrite_id_exe(clk, reset, MemWriteD, MemWriteE);
  flopr #(1)   jump_id_exe(clk, reset, JumpD, JumpE);
  flopr #(1)   branch_id_exe(clk, reset, BranchD, BranchE);
  flopr #(4)   alucontrol_id_exe(clk, reset, ALUControlD, ALUControlE);
  // Data
  flopr #(32) srca_id_exe(clk, reset, SrcAD, SrcAE);
  flopr #(32) readdata2_id_exe(clk, reset, ReadData2D, ReadData2E);
  flopr #(32) pc_id_exe(clk, reset, PCD, PCE);
  flopr #(32) immext_id_exe(clk, reset, ImmExtD, ImmExtE);
  flopr #(32) pcplus4_id_exe(clk, reset, PCPlus4D, PCPlus4E);
  flopr #(5)  rs1_id_exe(clk, reset, rs1D, rs1E);
  flopr #(5)  rs2_id_exe(clk, reset, rs2D, rs2E);
  flopr #(5)  rd_id_exe(clk, reset, rdD, rdE);
  flopr #(1)  jumpreg_id_exe(clk, reset, JumpRegD, JumpRegE);
  flopr #(3)  funct3_id_exe(clk, reset, funct3D, funct3E);

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
               input logic [2:0]  funct3E,

               output logic        RegWriteM, MemWriteM,
               output logic [1:0]  ResultSrcM,
               output logic [31:0] ALUResultM, WriteDataM, PCPlus4M,
               output logic [4:0]  rdM,
               output logic [2:0]  funct3M);

  // Control
  flopr #(1)   regwrite_exe_mem(clk, reset, RegWriteE, RegWriteM);
  flopr #(1)   memwrite_exe_mem(clk, reset, MemWriteE, MemWriteM);
  flopr #(2)   resultsrc_exe_mem(clk, reset, ResultSrcE, ResultSrcM);
  // Data
  flopr #(32) aluresult_exe_mem(clk, reset, ALUResultE, ALUResultM);
  flopr #(32) writedata_exe_mem(clk, reset, WriteDataE, WriteDataM);
  flopr #(32) pcplus4_exe_mem(clk, reset, PCPlus4E, PCPlus4M);
  flopr #(5)  rd_exe_mem(clk, reset, rdE, rdM);

  flopr #(3)  funct3_exe_mem(clk, reset, funct3E, funct3M);

endmodule

// MEM->WB pipeline register 
module mem_wb(input logic      clk, reset,
              // Control Signals
              input logic        RegWriteM,
              input logic [1:0]  ResultSrcM,
              // Data
              input logic [31:0] ALUResultM, ReadDataM, PCPlus4M,
              input logic [4:0]  rdM,

              input logic [2:0]  funct3M,

              output logic        RegWriteW,
              output logic [1:0]  ResultSrcW,
              output logic [31:0] ALUResultW, ReadDataW, PCPlus4W,
              output logic [4:0]  rdW,
              output logic [2:0]  funct3W);

  // Control
  flopr #(1)   regwrite_mem_wb(clk, reset, RegWriteM, RegWriteW);
  flopr #(2)   resultsrc_mem_wb(clk, reset, ResultSrcM, ResultSrcW);
  // Data
  flopr #(32) aluresult_mem_wb(clk, reset, ALUResultM, ALUResultW);
  flopr #(32) readdata_mem_wb(clk, reset, ReadDataM, ReadDataW);
  flopr #(32) pcplus4_mem_wb(clk, reset, PCPlus4M, PCPlus4W);
  flopr #(5)  rd_mem_wb(clk, reset, rdM, rdW);

  flopr #(3)  funct3_mem_wb(clk, reset, funct3M, funct3W);

endmodule

// Further judgment is needed to determine whether jump-condition of B-type instructions is met.
module branch_available (input logic [2:0] funct3,
                         input logic       Zero,
                         input logic       ALUResult0,
                         
                         output logic      BranchTaken);

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

endmodule

// Use addr = rs1 + imm to load data
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

// --- Hazard Unit ---
// Forwarding
module forwarding(input logic [4:0] rs1E, rs2E,
                  input logic [4:0] rdM,
                  input logic [4:0] rdW,
                  input logic       RegWriteM,
                  input logic       RegWriteW,
                  
                  output logic [1:0] ForwardAE,
                  output logic [1:0] ForwardBE);

// ForwardA Logic: For first ALU operand (coming from rs1)
// Priority is given to the MEM stage, as it has the newer data
always_comb begin
    if (RegWriteM && (rdM != 5'b0) && (rdM == rs1E))
        ForwardAE = 2'b10; // Forward from EXE/MEM stage result
    else if (RegWriteW && (rdW != 5'b0) && (rdW == rs1E))
        ForwardAE = 2'b01; // Forward from MEM/WB stage result
    else
        ForwardAE = 2'b00; // No forwarding, use register file value
end

// ForwardB Logic: For second ALU operand (coming from rs2)
always_comb begin
    if (RegWriteM && (rdM != 5'b0) && (rdM == rs2E))
        ForwardBE = 2'b10; 
    else if (RegWriteW && (rdW != 5'b0) && (rdW == rs2E))
        ForwardBE = 2'b01; 
    else
        ForwardBE = 2'b00; 
end

endmodule