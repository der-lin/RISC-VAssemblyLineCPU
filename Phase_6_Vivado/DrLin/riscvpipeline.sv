module riscvpipeline(input  logic        clk, reset,
                     output logic [31:0] PC,
                     input  logic [31:0] Instr,
                     output logic        MemWrite,
                     output logic [31:0] DataAdr, WriteData,
                     input  logic [31:0] ReadData,
                     output logic [2:0]  funct3M);

// IF Stage
logic [31:0] PCNextF, PCPlus4F;
logic        PCSrcE;
logic        StallF;

// ID Stage
logic [31:0] PCD, PCPlus4D, InstrD;
logic [1:0]  ResultSrcD;
logic [2:0]  ImmSrcD;
logic        ALUSrcD, RegWriteD, MemWriteD, JumpD, BranchD;
logic [3:0]  ALUControlD;
logic [31:0] ReadData1D, SrcAD, ReadData2D, ImmExtD;
logic [1:0]  SrcASrcD;
logic        JumpRegD;
logic        StallD;
logic        FlushD;

// EXE Stage
logic [31:0] SrcAE, ReadData2E, ImmExtE, PCPlus4E, PCE;
logic [4:0]  rs1E, rs2E, rdE;
logic [1:0]  ResultSrcE;
logic        ALUSrcE, RegWriteE, MemWriteE, JumpE, BranchE;
logic [3:0]  ALUControlE;
logic [31:0] SrcBE, ALUResultE;
logic        ZeroE;
logic [31:0] PCTargetE;
logic        JumpRegE;
logic [31:0] PCImmResultE;
logic [2:0]  funct3E;
logic        BranchTaken;
logic [31:0] JalrTargetE;
logic [1:0]  ForwardAE, ForwardBE;
logic [31:0] ForwardSrcAE, ForwardSrcBE;
logic        FlushE;
logic [1:0]  SrcASrcE;

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
logic [31:0] LReadDataW;
logic [2:0]  funct3W;

if_id if_id(clk, reset, FlushD, ~StallD,
             PC, PCPlus4F, Instr,
             PCD, PCPlus4D, InstrD);

id_exe id_exe(clk, reset, FlushE,
              ResultSrcD, ALUSrcD, RegWriteD, MemWriteD, JumpD, BranchD,
              ALUControlD,
              SrcAD, ReadData2D, PCD, ImmExtD, PCPlus4D,
              InstrD[19:15], InstrD[24:20], InstrD[11:7],
              JumpRegD,
              InstrD[14:12],
              SrcASrcD,
              ResultSrcE, ALUSrcE, RegWriteE, MemWriteE, JumpE, BranchE,
              ALUControlE,
              SrcAE, ReadData2E, PCE, ImmExtE, PCPlus4E,
              rs1E, rs2E, rdE,
              JumpRegE,
              funct3E,
              SrcASrcE);

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

// IF
flopren #(32) pcreg(clk, reset, ~StallF, PCNextF, PC);
adder         pcadd4(PC, 32'd4, PCPlus4F);
mux2 #(32)    pcmux(PCPlus4F, PCTargetE, PCSrcE, PCNextF);

// ID
controller controller(InstrD[6:0], InstrD[14:12], InstrD[30],
                      ResultSrcD, MemWriteD, BranchD, ALUSrcD, RegWriteD, JumpD,
                      ImmSrcD, ALUControlD, SrcASrcD, JumpRegD);
regfile rf(clk, RegWriteW, InstrD[19:15], InstrD[24:20],
           rdW, ResultW, ReadData1D, ReadData2D);
extend ext(InstrD[31:7], ImmSrcD, ImmExtD);
mux3 #(32) srcamux(ReadData1D, 32'b0, PCD, SrcASrcD, SrcAD);
hazardunit hazardunit(InstrD[19:15], InstrD[24:20], rdE, ResultSrcE[0], PCSrcE,
                      StallF, StallD, FlushD, FlushE);

// EXE
forwarding forwarding(rs1E, rs2E, rdM, rdW, RegWriteM, RegWriteW, SrcASrcE,
                      ForwardAE, ForwardBE);
mux3 #(32) forward_srcamux(SrcAE, ResultW, ALUResultM, ForwardAE, ForwardSrcAE);
mux3 #(32) forward_srcbmux(ReadData2E, ResultW, ALUResultM, ForwardBE, ForwardSrcBE);

mux2 #(32) srcbmux(ForwardSrcBE, ImmExtE, ALUSrcE, SrcBE);
alu        alu(ForwardSrcAE, SrcBE, ALUControlE, ALUResultE, ZeroE);

adder       pcbranch(PCE, ImmExtE, PCImmResultE);
assign JalrTargetE = ALUResultE & 32'hfffffffc;
mux2 #(32)  pctargetmux(PCImmResultE, JalrTargetE, JumpRegE, PCTargetE);
branch_available branchava(funct3E, ZeroE, ALUResultE[0], BranchTaken);
assign PCSrcE = JumpE | (BranchE & BranchTaken);

// MEM
assign DataAdr   = ALUResultM;
assign WriteData = WriteDataM;
assign MemWrite  = MemWriteM;
assign ReadDataM = ReadData;

// WB
readdata_load readload(ReadDataW, funct3W, ALUResultW[1:0], LReadDataW);
mux3 #(32) resmux(ALUResultW, LReadDataW, PCPlus4W, ResultSrcW, ResultW);

endmodule

module controller(input  logic [6:0] op,
                  input  logic [2:0] funct3,
                  input  logic       funct7b5,
                  output logic [1:0] ResultSrc,
                  output logic       MemWrite,
                  output logic       Branch, ALUSrc,
                  output logic       RegWrite, Jump,
                  output logic [2:0] ImmSrc,
                  output logic [3:0] ALUControl,
                  output logic [1:0] SrcASrc,
                  output logic       JumpReg);

  logic [1:0] ALUOp;

  maindec md(op,
             ResultSrc, MemWrite, Branch,
             ALUSrc, RegWrite, Jump, ImmSrc, ALUOp, SrcASrc, JumpReg);

  aludec ad(op[5], funct3, funct7b5, ALUOp, ALUControl);
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
      7'b0000011: controls = 15'b1_000_1_0_01_0_00_0_00_0; // lw
      7'b0100011: controls = 15'b0_001_1_1_00_0_00_0_00_0; // sw
      7'b0110011: controls = 15'b1_xxx_0_0_00_0_10_0_00_0; // R-type
      7'b1100011: controls = 15'b0_010_0_0_00_1_11_0_00_0; // B-type
      7'b0010011: controls = 15'b1_000_1_0_00_0_10_0_00_0; // I-type ALU
      7'b1101111: controls = 15'b1_011_0_0_10_0_00_1_00_0; // jal
      7'b1100111: controls = 15'b1_000_1_0_10_0_00_1_00_1; // jalr
      7'b0110111: controls = 15'b1_100_1_0_00_0_00_0_01_0; // lui
      7'b0010111: controls = 15'b1_100_1_0_00_0_00_0_10_0; // auipc
      default:    controls = 15'b0_000_0_0_00_0_00_0_00_0;
    endcase
endmodule

module aludec(input  logic       opb5,
              input  logic [2:0] funct3,
              input  logic       funct7b5,
              input  logic [1:0] ALUOp,
              output logic [3:0] ALUControl);

  logic RtypeSub;
  assign RtypeSub = funct7b5 & opb5;

  localparam ALU_ADD  = 4'b0000;
  localparam ALU_SUB  = 4'b0001;
  localparam ALU_AND  = 4'b0010;
  localparam ALU_OR   = 4'b0011;
  localparam ALU_XOR  = 4'b0100;
  localparam ALU_SLT  = 4'b0101;
  localparam ALU_SLL  = 4'b0110;
  localparam ALU_SLTU = 4'b0111;
  localparam ALU_SRL  = 4'b1000;
  localparam ALU_SRA  = 4'b1001;

  always_comb
    case(ALUOp)
      2'b00: ALUControl = ALU_ADD;
      2'b01: ALUControl = ALU_SUB;
      2'b10: case(funct3)
               3'b000: ALUControl = RtypeSub ? ALU_SUB : ALU_ADD;
               3'b010: ALUControl = ALU_SLT;
               3'b011: ALUControl = ALU_SLTU;
               3'b110: ALUControl = ALU_OR;
               3'b111: ALUControl = ALU_AND;
               3'b001: ALUControl = ALU_SLL;
               3'b100: ALUControl = ALU_XOR;
               3'b101: ALUControl = funct7b5 ? ALU_SRA : ALU_SRL;
               default: ALUControl = 4'bxxxx;
             endcase
      2'b11: case(funct3)
               3'b000, 3'b001: ALUControl = ALU_SUB;
               3'b100, 3'b101: ALUControl = ALU_SLT;
               3'b110, 3'b111: ALUControl = ALU_SLTU;
               default: ALUControl = 4'bxxxx;
             endcase
    endcase
endmodule

module if_id(input  logic        clk, reset, clear, en,
             input  logic [31:0] PCF, PCPlus4F, InstrF,
             output logic [31:0] PCD, PCPlus4D, InstrD);

  floprcen #(32) pc_if_id(clk, reset, clear, en, PCF, PCD);
  floprcen #(32) pcplus4_if_id(clk, reset, clear, en, PCPlus4F, PCPlus4D);

  always_ff @(posedge clk, posedge reset) begin
    if (reset)      InstrD <= 32'h00000013;
    else if (clear) InstrD <= 32'h00000013;
    else if (en)    InstrD <= InstrF;
  end
endmodule

module id_exe(input logic        clk, reset, clear,
              input logic [1:0]  ResultSrcD,
              input logic        ALUSrcD, RegWriteD, MemWriteD, JumpD, BranchD,
              input logic [3:0]  ALUControlD,
              input logic [31:0] SrcAD, ReadData2D, PCD, ImmExtD, PCPlus4D,
              input logic [4:0]  rs1D, rs2D, rdD,
              input logic        JumpRegD,
              input logic [2:0]  funct3D,
              input logic [1:0]  SrcASrcD,
              output logic [1:0]  ResultSrcE,
              output logic        ALUSrcE, RegWriteE, MemWriteE, JumpE, BranchE,
              output logic [3:0]  ALUControlE,
              output logic [31:0] SrcAE, ReadData2E, PCE, ImmExtE, PCPlus4E,
              output logic [4:0]  rs1E, rs2E, rdE,
              output logic        JumpRegE,
              output logic [2:0]  funct3E,
              output logic [1:0]  SrcASrcE);

  floprc #(2) resultsrc_id_exe(clk, reset, clear, ResultSrcD, ResultSrcE);
  floprc #(1) alusrc_id_exe(clk, reset, clear, ALUSrcD, ALUSrcE);
  floprc #(1) regwrite_id_exe(clk, reset, clear, RegWriteD, RegWriteE);
  floprc #(1) memwrite_id_exe(clk, reset, clear, MemWriteD, MemWriteE);
  floprc #(1) jump_id_exe(clk, reset, clear, JumpD, JumpE);
  floprc #(1) branch_id_exe(clk, reset, clear, BranchD, BranchE);
  floprc #(4) alucontrol_id_exe(clk, reset, clear, ALUControlD, ALUControlE);
  floprc #(2) srcasrc_id_exe(clk, reset, clear, SrcASrcD, SrcASrcE);

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

module exe_mem(input logic       clk, reset,
               input logic        RegWriteE, MemWriteE,
               input logic [1:0]  ResultSrcE,
               input logic [31:0] ALUResultE, WriteDataE, PCPlus4E,
               input logic [4:0]  rdE,
               input logic [2:0]  funct3E,
               output logic        RegWriteM, MemWriteM,
               output logic [1:0]  ResultSrcM,
               output logic [31:0] ALUResultM, WriteDataM, PCPlus4M,
               output logic [4:0]  rdM,
               output logic [2:0]  funct3M);

  flopr #(1)  regwrite_exe_mem(clk, reset, RegWriteE, RegWriteM);
  flopr #(1)  memwrite_exe_mem(clk, reset, MemWriteE, MemWriteM);
  flopr #(2)  resultsrc_exe_mem(clk, reset, ResultSrcE, ResultSrcM);
  flopr #(32) aluresult_exe_mem(clk, reset, ALUResultE, ALUResultM);
  flopr #(32) writedata_exe_mem(clk, reset, WriteDataE, WriteDataM);
  flopr #(32) pcplus4_exe_mem(clk, reset, PCPlus4E, PCPlus4M);
  flopr #(5)  rd_exe_mem(clk, reset, rdE, rdM);
  flopr #(3)  funct3_exe_mem(clk, reset, funct3E, funct3M);
endmodule

module mem_wb(input logic      clk, reset,
              input logic        RegWriteM,
              input logic [1:0]  ResultSrcM,
              input logic [31:0] ALUResultM, ReadDataM, PCPlus4M,
              input logic [4:0]  rdM,
              input logic [2:0]  funct3M,
              output logic        RegWriteW,
              output logic [1:0]  ResultSrcW,
              output logic [31:0] ALUResultW, ReadDataW, PCPlus4W,
              output logic [4:0]  rdW,
              output logic [2:0]  funct3W);

  flopr #(1)  regwrite_mem_wb(clk, reset, RegWriteM, RegWriteW);
  flopr #(2)  resultsrc_mem_wb(clk, reset, ResultSrcM, ResultSrcW);
  flopr #(32) aluresult_mem_wb(clk, reset, ALUResultM, ALUResultW);
  flopr #(32) readdata_mem_wb(clk, reset, ReadDataM, ReadDataW);
  flopr #(32) pcplus4_mem_wb(clk, reset, PCPlus4M, PCPlus4W);
  flopr #(5)  rd_mem_wb(clk, reset, rdM, rdW);
  flopr #(3)  funct3_mem_wb(clk, reset, funct3M, funct3W);
endmodule

module branch_available(input logic [2:0] funct3,
                        input logic       Zero,
                        input logic       ALUResult0,
                        output logic      BranchTaken);

always_comb
  case (funct3)
    3'b000: BranchTaken = Zero;
    3'b001: BranchTaken = ~Zero;
    3'b100: BranchTaken = ALUResult0;
    3'b101: BranchTaken = ~ALUResult0;
    3'b110: BranchTaken = ALUResult0;
    3'b111: BranchTaken = ~ALUResult0;
    default: BranchTaken = 1'b0;
  endcase
endmodule

module readdata_load(input logic [31:0] ReadDataW,
                     input logic [2:0]  funct3W,
                     input logic [1:0]  addr_lsb,
                     output logic [31:0] LReadData);

logic [31:0] shifted_data;

always_comb begin
  shifted_data = ReadDataW >> (addr_lsb * 8);
  case (funct3W)
    3'b000: LReadData = {{24{shifted_data[7]}}, shifted_data[7:0]};
    3'b001: LReadData = {{16{shifted_data[15]}}, shifted_data[15:0]};
    3'b010: LReadData = ReadDataW;
    3'b100: LReadData = {{24{1'b0}}, shifted_data[7:0]};
    3'b101: LReadData = {{16{1'b0}}, shifted_data[15:0]};
    default: LReadData = ReadDataW;
  endcase
end
endmodule

module forwarding(input logic [4:0] rs1E, rs2E,
                  input logic [4:0] rdM,
                  input logic [4:0] rdW,
                  input logic       RegWriteM,
                  input logic       RegWriteW,
                  input logic [1:0] SrcASrcE,
                  output logic [1:0] ForwardAE,
                  output logic [1:0] ForwardBE);

always_comb begin
  if ((SrcASrcE == 2'b00) && RegWriteM && (rdM != 5'b0) && (rdM == rs1E))
    ForwardAE = 2'b10;
  else if ((SrcASrcE == 2'b00) && RegWriteW && (rdW != 5'b0) && (rdW == rs1E))
    ForwardAE = 2'b01;
  else
    ForwardAE = 2'b00;
end

always_comb begin
  if (RegWriteM && (rdM != 5'b0) && (rdM == rs2E))
    ForwardBE = 2'b10;
  else if (RegWriteW && (rdW != 5'b0) && (rdW == rs2E))
    ForwardBE = 2'b01;
  else
    ForwardBE = 2'b00;
end
endmodule

module hazardunit(input logic [4:0] rs1D, rs2D,
                  input logic [4:0] rdE,
                  input logic       ResultSrcE0, PCSrcE,
                  output logic      StallF, StallD, FlushD, FlushE);

logic loadStall;
assign loadStall = ResultSrcE0 & (rdE != 5'b0) & ((rs1D == rdE) | (rs2D == rdE));
assign StallF = loadStall;
assign StallD = loadStall;
assign FlushE = loadStall | PCSrcE;
assign FlushD = PCSrcE;
endmodule
