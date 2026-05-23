`timescale 1ns/1ps

module testbench;

  reg clk;
  reg reset;

  integer i;

  // Instancia CPU top
  cpu_top dut (
    .clk(clk),
    .reset(reset)
  );

  initial begin
    clk = 0;
    reset = 1;
    #10;
    reset = 0;
  end

  always #5 clk = ~clk; // clock de 10ns período

  // Monitor de sinais a cada ciclo
  always @(posedge clk) begin
    $display("Instr: %h | imm_out: %d | alu_input2: %d | alu_result: %d",
      dut.instruction,
      dut.immgen_inst.imm_out,
      dut.alu_input2,
      dut.alu_result
    );
  end
  
  // Após algumas instruções, imprime registradores
  initial begin
    #150;

    $display("\nRegistradores (0 a 31):");
    for (i = 0; i < 32; i = i + 1) begin
      $display("reg[%0d] = %d", i, dut.registers_inst.registers[i]);
    end

    $finish;
  end

endmodule