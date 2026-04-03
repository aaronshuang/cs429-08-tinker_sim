`timescale 1ns / 1ps

module tb_tinker;

    // --- CPU INSTANTIATION ---
    reg clk;
    reg reset;
    tinker_core uut (.clk(clk), .reset(reset));

    // Clock Generation: 10ns period
    always #5 clk = ~clk;

    // --- ASSEMBLER & MEMORY LOADERS ---
    task write_inst;
        input [63:0] addr;
        input [4:0]  op;
        input [4:0]  rd;
        input [4:0]  rs;
        input [4:0]  rt;
        input [11:0] imm;
        reg   [31:0] inst;
        begin
            inst = {op, rd, rs, rt, imm};
            uut.memory.bytes[addr]   = inst[7:0];
            uut.memory.bytes[addr+1] = inst[15:8];
            uut.memory.bytes[addr+2] = inst[23:16];
            uut.memory.bytes[addr+3] = inst[31:24];
        end
    endtask

    task write_mem64;
        input [63:0] addr;
        input [63:0] data;
        begin
            uut.memory.bytes[addr]   = data[7:0];
            uut.memory.bytes[addr+1] = data[15:8];
            uut.memory.bytes[addr+2] = data[23:16];
            uut.memory.bytes[addr+3] = data[31:24];
            uut.memory.bytes[addr+4] = data[39:32];
            uut.memory.bytes[addr+5] = data[47:40];
            uut.memory.bytes[addr+6] = data[55:48];
            uut.memory.bytes[addr+7] = data[63:56];
        end
    endtask

    // --- VERIFICATION HELPER ---
    integer passed_tests = 0;
    integer total_tests = 0;
    task assert_reg;
        input [4:0] reg_idx;
        input [63:0] expected;
        input [255:0] test_name;
        begin
            total_tests = total_tests + 1;
            if (uut.reg_file.registers[reg_idx] === expected) begin
                $display("[PASS] %s \t\t(r%0d = %h)", test_name, reg_idx, expected);
                passed_tests = passed_tests + 1;
            end else begin
                $display("[FAIL] %s \t\t(r%0d = %h, Expected: %h)", test_name, reg_idx, uut.reg_file.registers[reg_idx], expected);
            end
        end
    endtask

    // --- OPCODES CONSTANTS ---
    localparam OP_AND = 5'h00, OP_OR = 5'h01, OP_XOR = 5'h02, OP_NOT = 5'h03;
    localparam OP_SHFTR = 5'h04, OP_SHFTRI = 5'h05, OP_SHFTL = 5'h06, OP_SHFTLI = 5'h07;
    localparam OP_BR = 5'h08, OP_BRR_R = 5'h09, OP_BRR_L = 5'h0A, OP_BRNZ = 5'h0B;
    localparam OP_CALL = 5'h0C, OP_RET = 5'h0D, OP_BRGT = 5'h0E, OP_PRIV = 5'h0F;
    localparam OP_MOV_ML = 5'h10, OP_MOV_RR = 5'h11, OP_MOV_L = 5'h12, OP_MOV_SM = 5'h13;
    localparam OP_ADDF = 5'h14, OP_SUBF = 5'h15, OP_MULF = 5'h16, OP_DIVF = 5'h17;
    localparam OP_ADD = 5'h18, OP_ADDI = 5'h19, OP_SUB = 5'h1A, OP_SUBI = 5'h1B;
    localparam OP_MUL = 5'h1C, OP_DIV = 5'h1D;

    integer timeout;

    initial begin
        $dumpfile("tinker_comprehensive.vcd");
        $dumpvars(0, tb_tinker);
        
        clk = 0;
        reset = 1;

        // set up memory
        write_mem64(16'h0108, 64'h3FF8000000000000); // Address 0x108 = Float 1.5
        write_mem64(16'h0110, 64'h4000000000000000); // Address 0x110 = Float 2.0
        write_mem64(16'h0118, 64'h7FF8000000000000); // Address 0x118 = Float NaN
        write_mem64(16'h0120, 64'h7FF0000000000000); // Address 0x120 = Float +Infinity

        // instruction memory
        
        // math
        // 0x2000
        write_inst(16'h2000, OP_ADDI, 1, 0, 0, 12'h005); // r1 = 5
        write_inst(16'h2004, OP_ADDI, 2, 0, 0, 12'h00A); // r2 = 10
        write_inst(16'h2008, OP_ADD,  3, 1, 2, 12'h000); // r3 = 5 + 10 = 15
        write_inst(16'h200C, OP_SUB,  4, 2, 1, 12'h000); // r4 = 10 - 5 = 5
        write_inst(16'h2010, OP_MUL,  5, 1, 2, 12'h000); // r5 = 5 * 10 = 50
        write_inst(16'h2014, OP_DIV,  6, 2, 1, 12'h000); // r6 = 10 / 5 = 2

        // logic
        // 0x2018
        write_inst(16'h2018, OP_AND,  7, 1, 2, 12'h000); // r7 = 5 & 10 = 0
        write_inst(16'h201C, OP_OR,   8, 1, 2, 12'h000); // r8 = 5 | 10 = 15
        write_inst(16'h2020, OP_XOR,  9, 1, 2, 12'h000); // r9 = 5 ^ 10 = 15
        write_inst(16'h2024, OP_NOT, 10, 1, 0, 12'h000); // r10= ~5 = 0xFFF...FA

        // shifts
        // 0x2028
        write_inst(16'h2028, OP_SHFTLI, 1, 0, 0, 12'h002); // r1 = 5 << 2 = 20
        write_inst(16'h202C, OP_SHFTRI, 2, 0, 0, 12'h001); // r2 = 10 >> 1 = 5

        // movs 
        // 0x2030
        write_inst(16'h2030, OP_MOV_L, 11, 0, 0, 12'hABC); // r11[63:52] = 0xABC
        write_inst(16'h2034, OP_MOV_RR, 12, 1, 0, 12'h000); // r12 = r1 = 20
        write_inst(16'h2038, OP_MOV_SM,  0, 12, 0, 12'h100); // Mem[0x100] = r12 (20)
        write_inst(16'h203C, OP_MOV_ML, 13, 0, 0, 12'h100); // r13 = Mem[0x100] = 20

        // controls
        // 0x2040
        write_inst(16'h2040, OP_BRR_L, 0, 0, 0, 12'h008); // Jump forward 8 bytes
        write_inst(16'h2044, OP_ADDI, 14, 0, 0, 12'h999); // r14=999 (SHOULD SKIP)
        
        // 0x2048 (Landed here) - Set up r22 to point to function at 0x2088
        write_inst(16'h2048, OP_ADDI, 22, 0, 0, 12'h208); // r22 = 0x208
        write_inst(16'h204C, OP_SHFTLI, 22, 0, 0, 12'h004); // r22 = 0x2080
        write_inst(16'h2050, OP_ADDI, 22, 0, 0, 12'h008); // r22 = 0x2088 (Func Addr)
        write_inst(16'h2054, OP_CALL, 22, 0, 0, 12'h000); // Call Func (Saves 0x2058 to Stack)

        // 0x2058 (Returns here)
        // --- FPU Edge Cases ---
        write_inst(16'h2058, OP_MOV_ML, 15, 0, 0, 12'h108); // r15 = 1.5
        write_inst(16'h205C, OP_MOV_ML, 16, 0, 0, 12'h110); // r16 = 2.0
        write_inst(16'h2060, OP_ADDF,   17, 15, 16, 12'h000); // r17 = 1.5 + 2.0 = 3.5
        write_inst(16'h2064, OP_MULF,   18, 15, 16, 12'h000); // r18 = 1.5 * 2.0 = 3.0

        write_inst(16'h2068, OP_MOV_ML, 23, 0, 0, 12'h118); // r23 = NaN
        write_inst(16'h206C, OP_MOV_ML, 24, 0, 0, 12'h120); // r24 = +Infinity
        write_inst(16'h2070, OP_ADDF,   25, 24, 16, 12'h000); // r25 = Inf + 2.0 = Inf
        write_inst(16'h2074, OP_DIVF,   26, 16,  0, 12'h000); // r26 = 2.0 / 0.0 = Inf
        write_inst(16'h2078, OP_MULF,   27, 23, 16, 12'h000); // r27 = NaN * 2.0 = NaN

        // 0x207C
        write_inst(16'h207C, OP_PRIV, 0, 0, 0, 12'h000); // HALT!

        // functions
        write_inst(16'h2088, OP_ADDI, 21, 0, 0, 12'h111); // r21 = 0x111
        write_inst(16'h208C, OP_RET,   0, 0, 0, 12'h000); // Return to Stack

        // execute
        #15 reset = 0; // Release Reset
        
        // Wait for CPU to hit HALT opcode or timeout
        timeout = 0;
        while (uut.opcode !== OP_PRIV && timeout < 1000) begin
            @(posedge clk);
            timeout = timeout + 1;
        end

        if (timeout >= 1000) begin
            $display("\n[FATAL] Timeout! CPU never hit the Halt Instruction. Infinite Loop or Branch Failure.\n");
            $finish;
        end

        // unit tests
        $display("TINKER CORE UNIT TEST RESULTS");

        assert_reg(1,  64'h14, "ADDI & SHFTLI    (5 << 2 = 20)");
        assert_reg(2,  64'h05, "ADDI & SHFTRI    (10 >> 1 = 5)");
        assert_reg(3,  64'h0F, "ADD              (5 + 10 = 15)");
        assert_reg(4,  64'h05, "SUB              (10 - 5 = 5) ");
        assert_reg(5,  64'h32, "MUL              (5 * 10 = 50)");
        assert_reg(6,  64'h02, "DIV              (10 / 5 = 2) ");
        
        assert_reg(7,  64'h00, "AND              (5 & 10 = 0) ");
        assert_reg(8,  64'h0F, "OR               (5 | 10 = 15)");
        assert_reg(9,  64'h0F, "XOR              (5 ^ 10 = 15)");
        assert_reg(10, 64'hFFFFFFFFFFFFFFFA, "NOT              (~5)         ");

        assert_reg(11, 64'h0000000000000ABC, "MOV_L            (0xABC0..)   ");
        assert_reg(12, 64'h14, "MOV_RR           (Copy r1)    ");
        assert_reg(13, 64'h14, "STORE & LOAD     (Mem I/O)    ");
        assert_reg(14, 64'h00, "BRR_L            (Skip Code)  ");
        
        assert_reg(21, 64'h111,"CALL & RET       (Stack Jumps)");

        assert_reg(17, 64'h400C000000000000, "ADDF             (1.5+2.0=3.5)");
        assert_reg(18, 64'h4008000000000000, "MULF             (1.5*2.0=3.0)");
        assert_reg(25, 64'h7FF0000000000000, "ADDF Infinity    (Inf+2.0=Inf)");
        assert_reg(26, 64'h7FF0000000000000, "DIVF by Zero     (2.0/0.0=Inf)");
        assert_reg(27, 64'h7FF8000000000000, "MULF NaN         (NaN*2.0=NaN)");

        if (passed_tests == total_tests)
            $display("   ALL %0d TESTS PASSED!", total_tests);
        else
            $display("   FAILED %0d / %0d TESTS. Check outputs.", (total_tests - passed_tests), total_tests);

        $finish;
    end
endmodule