`timescale 1ns / 1ps

module tb_tinker;

    // Inputs
    reg clk;
    reg reset;

    // Instantiate the Unit Under Test (UUT)
    tinker_core uut (
        .clk(clk),
        .reset(reset)
    );

    // Clock Generation: toggles every 5 nanoseconds
    always #5 clk = ~clk;

    initial begin
        // Initialize Inputs
        clk = 0;
        reset = 1;

        // --- LOAD MACHINE CODE INTO MEMORY ---
        // Because Tinker starts at 0x2000 and is Little-Endian, 
        // we write the bytes of our instructions into memory here.

        // Instruction 1: addi r1, 10
        // Opcode 0x19 (11001), rd=1 (00001), rs=0, rt=0, imm=10
        // Binary: 1100 1000 0100 0000 0000 0000 0000 1010 -> Hex: C840000A
        uut.memory.bytes[64'h2000] = 8'h0A;
        uut.memory.bytes[64'h2001] = 8'h00;
        uut.memory.bytes[64'h2002] = 8'h40;
        uut.memory.bytes[64'h2003] = 8'hC8;

        // Instruction 2: addi r2, 20
        // Opcode 0x19 (11001), rd=2 (00010), rs=0, rt=0, imm=20
        // Binary: 1100 1000 1000 0000 0000 0000 0001 0100 -> Hex: C8800014
        uut.memory.bytes[64'h2004] = 8'h14;
        uut.memory.bytes[64'h2005] = 8'h00;
        uut.memory.bytes[64'h2006] = 8'h80;
        uut.memory.bytes[64'h2007] = 8'hC8;

        // Instruction 3: add r3, r1, r2
        // Opcode 0x18 (11000), rd=3 (00011), rs=1 (00001), rt=2 (00010)
        // Binary: 1100 0000 1100 0010 0010 0000 0000 0000 -> Hex: C0C22000
        uut.memory.bytes[64'h2008] = 8'h00;
        uut.memory.bytes[64'h2009] = 8'h20;
        uut.memory.bytes[64'h200A] = 8'hC2;
        uut.memory.bytes[64'h200B] = 8'hC0;

        // Instruction 4: Halt (priv 0)
        // Opcode 0x0F (01111), imm=0
        // Binary: 0111 1000 0000 0000 0000 0000 0000 0000 -> Hex: 78000000
        uut.memory.bytes[64'h200C] = 8'h00;
        uut.memory.bytes[64'h200D] = 8'h00;
        uut.memory.bytes[64'h200E] = 8'h00;
        uut.memory.bytes[64'h200F] = 8'h78;

        // Wait a little bit, then release reset
        #15;
        reset = 0;

        // The CPU is now running! 
        // We set a fail-safe timeout in case Halt fails
        #500;
        $display("Timeout reached.");
        $finish;
    end

    // Monitor allows us to watch variables in the console in real-time
    initial begin
        $monitor("Time=%0d | PC=%h | r1=%0d | r2=%0d | r3=%0d", 
                 $time, uut.pc, uut.reg_file.registers[1], uut.reg_file.registers[2], uut.reg_file.registers[3]);
    end

endmodule