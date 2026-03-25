`timescale 1ns / 1ps

module tb_tinker;
    // Core Inputs
    reg clk;
    reg reset;

    // Instantiate the Unit Under Test (UUT)
    tinker_core uut (.clk(clk), .reset(reset));

    // Clock Generation: toggles every 5 nanoseconds
    always #5 clk = ~clk;

    // Little endian write instruction and write memory
    task write_inst;
        input [63:0] addr;
        input [31:0] inst;
        begin
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

    initial begin
        $dumpfile("tinker_waves.vcd");
        $dumpvars(0, tb_tinker);
        
        clk = 0;
        reset = 1;

        // Load the IEEE-754 double precision value for 1.5 at address 0x108
        write_mem64(64'h0108, 64'h3FF8000000000000);

        // 0x2000: addi r1, 15
        write_inst(64'h2000, 32'hC840000F); 
        // 0x2004: addi r2, 5
        write_inst(64'h2004, 32'hC8800005); 
        // 0x2008: add r3, r1, r2    (r3 should become 15 + 5 = 20)
        write_inst(64'h2008, 32'hC0C22000); 
        // 0x200C: sub r4, r1, r2    (r4 should become 15 - 5 = 10)
        write_inst(64'h200C, 32'hD1022000); 
        // 0x2010: mul r5, r1, r2    (r5 should become 15 * 5 = 75)
        write_inst(64'h2010, 32'hE1422000); 
        // 0x2014: div r6, r1, r2    (r6 should become 15 / 5 = 3)
        write_inst(64'h2014, 32'hE9822000); 

        // 0x2018: xor r7, r1, r2    (15 XOR 5 = 10)
        write_inst(64'h2018, 32'h11C22000); 
        // 0x201C: shftli r8, r1, 2  (Shift r1 left by 2: 15 << 2 = 60)
        write_inst(64'h201C, 32'h3A020002); 
        
        // 0x2020: mov (r0)(0x100), r8  (Store the 60 from r8 into memory at 0x100)
        write_inst(64'h2020, 32'h98100100); 
        // 0x2024: mov r9, (r0)(0x100)  (Load that 60 back out into r9)
        write_inst(64'h2024, 32'h82400100); 
        
        // 0x2028: brr 8                (Jump forward 8 bytes -> PC moves to 0x2030)
        write_inst(64'h2028, 32'h50000008); 
        // 0x202C: addi r0, 999         (THIS SHOULD BE SKIPPED!)
        write_inst(64'h202C, 32'hC80003E7); 
        
        // 0x2030: mov r11, (r0)(0x108) (Load the double 1.5 from memory 0x108)
        write_inst(64'h2030, 32'h82C00108); 
        // 0x2034: addf r12, r11, r11   (1.5 + 1.5 = 3.0. r12 should equal 0x4008000000000000)
        write_inst(64'h2034, 32'hA316B000); 

        // 0x2038: priv 0               (Triggers the Halt command)
        write_inst(64'h2038, 32'h78000000); 

        // Release reset and let the CPU run
        #15 reset = 0;

        // Failsafe timeout
        #500;
        $display("\n[ERROR] Timeout! The CPU did not hit the Halt instruction.");
        $finish;
    end

    // This will print to the console every time a monitored register changes!
    initial begin
        $monitor("Time=%0t | PC=%h | r3(Add)=%0d | r8(Shft)=%0d | r9(Mem)=%0d | r12(FPU)=%h", 
                 $time, uut.pc, 
                 uut.reg_file.registers[3], 
                 uut.reg_file.registers[8], 
                 uut.reg_file.registers[9],
                 uut.reg_file.registers[12]);
    end

endmodule