# 指南：在五级流水线 RISC-V 处理器中处理冒险

本文档旨在指导您如何在 `riscvSolveHazard.sv` 的基础上，为您的五级流水线 RISC-V 处理器添加数据冒险和控制冒险的处理逻辑。

## 1. 数据冒险 (Data Hazards)

当一条指令依赖于仍在流水线中尚未完成的前序指令的结果时，就会发生数据冒险。我们将采用两种主要技术来解决这个问题：**前递（Forwarding）** 和 **停顿/气泡（Stalling/Bubbling）**。

### 1.1. 通过前递解决 EXE-EXE 和 MEM-EXE 冒险

大多数数据冒险可以通过在流水线的后续阶段（执行 `EXE` 或访存 `MEM`）将结果直接前递回 `EXE` 阶段的 ALU 输入端来解决，而无需等待结果被写回到寄存器堆。

**步骤 1: 创建前递单元 (Forwarding Unit)**

这个新模块将决定 ALU 的操作数应该来自寄存器堆还是从 `EXE/MEM` 或 `MEM/WB` 流水线寄存器中前递。

```verilog
// Forwarding Unit
// Determines when to forward data to the ALU inputs
module ForwardingUnit(
    // Inputs from pipeline registers
    input logic [4:0]  rs1E, rs2E, // Source register numbers in EXE stage
    input logic [4:0]  rdM,        // Destination register number in MEM stage
    input logic [4:0]  rdW,        // Destination register number in WB stage
    input logic        RegWriteM,  // RegWrite control signal in MEM stage
    input logic        RegWriteW,  // RegWrite control signal in WB stage

    // Outputs to control forwarding muxes
    output logic [1:0] ForwardA,   // Control for SrcA mux
    output logic [1:0] ForwardB    // Control for SrcB mux
);

    // ForwardA Logic: For first ALU operand (coming from rs1)
    // Priority is given to the MEM stage, as it has the newer data
    always_comb begin
        if (RegWriteM && (rdM != 5'b0) && (rdM == rs1E))
            ForwardA = 2'b01; // Forward from EXE/MEM stage result
        else if (RegWriteW && (rdW != 5'b0) && (rdW == rs1E))
            ForwardA = 2'b10; // Forward from MEM/WB stage result
        else
            ForwardA = 2'b00; // No forwarding, use register file value
    end

    // ForwardB Logic: For second ALU operand (coming from rs2)
    always_comb begin
        if (RegWriteM && (rdM != 5'b0) && (rdM == rs2E))
            ForwardB = 2'b01; // Forward from EXE/MEM stage result
        else if (RegWriteW && (rdW != 5'b0) && (rdW == rs2E))
            ForwardB = 2'b10; // Forward from MEM/WB stage result
        else
            ForwardB = 2'b00; // No forwarding, use register file value
    end

endmodule
```

**步骤 2: 在 EXE 阶段添加前递 MUX**

在 `riscvpipeline` 模块中，我们需要在 ALU 之前添加 MUX（多路选择器），以根据前递单元的信号选择正确的操作数来源。

*   修改 `riscvpipeline` 模块：
    1.  声明 `ForwardA` 和 `ForwardB` 信号。
    2.  实例化 `ForwardingUnit`。
    3.  在 ALU 的输入 `SrcAE` 和 `SrcBE` 之前添加 MUX。

```verilog
// In riscvpipeline module
// --- Add internal wires for forwarding ---
logic [1:0] ForwardA, ForwardB;
logic [31:0] ForwardedSrcA, ForwardedSrcB;

// --- Instantiate ForwardingUnit in EXE stage ---
// It uses inputs from EXE, MEM, and WB stages
ForwardingUnit fwd_unit(
    .rs1E(rs1E), .rs2E(rs2E),
    .rdM(rdM), .RegWriteM(RegWriteM),
    .rdW(rdW), .RegWriteW(RegWriteW),
    .ForwardA(ForwardA),
    .ForwardB(ForwardB)
);

// --- Add Muxes before ALU inputs in EXE Stage ---
// Mux for SrcA
mux3 #(32) forward_mux_a(
    .d0(SrcAE),         // 00: From ID/EXE (regfile)
    .d1(ALUResultM),    // 01: Forward from EXE/MEM
    .d2(ResultW),       // 10: Forward from MEM/WB
    .s(ForwardA),
    .y(ForwardedSrcA)
);

// Mux for SrcB (Note: SrcB can be either ReadData2 or ImmExt)
mux3 #(32) forward_mux_b(
    .d0(ReadData2E),    // 00: From ID/EXE (regfile)
    .d1(ALUResultM),    // 01: Forward from EXE/MEM
    .d2(ResultW),       // 10: Forward from MEM/WB
    .s(ForwardB),
    .y(ForwardedSrcB)
);

// --- Update the ALU and SrcBMux inputs ---
// Note: ReadData2E is what we might forward TO. SrcBE is the final muxed value.
// The forwarding for rs2 should replace ReadData2E before it goes to the SrcB mux.
mux2 #(32)  srcbmux(ForwardedSrcB, ImmExtE, ALUSrcE, SrcBE); // SrcB mux now uses forwarded value
alu         alu(ForwardedSrcA, SrcBE, ALUControlE, ALUResultE, ZeroE); // ALU now uses forwarded value for SrcA
```

### 1.2. 解决加载-使用冒险 (Load-Use Hazard)

当一条 `lw` 指令紧跟着一条使用其加载结果的指令时，前递无法解决问题，因为数据直到 `MEM` 阶段结束时才从内存中读出。此时，下一条指令已经在 `EXE` 阶段，为时已晚。我们需要停顿流水线一个周期。

**步骤 1: 创建冒险检测单元 (Hazard Detection Unit)**

这个单元位于 `ID` 阶段，用于检测是否需要停顿。

```verilog
// Hazard Detection Unit
// Detects load-use hazards and signals a stall
module HazardDetectionUnit(
    // Inputs
    input logic [4:0]  rs1D, rs2D, // Source regs of instruction in ID stage (from InstrD)
    input logic [4:0]  rdE,        // Dest reg of instruction in EXE stage
    input logic [1:0]  ResultSrcE, // To identify if the instruction in EXE is a load

    // Outputs
    output logic Stall,            // Signal to stall the pipeline
    output logic Bubble            // Signal to insert a bubble into ID/EXE
);
    
    // A load-use hazard occurs if the instruction in EXE is a load (lw)
    // and its destination register is one of the source registers
    // of the instruction currently in ID.
    // ResultSrcE is 2'b01 for lw
    logic load_in_exe;
    assign load_in_exe = (ResultSrcE == 2'b01);

    always_comb begin
        if (load_in_exe && ((rdE == rs1D) || (rdE == rs2D))) begin
            Stall = 1'b1;
            Bubble = 1'b1;
        end else begin
            Stall = 1'b0;
            Bubble = 1'b0;
        end
    end

endmodule
```

**步骤 2: 实现停顿逻辑**

当 `Stall` 信号为高时：
1.  PC 寄存器和 `IF/ID` 流水线寄存器暂停写入，保持当前值。
2.  在 `ID/EXE` 流水线寄存器中插入一个“气泡”（即 `nop` 指令的控制信号），这通常通过将所有控制位置零来实现。

*   修改 `riscvpipeline` 模块：

```verilog
// In riscvpipeline module
// --- Add wires for stalling ---
logic Stall, Bubble;

// --- Instantiate HazardDetectionUnit in ID stage ---
HazardDetectionUnit hazard_unit (
    .rs1D(InstrD[19:15]),
    .rs2D(InstrD[24:20]),
    .rdE(rdE),
    .ResultSrcE(ResultSrcE),
    .Stall(Stall),
    .Bubble(Bubble)
);

// --- Modify PC and IF/ID write logic ---
logic PCWrite, IFIDWrite;
assign PCWrite = ~Stall;
assign IFIDWrite = ~Stall;

// You need to modify the flopr instances for PC and IF/ID
// to include a write enable signal.
// Example for a modified flopr:
/*
module flopr_en #(parameter WIDTH = 8)
              (input  logic             clk, reset, en,
               input  logic [WIDTH-1:0] d, 
               output logic [WIDTH-1:0] q);

  always_ff @(posedge clk, posedge reset)
    if (reset) q <= 0;
    else if (en) q <= d;
endmodule
*/
// Then instantiate it like this:
// flopr_en #(32) pcreg(clk, reset, PCWrite, PCNextF, PC);
// And similarly for the three registers inside the if_id module.

// --- Modify ID/EXE pipeline register to insert bubble ---
// The id_exe module needs to be modified. When Bubble is high, it should
// load 0s for its control signal outputs.
// An easy way is to MUX the control signals from the controller with 0 before they enter the id_exe register.
logic RegWriteD_after_stall, MemWriteD_after_stall /* ... and so on for all control signals */;
assign RegWriteD_after_stall = RegWriteD & ~Bubble;
// Pass RegWriteD_after_stall to id_exe instead of RegWriteD.
```

## 2. 控制冒险 (Control Hazards)

当处理器取到一条分支或跳转指令时，它需要时间来计算目标地址和判断分支是否发生，这期间取到的指令可能是错误的。

您的设计在 `EXE` 阶段判断分支，这意味着有两拍（`IF` 和 `ID`）的延迟。如果分支跳转，这两个周期取入的指令需要被“冲刷”（Flush）掉。

**步骤 1: 检测冲刷条件**

`PCSrcE` 信号（在 `EXE` 阶段产生）是理想的冲刷触发器。当 `PCSrcE` 为 1 时，意味着发生了跳转或分支成功，流水线需要冲刷。

**步骤 2: 实现冲刷逻辑**

当 `PCSrcE` 为 1 时，我们需要将 `IF/ID` 寄存器中的指令清空。这相当于将一条 `nop` 指令送入 `ID` 阶段。

*   修改 `if_id` 模块：

```verilog
// In riscvpipeline, generate a flush signal
logic Flush_IF;
assign Flush_IF = PCSrcE; // Flush when a branch is taken or jump occurs

// Modify the if_id module to accept a flush signal
module if_id(input  logic        clk, reset, flush,
             input  logic [31:0] PCF, PCPlus4F, InstrF,
             output logic [31:0] PCD, PCPlus4D, InstrD);

  flopr #(32) pc_if_id(clk, reset, PCF, PCD);
  flopr #(32) pcplus4_if_id(clk, reset, PCPlus4F, PCPlus4D);
  
  // If flush is asserted, load a nop instruction (0x00000013 or just 0)
  always_ff @(posedge clk, posedge reset) begin
    if (reset || flush)
        InstrD <= 32'h00000013; // nop (addi x0, x0, 0)
    else
        InstrD <= InstrF;
  end
endmodule

// In riscvpipeline, instantiate the modified if_id
if_id if_id_inst(clk, reset, Flush_IF,
                 PC, PCPlus4F, Instr,
                 PCD, PCPlus4D, InstrD);
```
**注意**: 一个更简单的冲刷方法是，当 `Flush` 信号有效时，将送入 `ID/EXE` 寄存器的控制信号全部清零，这和上面 `Stall` 机制中的 `Bubble` 效果一样。你可以将 `Flush_IF` 信号也连接到产生 `Bubble` 的逻辑上。

```verilog
// Combined Bubble logic in ID stage
logic StallBubble, FlushBubble;
// StallBubble comes from HazardDetectionUnit
// FlushBubble is PCSrcE from EXE stage
assign FinalBubble = StallBubble | FlushBubble;

// Then use FinalBubble to clear control signals going into ID/EXE register.
```

## 总结

1.  **添加 `ForwardingUnit`** 并在 `EXE` 阶段添加 MUX 来解决大部分数据冒险。
2.  **添加 `HazardDetectionUnit`** 在 `ID` 阶段来检测加载-使用冒险，并通过暂停 PC 和 `IF/ID` 寄存器以及在 `ID/EXE` 中插入气泡来实现流水线停顿。
3.  **利用 `PCSrcE` 信号** 作为冲刷触发器，在分支或跳转发生时清空 `IF/ID` 寄存器（或在 `ID/EXE` 中插入气泡），以解决控制冒险。

这些修改需要您仔细地更新 `riscvpipeline` 模块以及相关的流水线寄存器模块，以确保信号正确连接和逻辑无误。