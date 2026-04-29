// data memory
module dm(clk, we, a, addr_lsb, funct3, wd, rd);
  input         clk;
  input         we;
  input  [8:2]  a;
  input  [1:0]  addr_lsb;
  input  [2:0]  funct3;
  input  [31:0] wd;
  output [31:0] rd;

  reg  [31:0] RAM[127:0];
  wire [8:2]  word_addr;
  assign word_addr = a;
  assign rd = RAM[word_addr];

  always @(posedge clk)
    if (we) begin
      case (funct3)
        3'b000: begin
          case (addr_lsb)
            2'b00: RAM[word_addr][7:0]   <= wd[7:0];
            2'b01: RAM[word_addr][15:8]  <= wd[7:0];
            2'b10: RAM[word_addr][23:16] <= wd[7:0];
            2'b11: RAM[word_addr][31:24] <= wd[7:0];
          endcase
        end
        3'b001: begin
          if (addr_lsb[1]) RAM[word_addr][31:16] <= wd[15:0];
          else             RAM[word_addr][15:0]  <= wd[15:0];
        end
        3'b010: RAM[word_addr] <= wd;
        default: ;
      endcase
      $display("M[%03d]\t= 0x%08h", {word_addr, 2'b00}, wd);
    end

endmodule
