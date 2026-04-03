`timescale 1ns / 1ps

module tb_tinker_2;

    reg clk;
    reg reset;

    // Instantiate the CPU Core
    tinker_core uut (.clk(clk), .reset(reset));

    // Clock Generation: 10ns period (posedge at 5, 15, 25, 35...)
    always #5 clk = ~clk;

    // Helper variables for testing
    integer passed_tests = 0;
    integer total_tests = 0;

    // ---------------------------------------------------------
    // Assertion Task
    // ---------------------------------------------------------
    task assert_eq;
        input [63:0] expected;
        input [63:0] actual;
        input [255:0] test_name;
        begin
            total_tests = total_tests + 1;
            if (expected === actual) begin
                $display("[PASS] %s", test_name);
                passed_tests = passed_tests + 1;
            end else begin
                $display("[FAIL] %s | Expected: %h, Got: %h", test_name, expected, actual);
            end
        end
    endtask

    // ---------------------------------------------------------
    // Instruction Loader Task
    // ---------------------------------------------------------
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

    initial begin
        // Setup GTKWave Output
        $dumpfile("tinker_internals.vcd");
        $dumpvars(0, tb_tinker);
        
        clk = 0;
        reset = 1;

        // Pre-load Memory with Test Instructions
        // Addr 0x2000: ADDI r1, 15
        write_inst(16'h2000, 5'h19, 5'd1, 5'd0, 5'd0, 12'd15);
        // Addr 0x2004: STORE (r1)(0x8), r2 
        write_inst(16'h2004, 5'h13, 5'd1, 5'd2, 5'd0, 12'd8);
        // Addr 0x2008: ADDF r5, r3, r4 
        write_inst(16'h2008, 5'h14, 5'd5, 5'd3, 5'd4, 12'd0);
        // Addr 0x200C: BRGT r8, r6, r7 
        write_inst(16'h200C, 5'h0E, 5'd8, 5'd6, 5'd7, 12'd0);

        // At 5ns, posedge clk happens. reset is 1, so pc <= 0x2000.
        // Drop reset at 12ns so PC stays locked at 0x2000 for the first test.
        #12 reset = 0; 

        // =================================================================
        // UNIT TEST 1: Decoder, Immediate MUX, and ALU Datapath (ADDI)
        // =================================================================
        $display("\n--- Testing ADDI (Decoder & ALU MUX) ---");
        // Time = 14ns (1ns before the posedge clk at 15ns)
        #2; 
        
        assert_eq(5'h19, uut.opcode, "Decoder Opcode Extraction (0x19)");
        assert_eq(5'd1, uut.rd, "Decoder Destination Register (r1)");
        assert_eq(12'd15, uut.imm, "Decoder Immediate Extraction (15)");
        assert_eq(1'b1, uut.use_immediate, "Decoder 'use_immediate' Flag Active");
        assert_eq(1'b1, uut.reg_write_en, "Decoder 'reg_write_en' Flag Active");
        
        assert_eq(64'd0, uut.alu_input_a, "ALU Input A correctly reads rd_val (0)");
        assert_eq(64'd15, uut.alu_input_b, "ALU Input B correctly routes immediate (15)");
        assert_eq(64'd15, uut.alu_res, "ALU computes correct result (15)");
        assert_eq(64'd15, uut.reg_write_data, "Write-back MUX routes ALU result");

        // Time = 15ns: Clock ticks! PC becomes 0x2004.
        
        // =================================================================
        // UNIT TEST 2: Memory Subsystem Wiring (STORE)
        // =================================================================
        $display("\n--- Testing STORE (Memory Datapath) ---");
        // Time = 24ns (1ns before the posedge clk at 25ns)
        #10; 
        
        // Inject fake data to test routing
        uut.reg_file.registers[1] = 64'd15; // Set base address
        uut.reg_file.registers[2] = 64'hDEADBEEF; // Set store data
        // Give 1ns for combinational logic to update after injection
        #0.1; 

        assert_eq(1'b1, uut.mem_write, "Decoder 'mem_write' Flag Active");
        assert_eq(1'b0, uut.reg_write_en, "Decoder disables register write");
        assert_eq(64'd15, uut.alu_input_a, "ALU Input A correctly grabs base addr from r1");
        assert_eq(64'd8, uut.alu_input_b, "ALU Input B correctly grabs offset (8)");
        assert_eq(64'd23, uut.mem_addr, "Memory MUX correctly calculates Address (15+8=23)");
        assert_eq(64'hDEADBEEF, uut.mem_wdata, "Memory MUX correctly routes r2 to wdata");

        // Time = 25ns: Clock ticks! PC becomes 0x2008.

        // =================================================================
        // UNIT TEST 3: FPU Subsystem Wiring (ADDF)
        // =================================================================
        $display("\n--- Testing ADDF (FPU Hookups) ---");
        // Time = 34ns (1ns before posedge at 35ns)
        #9.9; 
        
        // Inject IEEE-754 floats
        uut.reg_file.registers[3] = 64'h3FF8000000000000; // 1.5
        uut.reg_file.registers[4] = 64'h4000000000000000; // 2.0
        #0.1; 

        assert_eq(1'b1, uut.use_fpu_instruction, "Decoder flags FPU instruction");
        assert_eq(64'h400C000000000000, uut.fpu_res, "FPU correctly adds 1.5 + 2.0 = 3.5");
        assert_eq(64'h400C000000000000, uut.reg_write_data, "Write-back MUX properly prioritizes FPU res");

        // Time = 35ns: Clock ticks! PC becomes 0x200C.

        // =================================================================
        // UNIT TEST 4: Branching Logic Datapath (BRGT)
        // =================================================================
        $display("\n--- Testing BRGT (Branch Control Logic) ---");
        // Time = 44ns (1ns before posedge at 45ns)
        #9.9; 
        
        // Force the condition to be TRUE (r6 > r7)
        uut.reg_file.registers[6] = 64'd100;
        uut.reg_file.registers[7] = 64'd50;
        uut.reg_file.registers[8] = 64'h3000; // Target Addr
        #0.1;

        assert_eq(1'b1, uut.is_branch, "Decoder flags instruction as a Branch");
        assert_eq(1'b1, uut.take_branch, "Branch Evaluator registers r6 > r7 (TRUE)");
        assert_eq(64'h3000, uut.branch_target, "Branch Evaluator calculates target address (0x3000)");

        // Time = 45ns: Clock ticks! PC warps to 0x3000.
        
        #1; // Time = 46ns. PC should now be updated.
        assert_eq(64'h3000, uut.pc, "Fetch Unit correctly applies branch target to PC");

        // =================================================================
        // FINAL SUMMARY
        // =================================================================
        $display("\n===========================================");
        if (passed_tests == total_tests)
            $display("   ALL %0d INTERNAL DATAPATH TESTS PASSED!", total_tests);
        else
            $display("   FAILED %0d / %0d TESTS.", (total_tests - passed_tests), total_tests);
        $display("===========================================\n");

        $finish;
    end

endmodule