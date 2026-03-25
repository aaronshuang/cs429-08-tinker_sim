module instruction_decoder (
    // Instruction
    input [31:0] instruction,

    // Instruction Parts
    output [4:0] opcode,

    // Register Ports
    output [4:0] rd, rs, rt,

    // Immediate
    output [11:0] imm,

    // ALU Ports
    output use_immediate,
    output use_fpu_instruction,

    // Control Signals
    output reg reg_write_en,
    output reg mem_read,
    output reg mem_write,
    output is_branch
);
    assign opcode = instruction[31:27];
    assign rd = instruction[26:22];
    assign rs = instruction[21:17];
    assign rt = instruction[16:12];
    assign imm = instruction[11:0];

    assign use_immediate = (
        opcode == 5'h19 | // addi
        opcode == 5'h1b | // subi
        opcode == 5'h05 | // shftri
        opcode == 5'h07 | // shftli
        opcode == 5'h10 | // load
        opcode == 5'h13  // store
    );

    assign use_fpu_instruction = (
        opcode == 5'h14 |
        opcode == 5'h15 |
        opcode == 5'h16 |
        opcode == 5'h17
    );

    assign is_branch = (opcode >= 5'h08 && opcode <= 5'h0e);

    always @(*) begin
        reg_write_en = 0;
        mem_read = 0;
        mem_write = 0;

        case (opcode)
            // Math, Logic, Shifts, and Load
            5'h18, 5'h19, 5'h1a, 5'h1b, 5'h1c, 5'h1d, 
            5'h00, 5'h01, 5'h02, 5'h03,
            5'h04, 5'h05, 5'h06, 5'h07,
            5'h14, 5'h15, 5'h16, 5'h17: begin
                reg_write_en = 1;
            end
            
            5'h10, 5'h0d: begin // Load: mov rd, (rs)(L)
                mem_read = 1;
                if (opcode == 5'h10) reg_write_en = 1;
            end
            5'h13, 5'h0c: begin // Store: mov (rd)(L), rs 
                mem_write = 1;
            end
        endcase
    end
endmodule

module register_file (
    input clk,
    input reset,
    input [63:0] data,
    input [4:0] rd, rs, rt,
    input write_enable,
    output [63:0] rd_val, rs_val, rt_val,
    output [63:0] r31_val
);
    reg [63:0] registers [0:31];

    assign rd_val = registers[rd];
    assign rs_val = registers[rs];
    assign rt_val = registers[rt];
    assign r31_val = registers[31];

    integer i;

    always @(posedge clk) begin
        if (reset) begin
            for (i = 0; i < 31; i = i + 1) begin
                registers[i] <= 64'b0;
            end
            registers[31] <= 64'd524288;
        end else if (write_enable) begin
            registers[rd] <= data;
        end
    end
endmodule

module ALU (
    input [63:0] a, b,
    input [4:0] op,
    output reg [63:0] res
);
    always @(*) begin
        case (op)
            5'h00: res = a & b;
            5'h01: res = a | b;
            5'h02: res = a ^ b;
            5'h03: res = ~a;
            5'h18, 5'h19: res = a + b;
            5'h10, 5'h13: res = a + b;
            5'h1a, 5'h1b: res = a - b;
            5'h1c: res = a * b;
            5'h1d: res = a / b;
            5'h04, 5'h05: res = a >> b;
            5'h06, 5'h07: res = a << b;
            default: res = 64'b0;
        endcase
    end
endmodule

module FPU (
    input [63:0] a, b,
    input [4:0] op,
    output reg [63:0] res
);

    reg sign_a, sign_b, sign_res;
    reg [10:0] exp_a, exp_b, exp_res;
    reg [10:0] eff_exp_a, eff_exp_b; // exp for subnormals

    reg [55:0] frac_a, frac_b; // extra bit for carry + 3 GRS bits
    reg [56:0] frac_add_res; // extra bit for overflow + 3 GRS bits

    reg [52:0] m_a, m_b; // 53-bit effective fractions
    reg signed [12:0] signed_exp; // Signed to safely handle underflow/overflow
    reg [106:0] raw_mul_res; // 106 bits + 1 for rounding overflow
    reg [107:0] div_num; // Shifted numerator
    reg [56:0] raw_div_res; // 56 bits + 1 for rounding overflow

    reg[10:0] exp_diff;
    integer i;
    reg[5:0] shift_amt;
    reg[55:0] shift_mask;

    reg G, R, S, LSB;
    reg round_up;

    always @(*) begin
        res = 64'b0;

        sign_a = a[63];
        sign_b = b[63];

        exp_a = a[62:52];
        exp_b = b[62:52];
        eff_exp_a = (exp_a == 0) ? 11'd1 : exp_a;
        eff_exp_b = (exp_b == 0) ? 11'd1 : exp_b;

        frac_a = { (exp_a != 0), a[51:0], 3'b000 };
        frac_b = { (exp_b != 0), b[51:0], 3'b000 };

        case (op)
            5'h14, 5'h15: begin // addf / subf
                if (op == 5'h15) sign_b = ~sign_b;

                // Align exponents
                if (eff_exp_a > eff_exp_b) begin
                    exp_diff = eff_exp_a - eff_exp_b;
                    exp_res  = eff_exp_a;
                    if (exp_diff > 55) begin
                        frac_b = {55'b0, |frac_b};
                    end else begin
                        // shift b to the left but or the truncated bits for the sticky bit
                        shift_mask = (56'd1 << exp_diff) - 56'd1;
                        frac_b = (frac_b >> exp_diff) | {55'b0, |(frac_b & shift_mask)};
                    end
                end else if (eff_exp_b > eff_exp_a) begin
                    exp_diff = eff_exp_b - eff_exp_a;
                    exp_res  = eff_exp_b;
                    if (exp_diff > 55) begin
                        frac_a = {55'b0, |frac_a};
                    end else begin
                        shift_mask = (56'd1 << exp_diff) - 56'd1;
                        frac_a = (frac_a >> exp_diff) | {55'b0, |(frac_a & shift_mask)};
                    end
                end else begin
                    exp_res = eff_exp_a;
                end

                // Compute
                if (sign_a == sign_b) begin
                    frac_add_res = frac_a + frac_b;
                    sign_res  = sign_a;
                end else begin
                    if (frac_a >= frac_b) begin
                        frac_add_res = frac_a - frac_b;
                        sign_res  = sign_a;
                    end else begin
                        frac_add_res = frac_b - frac_a;
                        sign_res  = sign_b;
                    end
                end
                
                // Normalize
                if (frac_add_res == 0) begin
                    res = 64'b0; // Exact zero
                end else begin
                    // Check for overflow
                    if (frac_add_res[56]) begin 
                        frac_add_res = (frac_add_res >> 1) | {56'b0, frac_add_res[0]};
                        exp_res = exp_res + 1;
                    end else begin
                        // Shift left until leading 1
                        shift_amt = 0;
                        for (i = 55; i >= 0; i = i - 1) begin
                            if (frac_add_res[55] == 0 && exp_res > 0) begin
                                frac_add_res = frac_add_res << 1;
                                exp_res = exp_res - 1;
                            end
                        end
                    end

                    // Check if subnormal
                    if (exp_res == 0 && frac_add_res[55] == 1) begin
                        exp_res = 0; 
                    end

                    LSB = frac_add_res[3]; // The actual least significant bit of the 52-bit fraction
                    G = frac_add_res[2];
                    R = frac_add_res[1];
                    S = frac_add_res[0];
                    // Round up if G is 1 AND (R or S is 1 OR LSB is 1)
                    round_up = G & (R | S | LSB);
                    if (round_up) begin
                        frac_add_res = frac_add_res + 4'b1000;
                        // Check rounding overflow
                        if (frac_add_res[56]) begin
                            frac_add_res = frac_add_res >> 1;
                            exp_res = exp_res + 1;
                        end
                    end

                    // Drop implict bit
                    res = {sign_res, exp_res, frac_add_res[54:3]};
                end
            end
            5'h16: begin // mulf
                sign_res = sign_a ^ sign_b;
                m_a = { (exp_a != 0), a[51:0] };
                m_b = { (exp_b != 0), b[51:0] };

                if (m_a == 0 || m_b == 0) begin
                    res = {sign_res, 63'b0};
                end else begin
                    signed_exp = eff_exp_a + eff_exp_b - 1023;
                    raw_mul_res = m_a * m_b;
                    
                    // Normalize
                    if (raw_mul_res[105]) begin
                        signed_exp = signed_exp + 1;
                    end else begin
                        // Shift left until leading 1 is at bit 105
                        for (i = 105; i >= 0; i = i - 1) begin
                            if (raw_mul_res[105] == 0 && signed_exp > 0) begin
                                raw_mul_res = raw_mul_res << 1;
                                signed_exp = signed_exp - 1;
                            end
                        end
                    end

                    // GRS rounding
                    LSB = raw_mul_res[53];
                    G = raw_mul_res[52];
                    R = raw_mul_res[51];
                    S = |raw_mul_res[50:0];
                    round_up = G & (R | S | LSB);

                    if (round_up) begin
                        raw_mul_res = raw_mul_res + (107'b1 << 53);
                        if (raw_mul_res[106]) begin // Rounding overflow
                            raw_mul_res = raw_mul_res >> 1;
                            signed_exp = signed_exp + 1;
                        end
                    end

                    // Cap exponents
                    if (signed_exp <= 0) exp_res = 0; // Subnormal
                    else if (signed_exp >= 2047) exp_res = 11'h7FF; // Infinity
                    else exp_res = signed_exp[10:0];

                    res = {sign_res, exp_res, raw_mul_res[104:53]};
                end
            end
            5'h17: begin // divf
                sign_res = sign_a ^ sign_b;
                m_a = { (exp_a != 0), a[51:0] };
                m_b = { (exp_b != 0), b[51:0] };

                if (m_b == 0) begin
                    res = {sign_res, 11'h7FF, 52'b0}; // Div by zero -> Infinity
                end else if (m_a == 0) begin
                    res = {sign_res, 63'b0}; // 0 / X -> 0
                end else begin
                    signed_exp = eff_exp_a - eff_exp_b + 1023;
                    
                    // Shift numerator left by 55 bits to generate 56 bits of quotient
                    div_num = {m_a, 55'b0};
                    raw_div_res = div_num / m_b;
                    
                    // Normalize the quotient
                    if (raw_div_res[55]) begin
                        // Already proper form 1....
                    end else begin
                        for (i = 55; i >= 0; i = i - 1) begin
                            if (raw_div_res[55] == 0 && signed_exp > 0) begin
                                raw_div_res = raw_div_res << 1;
                                signed_exp = signed_exp - 1;
                            end
                        end
                    end

                    // GRS rounding
                    LSB = raw_div_res[3];
                    G = raw_div_res[2];
                    R = raw_div_res[1];
                    S = |(div_num % m_b) | raw_div_res[0]; 
                    
                    round_up = G & (R | S | LSB);

                    if (round_up) begin
                        raw_div_res = raw_div_res + 4'b1000;
                        if (raw_div_res[56]) begin // Rounding overflow
                            raw_div_res = raw_div_res >> 1;
                            signed_exp = signed_exp + 1;
                        end
                    end

                    // Cap exponents
                    if (signed_exp <= 0) exp_res = 0; 
                    else if (signed_exp >= 2047) exp_res = 11'h7FF; 
                    else exp_res = signed_exp[10:0];

                    res = {sign_res, exp_res, raw_div_res[54:3]};
                end
            end
            default: res = 64'b0;
        endcase
    end
endmodule

module instruction_fetch_unit (
    input clk,
    input reset,
    input [63:0] branch_target,
    input take_branch,
    output reg [63:0] pc
);
    always @(posedge clk) begin
        if (reset) begin
            pc <= 64'h2000;
        end else if (take_branch) begin
            pc <= branch_target;
        end else begin
            pc <= pc + 4;
        end
    end
endmodule

module memory (
    input clk,
    input [63:0] addr,
    input [63:0] write_data,
    input mem_write,
    input mem_read,
    output [63:0] read_data
);
    parameter MEM_SIZE = 524288;
    reg [7:0] bytes [0:MEM_SIZE - 1];

    assign read_data = mem_read ? {
        bytes[addr + 7], bytes[addr + 6], bytes[addr + 5], bytes[addr + 4], 
        bytes[addr + 3], bytes[addr + 2], bytes[addr + 1], bytes[addr]
    } : 64'b0;

    always @(posedge clk) begin
        if (mem_write) begin
            bytes[addr] <= write_data[7:0];
            bytes[addr+1] <= write_data[15:8];
            bytes[addr+2] <= write_data[23:16];
            bytes[addr+3] <= write_data[31:24];
            bytes[addr+4] <= write_data[39:32];
            bytes[addr+5] <= write_data[47:40];
            bytes[addr+6] <= write_data[55:48];
            bytes[addr+7] <= write_data[63:56];
        end
    end 
endmodule

module tinker_core (
    input clk,
    input reset
);
    wire [63:0] pc;
    wire [31:0] current_instruction;

    wire [4:0] opcode, rd, rs, rt;
    wire [11:0] imm;
    wire use_immediate, use_fpu_instruction;
    wire reg_write_en, mem_read, mem_write;

    wire [63:0] rd_val, rs_val, rt_val, alu_res, fpu_res;
    wire [63:0] alu_input_a, alu_input_b;
    wire [63:0] reg_write_data, mem_read_data;

    wire is_branch;
    reg take_branch;
    reg [63:0] branch_target;

    wire [63:0] r31_val;

    instruction_fetch_unit fetch (
        .clk(clk), 
        .reset(reset),
        .branch_target(branch_target),
        .take_branch(take_branch),
        .pc(pc)
    );

    assign current_instruction = {
        memory.bytes[pc+3], memory.bytes[pc+2], 
        memory.bytes[pc+1], memory.bytes[pc]
    };

    instruction_decoder decoder (
        .instruction(current_instruction),
        .opcode(opcode), 
        .rd(rd), .rs(rs), .rt(rt),
        .imm(imm),
        .use_immediate(use_immediate),
        .use_fpu_instruction(use_fpu_instruction),
        .reg_write_en(reg_write_en),
        .mem_read(mem_read),
        .mem_write(mem_write),
        .is_branch(is_branch)
    );

    register_file reg_file (
        .clk(clk),
        .reset(reset),
        .data(reg_write_data),
        .rd(rd), .rs(rs), .rt(rt),
        .write_enable(reg_write_en),
        .rd_val(rd_val), .rs_val(rs_val), .rt_val(rt_val),
        .r31_val(r31_val)
    );

    assign alu_input_b = (use_immediate) ? {{52{imm[11]}}, imm} : rt_val;
    assign alu_input_a = (opcode == 5'h13) ? rd_val : rs_val;

    ALU alu (.a(alu_input_a), .b(alu_input_b), .op(opcode), .res(alu_res));
    FPU fpu (.a(rs_val), .b(alu_input_b), .op(opcode), .res(fpu_res));

    wire [63:0] stack_addr = r31_val - 8;
    wire [63:0] mem_addr = (opcode == 5'h0c || opcode == 5'h0d) ? stack_addr : alu_res;
    wire [63:0] mem_wdata = (opcode == 5'h0c) ? (pc + 4) : rs_val;

    memory memory (
        .clk(clk), .addr(mem_addr), 
        .write_data(mem_wdata), 
        .mem_write(mem_write),
        .mem_read(mem_read),
        .read_data(mem_read_data)
    );

    assign reg_write_data = (use_fpu_instruction) ? fpu_res : (mem_read) ? mem_read_data : alu_res;

    // Signed casts for the brgt comparison
    wire signed [63:0] signed_rs = rs_val;
    wire signed [63:0] signed_rt = rt_val;

    always @(*) begin
        take_branch = 1'b0;
        branch_target = 64'b0;

        if (is_branch) begin
            case (opcode)
                5'h08: begin // br rd
                    take_branch = 1'b1;
                    branch_target = rd_val;
                end
                5'h09: begin // brr rd
                    take_branch = 1'b1;
                    branch_target = pc + rd_val;
                end
                5'h0a: begin // brr L
                    take_branch = 1'b1;
                    branch_target = pc + {{52{imm[11]}}, imm}; 
                end
                5'h0b: begin // brnz rd, rs
                    if (rs_val != 0) begin
                        take_branch = 1'b1;
                        branch_target = rd_val;
                    end
                end
                5'h0c: begin // call
                    take_branch = 1'b1;
                    branch_target = rd_val;
                end
                5'h0d: begin // return
                    take_branch = 1'b1;
                    branch_target = mem_read_data;
                end
                5'h0e: begin // brgt rd, rs, rt
                    if (signed_rs > signed_rt) begin
                        take_branch = 1'b1;
                        branch_target = rd_val;
                    end
                end
            endcase
        end
    end

    // testing halt mechanic
    always @(posedge clk) begin
        if (opcode == 5'h0f && imm == 12'b0) begin
            $display("Execution Halted.");
            $finish; 
        end
    end
endmodule