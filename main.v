module pc (
  input clk,
  input reset,
  input zero,
  input [31:0] imm_out,
  input branch,
  output reg [31:0] pc_out
);

  wire [31:0] pc_plus_4;
  wire [31:0] pc_branch;
  wire branch_taken;

  assign pc_plus_4 = pc_out + 4;
  assign pc_branch = pc_out + imm_out;
  assign branch_taken = branch & zero;

  always @(posedge clk or posedge reset) begin
    if (reset)
      pc_out <= 0;
    else if (branch_taken)
      pc_out <= pc_branch;
    else
      pc_out <= pc_plus_4;
  end

endmodule

//_______________________________________________

module instruction_memory (
  input  [31:0] pc,
  output [31:0] instruction
);

  reg [31:0] memory [0:255];

  initial begin
    $readmemb("instruction.mem", memory);
  end

  assign instruction = memory[pc[9:2]]; // PC palavra-alinhada (cada instrução 4 bytes)

endmodule

//_______________________________________________

module registers(
    input clk,
    input reset,
    input [4:0] rs1,
    input [4:0] rs2,
    input [4:0] rd,
    input [31:0] write_data,
    input reg_write,
    output [31:0] read_data1,
    output [31:0] read_data2
);
    reg [31:0] registers [31:0];
    integer i;

    // Inicializa os registradores
    initial begin
        for (i = 0; i < 32; i = i + 1)
            registers[i] = 0;
    end

    // Leitura combinacional
    assign read_data1 = (rs1 != 0) ? registers[rs1] : 32'b0;
    assign read_data2 = (rs2 != 0) ? registers[rs2] : 32'b0;

    // Escrita síncrona
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            for (i = 0; i < 32; i = i + 1)
                registers[i] <= 0;
        end else if (reg_write && (rd != 0)) begin
            registers[rd] <= write_data;
        end
    end
endmodule

//_______________________________________________

module imm_gen (
    input  [31:0] instr,
    output reg [31:0] imm_out
);

    wire [6:0] opcode = instr[6:0];
    reg [11:0] imm_s;
    reg [12:0] imm_b;

    always @(*) begin
        case (opcode)
            7'b0000011,  // Tipo I: lb
            7'b0010011:  // Tipo I: ori
                imm_out = {{20{instr[31]}}, instr[31:20]}; // sinal estendido

            7'b0100011: begin  // Tipo S: sb
                imm_s = {instr[31:25], instr[11:7]};
                imm_out = {{20{imm_s[11]}}, imm_s};
            end

            7'b1100011: begin  // Tipo B: beq
                imm_b = {instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
                imm_out = {{19{imm_b[12]}}, imm_b};
            end

            7'b0110011:  // Tipo R: sub, and, srl
                imm_out = 32'b0;  // sem imediato

            default:
                imm_out = 32'b0;
        endcase
    end

endmodule

//_______________________________________________

module control (
    input  [6:0] opcode,
    output reg reg_write,
    output reg alu_src,
    output reg mem_to_reg,
    output reg mem_read,
    output reg mem_write,
    output reg branch,
    output reg [1:0] alu_op
);

    always @(*) begin
        // Inicializa todos os sinais com valores padrão para evitar latches
        reg_write   = 0;
        alu_src     = 0;
        mem_to_reg  = 0;
        mem_read    = 0;
        mem_write   = 0;
        branch      = 0;
        alu_op      = 2'b00;

        case (opcode)
            7'b0000011: begin // LB 
                reg_write   = 1;  // Habilita escrita no registrador
                alu_src     = 1;  // ALU recebe imediato (offset)
                mem_to_reg  = 1;  // Dados vêm da memória
                mem_read    = 1;  // Memória em modo leitura
                mem_write   = 0;
                branch      = 0;
                alu_op      = 2'b00; // ALU faz ADD para calcular endereço
            end
            7'b0100011: begin // SB 
                reg_write   = 0;
                alu_src     = 1;  // Imediato para offset
                mem_to_reg  = 0;
                mem_read    = 0;
                mem_write   = 1;  // Memória em modo escrita
                branch      = 0;
                alu_op      = 2'b00; // ALU faz ADD para calcular endereço
            end
            7'b1100011: begin // BEQ (Branch if Equal)
                reg_write   = 0;
                alu_src     = 0;  // Segundo operando vem do registrador
                mem_to_reg  = 0;
                mem_read    = 0;
                mem_write   = 0;
                branch      = 1;  // Ativa desvio condicional
                alu_op      = 2'b01; // ALU faz SUB para comparação
            end
            7'b0110011: begin // R-type (SUB, AND, SRL)
                reg_write   = 1;  // Habilita escrita no registrador
                alu_src     = 0;  // Segundo operando é registrador
                mem_to_reg  = 0;  // Resultado da ALU vai para o registrador
                mem_read    = 0;
                mem_write   = 0;
                branch      = 0;
                alu_op      = 2'b10; // ALU control depende de funct3/funct7
            end
            7'b0010011: begin // I-type (ANDI, ORI , SRLI)
                reg_write   = 1;  // Habilita escrita no registrador
                alu_src     = 1;  // Segundo operando é imediato
                mem_to_reg  = 0;
                mem_read    = 0;
                mem_write   = 0;
                branch      = 0;
                alu_op      = 2'b11; // ALU control para instruções com imediato
            end
            default: begin
                // Sinais desativados para opcodes não reconhecidos
                reg_write   = 0;
                alu_src     = 0;
                mem_to_reg  = 0;
                mem_read    = 0;
                mem_write   = 0;
                branch      = 0;
                alu_op      = 2'b00;
            end
        endcase
    end

endmodule

//_______________________________________________

module MuxAluSrc (
    input wire [31:0] reg_data2,
    input wire [31:0] imm_out,
    input wire alu_src,
    output reg [31:0] alu_input2
);

    always @(*) begin
        if (alu_src)
            alu_input2 = imm_out;
        else
            alu_input2 = reg_data2;
    end

endmodule

//_______________________________________________

module alu_control (
    input [1:0] alu_op,
    input [2:0] funct3,
    input [6:0] funct7,
    output reg [3:0] alu_ctrl
);
    always @(*) begin
        case (alu_op)
            2'b00: alu_ctrl = 4'b0010; // Load/Store: ADD
            2'b01: alu_ctrl = 4'b0110; // BEQ: SUB
            2'b10: begin // R-type
                case ({funct7, funct3})
                    10'b0000000000: alu_ctrl = 4'b0010; // ADD
                    10'b0100000000: alu_ctrl = 4'b0110; // SUB
                    10'b0000000110: alu_ctrl = 4'b0001; // OR (extra)
                    10'b0000000101: alu_ctrl = 4'b0011; // SRL
                    10'b0000000111: alu_ctrl = 4'b0000; // AND
                    default:        alu_ctrl = 4'b0000; // Default: AND
                endcase
            end
            2'b11: begin // I-type
                case (funct3)
                    3'b000: alu_ctrl = 4'b0010; // ADDI
                    3'b110: alu_ctrl = 4'b0001; // ORI

                    3'b101: begin
                        if (funct7 == 7'b0000000)
                            alu_ctrl = 4'b0011; // SRLI
                        else
                            alu_ctrl = 4'b0000;
                    end
                    default: alu_ctrl = 4'b0000;
                endcase
            end
            default: alu_ctrl = 4'b0000;
        endcase
    end
endmodule

//_________________________________________________

module alu (
    input [31:0] a, b,
    input [3:0] alu_control,
    output reg [31:0] result,
    output zero
);
    always @(*) begin
        case (alu_control)
            4'b0000: result = a & b;       // AND 
            4'b0001: result = a | b;       // OR
            4'b0010: result = a + b;       // ADD (LB/SB/ADDI)
            4'b0110: result = a - b;       // SUB / BEQ
            4'b0011: result = a >> b[4:0]; // SRL
            default: result = 0;
        endcase

        
    end

    assign zero = (result == 0); // Para instruções como BEQ
endmodule

//_________________________________________________

module data_memory(
  input clk,
  input [7:0] addr,
  input [31:0] write_data,
  input memWrite,
  input memRead,
  output reg [31:0] read_data
);

  reg [7:0] memory [0:255];
  integer i;

  initial begin
    for(i = 0; i < 256; i = i + 1)
      memory[i] = 8'b0;
  end

  // SB
  always @(posedge clk) begin
    if(memWrite)
      memory[addr] <= write_data[7:0];
  end

  // LB
  always @(*) begin
    if(memRead)
      read_data = {{24{memory[addr][7]}}, memory[addr]};
    else
      read_data = 32'b0;
  end

endmodule

//_________________________________________________

module MuxMemToReg(
  input memToReg,
  input [31:0] alu_result,
  input [31:0] read_data_mem,
  output [31:0] write_data
);

  assign write_data = memToReg ? read_data_mem : alu_result;

endmodule

//__________________________________________________

module cpu_top (
  input clk,
  input reset
);

  wire [31:0] pc_out;
  wire [31:0] instruction;

  wire reg_write;
  wire alu_src;
  wire mem_to_reg;
  wire mem_read;
  wire mem_write;
  wire branch;
  wire [1:0] alu_op;

  wire [31:0] imm_out;
  wire zero;

  // Campos do instruction para acessar registradores
  wire [4:0] rs1 = instruction[19:15];
  wire [4:0] rs2 = instruction[24:20];
  wire [4:0] rd  = instruction[11:7];

  wire [31:0] reg_data1;
  wire [31:0] reg_data2;
  wire [31:0] alu_input2;
  wire [31:0] alu_result;
  wire [31:0] mem_read_data;

  wire [3:0] alu_op_code; // saída do alu_control
  wire [6:0] opcode = instruction[6:0];

  // Instancia PC
  pc pc_inst (
    .clk(clk),
    .reset(reset),
    .zero(zero),
    .imm_out(imm_out),
    .branch(branch),
    .pc_out(pc_out)
  );

  // Instancia memória de instruções
  // ATENÇÃO: Aqui a sua instância de instruction_memory chama-se 'imem'
  instruction_memory imem (
    .pc(pc_out),
    .instruction(instruction)
  );

  // Instancia controle
  control control_inst (
    .opcode(opcode),
    .reg_write(reg_write),
    .alu_src(alu_src),
    .mem_to_reg(mem_to_reg),
    .mem_read(mem_read),
    .mem_write(mem_write),
    .branch(branch),
    .alu_op(alu_op)
  );

  // Instancia gerador de imediato
  imm_gen immgen_inst (
    .instr(instruction),
    .imm_out(imm_out)
  );

  // Instancia banco de registradores
  registers registers_inst (
    .clk(clk),
    .reset(reset),
    .rs1(rs1),
    .rs2(rs2),
    .rd(rd),
    .write_data(mem_to_reg ? mem_read_data : alu_result),
    .reg_write(reg_write),
    .read_data1(reg_data1),
    .read_data2(reg_data2)
  );

  // Mux entre registrador e imediato para ALU
  MuxAluSrc mux_alu_src (
    .reg_data2(reg_data2),
    .imm_out(imm_out),
    .alu_src(alu_src),
    .alu_input2(alu_input2)
  );

  // Instancia alu_control
  alu_control alu_control_inst (
    .alu_op(alu_op),
    .funct3(instruction[14:12]),
    .funct7(instruction[31:25]),
    .alu_ctrl(alu_op_code)
  );

  // Instancia ALU
  alu alu_inst (
    .a(reg_data1),
    .b(alu_input2),
    .alu_control(alu_op_code),
    .result(alu_result),
    .zero(zero)
  );

  // Instancia memória de dados
  data_memory data_memory_inst (
    .clk(clk),
    .addr(alu_result[7:0]),
    .write_data(reg_data2),
    .memWrite(mem_write),
    .memRead(mem_read),
    .read_data(mem_read_data)
  );

endmodule

//__________________________________________________


