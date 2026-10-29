module cpu_core (
	input wire          rst_n,
	input wire          clk,

	input wire          mem_ready,
	input wire [31:0]   mem_data,
	output reg          mem_valid,
	output reg [29:0]   mem_addr,   // aligned to 4 bytes
	output reg [31:0] mem_wdata,
	output reg [3:0]  mem_wstrb
);

	// Memory interface
	localparam MEM_IDLE = 2'b01;
	localparam MEM_WAIT = 2'b10;

	reg [1:0] mem_state;
	reg [31:0] instr_word;

	// Handshake completion: valid and ready sampled together
	wire mem_xfer = mem_ready & mem_valid;

	always @(posedge clk) begin
		if (!rst_n) begin
			mem_state <= MEM_IDLE;
			mem_valid <= 1'b0;
			mem_addr <= 30'b0;
			mem_wdata <= 32'b0;
			mem_wstrb <= 4'b0;
		end else begin
			case (mem_state)
				MEM_IDLE: begin
					case (1'b1)
						mem_req_instr: begin
							mem_valid <= 1'b1;
							mem_addr <= current_pc[31:2];
							mem_wdata <= 32'b0;
							mem_wstrb <= 4'b0;
							mem_state <= MEM_WAIT;
						end

						mem_req_load: begin
							mem_valid <= 1'b1;
							mem_addr <= alu_out[31:2];
							mem_wdata <= 32'b0;
							mem_wstrb <= 4'b0;
							mem_state <= MEM_WAIT;
						end

						mem_req_store: begin
							mem_valid <= 1'b1;
							mem_addr <= alu_out[31:2];
							mem_wdata <= mem_store_data << {alu_out[1:0], 3'b000};
							if (instr_sb)
								mem_wstrb <= 4'b0001 << alu_out[1:0];
							else if (instr_sh)
								mem_wstrb <= 4'b0011 << alu_out[1:0];
							else
								mem_wstrb <= 4'b1111;
							mem_state <= MEM_WAIT;
						end
					endcase
				end
				MEM_WAIT: begin
					if (mem_xfer) begin
						if (mem_req_instr) begin
							instr_word <= mem_data;
						end

						mem_valid <= 0;
						mem_wstrb <= 4'b0;
						mem_state <= MEM_IDLE;

`ifndef SYNTHESIS
						if (mem_req_instr || mem_req_load)
							$display("Memory read: data=%08h", mem_data);

						if (mem_req_store)
							$display("Memory write: addr=%08h data=%08h strb=%b",
									{mem_addr, 2'b00}, mem_wdata, mem_wstrb);
`endif
					end
				end
			endcase
		end
	end

	// Instruction decoder
	reg decoder_1_stage;
	reg decoder_done;

	// Stage 1: opcode classification for use inside the decoder only
	reg predecode_load;
	reg predecode_store;
	reg predecode_branch;
	reg predecode_alu_imm;
	reg predecode_alu_reg;

	// RV32I 38/40 except EBREAK and ECALL
	reg instr_lui, instr_auipc, instr_jal, instr_jalr;
	reg instr_beq, instr_bne, instr_blt, instr_bge, instr_bltu, instr_bgeu;
	reg instr_lb, instr_lh, instr_lw, instr_lbu, instr_lhu, instr_sb, instr_sh, instr_sw;
	reg instr_addi, instr_slti, instr_sltiu, instr_xori, instr_ori, instr_andi, instr_slli, instr_srli, instr_srai;
	reg instr_add, instr_sub, instr_sll, instr_slt, instr_sltu, instr_xor, instr_srl, instr_sra, instr_or, instr_and;
	reg instr_fence;

	// RV32M 8/8
	reg instr_mul, instr_mulh, instr_mulhsu, instr_mulhu;
	reg instr_div, instr_divu, instr_rem, instr_remu;

	// Decoded operand indices and immediate values
	reg [4:0] decoded_rd, decoded_rs1;
	reg [4:0] decoded_rs2;
	reg [31:0] decoded_imm, decoded_imm_j;

	always @(posedge clk) begin
		if (!rst_n) begin
			decoder_1_stage <= 0;
			decoder_done <= 0;

			// U-type and Jump
			instr_lui   <= 0;
			instr_auipc <= 0;
			instr_jal   <= 0;
			instr_jalr  <= 0;

			// Load
			instr_lb    <= 0;
			instr_lh    <= 0;
			instr_lw    <= 0;
			instr_lbu   <= 0;
			instr_lhu   <= 0;

			// Store
			instr_sb    <= 0;
			instr_sh    <= 0;
			instr_sw    <= 0;

			// Immediate Shift
			instr_slli  <= 0;
			instr_srli  <= 0;
			instr_srai  <= 0;

			// Branch
			instr_beq   <= 0;
			instr_bne   <= 0;
			instr_blt   <= 0;
			instr_bge   <= 0;
			instr_bltu  <= 0;
			instr_bgeu  <= 0;

			// ALUI
			instr_addi  <= 0;
			instr_slti  <= 0;
			instr_sltiu <= 0;
			instr_xori  <= 0;
			instr_ori   <= 0;
			instr_andi  <= 0;

			// ALU
			instr_add   <= 0;
			instr_sub   <= 0;
			instr_sll   <= 0;
			instr_slt   <= 0;
			instr_sltu  <= 0;
			instr_xor   <= 0;
			instr_srl   <= 0;
			instr_sra   <= 0;
			instr_or    <= 0;
			instr_and   <= 0;

			instr_fence <= 0;

			// Multiply
			instr_mul    <= 0;
			instr_mulh   <= 0;
			instr_mulhsu <= 0;
			instr_mulhu  <= 0;

			// Divide
			instr_div    <= 0;
			instr_divu   <= 0;
			instr_rem    <= 0;
			instr_remu   <= 0;
			

			predecode_branch <= 0;
			predecode_load <= 0;
			predecode_store <= 0;
			predecode_alu_imm <= 0;
			predecode_alu_reg <= 0;

		end else begin
			decoder_done <= 0;

			// this is 1-st decode stage
			if (mem_xfer & mem_req_instr) begin
				decoder_1_stage <= 1;

				instr_lui     <= mem_data[6:0] == 7'b0110111;
				instr_auipc   <= mem_data[6:0] == 7'b0010111;
				instr_jal     <= mem_data[6:0] == 7'b1101111;
				instr_jalr    <= mem_data[6:0] == 7'b1100111 && mem_data[14:12] == 3'b000;

				predecode_branch        <= mem_data[6:0] == 7'b1100011;
				predecode_load          <= mem_data[6:0] == 7'b0000011;
				predecode_store         <= mem_data[6:0] == 7'b0100011;
				predecode_alu_imm       <= mem_data[6:0] == 7'b0010011;
				predecode_alu_reg       <= mem_data[6:0] == 7'b0110011;

				// this is for J-type
				{ decoded_imm_j[31:20], decoded_imm_j[10:1], decoded_imm_j[11], decoded_imm_j[19:12], decoded_imm_j[0] } <= $signed({mem_data[31:12], 1'b0});

				decoded_rd <= mem_data[11:7];
				decoded_rs1 <= mem_data[19:15];
				decoded_rs2 <= mem_data[24:20];
			end

			// this is 2-nd decode stage
			if (decoder_1_stage) begin
				decoder_1_stage <= 0;
				decoder_done <= 1;

				instr_beq   <= predecode_branch && instr_word[14:12] == 3'b000;
				instr_bne   <= predecode_branch && instr_word[14:12] == 3'b001;
				instr_blt   <= predecode_branch && instr_word[14:12] == 3'b100;
				instr_bge   <= predecode_branch && instr_word[14:12] == 3'b101;
				instr_bltu  <= predecode_branch && instr_word[14:12] == 3'b110;
				instr_bgeu  <= predecode_branch && instr_word[14:12] == 3'b111;

				instr_lb    <= predecode_load && instr_word[14:12] == 3'b000;
				instr_lh    <= predecode_load && instr_word[14:12] == 3'b001;
				instr_lw    <= predecode_load && instr_word[14:12] == 3'b010;
				instr_lbu   <= predecode_load && instr_word[14:12] == 3'b100;
				instr_lhu   <= predecode_load && instr_word[14:12] == 3'b101;

				instr_sb    <= predecode_store && instr_word[14:12] == 3'b000;
				instr_sh    <= predecode_store && instr_word[14:12] == 3'b001;
				instr_sw    <= predecode_store && instr_word[14:12] == 3'b010;

				instr_addi  <= predecode_alu_imm && instr_word[14:12] == 3'b000;
				instr_slti  <= predecode_alu_imm && instr_word[14:12] == 3'b010;
				instr_sltiu <= predecode_alu_imm && instr_word[14:12] == 3'b011;
				instr_xori  <= predecode_alu_imm && instr_word[14:12] == 3'b100;
				instr_ori   <= predecode_alu_imm && instr_word[14:12] == 3'b110;
				instr_andi  <= predecode_alu_imm && instr_word[14:12] == 3'b111;

				instr_slli  <= predecode_alu_imm && instr_word[14:12] == 3'b001 && instr_word[31:25] == 7'b0000000;
				instr_srli  <= predecode_alu_imm && instr_word[14:12] == 3'b101 && instr_word[31:25] == 7'b0000000;
				instr_srai  <= predecode_alu_imm && instr_word[14:12] == 3'b101 && instr_word[31:25] == 7'b0100000;

				instr_add   <= predecode_alu_reg && instr_word[14:12] == 3'b000 && instr_word[31:25] == 7'b0000000;
				instr_sub   <= predecode_alu_reg && instr_word[14:12] == 3'b000 && instr_word[31:25] == 7'b0100000;
				instr_sll   <= predecode_alu_reg && instr_word[14:12] == 3'b001 && instr_word[31:25] == 7'b0000000;
				instr_slt   <= predecode_alu_reg && instr_word[14:12] == 3'b010 && instr_word[31:25] == 7'b0000000;
				instr_sltu  <= predecode_alu_reg && instr_word[14:12] == 3'b011 && instr_word[31:25] == 7'b0000000;
				instr_xor   <= predecode_alu_reg && instr_word[14:12] == 3'b100 && instr_word[31:25] == 7'b0000000;
				instr_srl   <= predecode_alu_reg && instr_word[14:12] == 3'b101 && instr_word[31:25] == 7'b0000000;
				instr_sra   <= predecode_alu_reg && instr_word[14:12] == 3'b101 && instr_word[31:25] == 7'b0100000;
				instr_or    <= predecode_alu_reg && instr_word[14:12] == 3'b110 && instr_word[31:25] == 7'b0000000;
				instr_and   <= predecode_alu_reg && instr_word[14:12] == 3'b111 && instr_word[31:25] == 7'b0000000;

				instr_fence <= (instr_word[6:0] == 7'b0001111 && !instr_word[14:12]);

				// RV32M - Multiply
				instr_mul    <= predecode_alu_reg && instr_word[31:25] == 7'b0000001 && instr_word[14:12] == 3'b000;
				instr_mulh   <= predecode_alu_reg && instr_word[31:25] == 7'b0000001 && instr_word[14:12] == 3'b001;
				instr_mulhsu <= predecode_alu_reg && instr_word[31:25] == 7'b0000001 && instr_word[14:12] == 3'b010;
				instr_mulhu  <= predecode_alu_reg && instr_word[31:25] == 7'b0000001 && instr_word[14:12] == 3'b011;

				// RV32M - Divide / Remainder
				instr_div    <= predecode_alu_reg && instr_word[31:25] == 7'b0000001 && instr_word[14:12] == 3'b100;
				instr_divu   <= predecode_alu_reg && instr_word[31:25] == 7'b0000001 && instr_word[14:12] == 3'b101;
				instr_rem    <= predecode_alu_reg && instr_word[31:25] == 7'b0000001 && instr_word[14:12] == 3'b110;
				instr_remu   <= predecode_alu_reg && instr_word[31:25] == 7'b0000001 && instr_word[14:12] == 3'b111;

				case (1'b1)
					instr_jal:
						decoded_imm <= decoded_imm_j;
					|{instr_lui, instr_auipc}:
						decoded_imm <= instr_word[31:12] << 12;
					|{instr_jalr, predecode_load, predecode_alu_imm}:
						decoded_imm <= $signed(instr_word[31:20]);
					predecode_branch:
						decoded_imm <= $signed({instr_word[31], instr_word[7], instr_word[30:25], instr_word[11:8], 1'b0});
					predecode_store:
						decoded_imm <= $signed({instr_word[31:25], instr_word[11:7]});
					default:
						decoded_imm <= 1'bx;
				endcase

			end
		end
	end

	// Instruction name display
	reg [63:0] new_ascii_instr;

	always @* begin
		new_ascii_instr = "";

		if (instr_lui)      new_ascii_instr = "lui";
		if (instr_auipc)    new_ascii_instr = "auipc";
		if (instr_jal)      new_ascii_instr = "jal";
		if (instr_jalr)     new_ascii_instr = "jalr";

		if (instr_beq)      new_ascii_instr = "beq";
		if (instr_bne)      new_ascii_instr = "bne";
		if (instr_blt)      new_ascii_instr = "blt";
		if (instr_bge)      new_ascii_instr = "bge";
		if (instr_bltu)     new_ascii_instr = "bltu";
		if (instr_bgeu)     new_ascii_instr = "bgeu";

		if (instr_lb)       new_ascii_instr = "lb";
		if (instr_lh)       new_ascii_instr = "lh";
		if (instr_lw)       new_ascii_instr = "lw";
		if (instr_lbu)      new_ascii_instr = "lbu";
		if (instr_lhu)      new_ascii_instr = "lhu";
		if (instr_sb)       new_ascii_instr = "sb";
		if (instr_sh)       new_ascii_instr = "sh";
		if (instr_sw)       new_ascii_instr = "sw";

		if (instr_addi)     new_ascii_instr = "addi";
		if (instr_slti)     new_ascii_instr = "slti";
		if (instr_sltiu)    new_ascii_instr = "sltiu";
		if (instr_xori)     new_ascii_instr = "xori";
		if (instr_ori)      new_ascii_instr = "ori";
		if (instr_andi)     new_ascii_instr = "andi";
		if (instr_slli)     new_ascii_instr = "slli";
		if (instr_srli)     new_ascii_instr = "srli";
		if (instr_srai)     new_ascii_instr = "srai";

		if (instr_add)      new_ascii_instr = "add";
		if (instr_sub)      new_ascii_instr = "sub";
		if (instr_sll)      new_ascii_instr = "sll";
		if (instr_slt)      new_ascii_instr = "slt";
		if (instr_sltu)     new_ascii_instr = "sltu";
		if (instr_xor)      new_ascii_instr = "xor";
		if (instr_srl)      new_ascii_instr = "srl";
		if (instr_sra)      new_ascii_instr = "sra";
		if (instr_or)       new_ascii_instr = "or";
		if (instr_and)      new_ascii_instr = "and";

		if (instr_mul)    new_ascii_instr = "mul";
		if (instr_mulh)   new_ascii_instr = "mulh";
		if (instr_mulhsu) new_ascii_instr = "mulhsu";
		if (instr_mulhu)  new_ascii_instr = "mulhu";

		if (instr_div)    new_ascii_instr = "div";
		if (instr_divu)   new_ascii_instr = "divu";
		if (instr_rem)    new_ascii_instr = "rem";
		if (instr_remu)   new_ascii_instr = "remu";
	end

	// ALU and comparison
	reg [31:0] alu_out;
	reg alu_compare_result;

	reg [31:0] alu_add_sub;
	reg [31:0] alu_shl, alu_shr;
	reg alu_eq, alu_ltu, alu_lts;

	// Arithmetic, shifts, and comparison primitives
	always @* begin
		alu_add_sub = instr_sub ? alu_op1 - alu_op2 : alu_op1 + alu_op2;
		alu_eq = alu_op1 == alu_op2;
		alu_lts = $signed(alu_op1) < $signed(alu_op2);
		alu_ltu = alu_op1 < alu_op2;
		alu_shl = alu_op1 << alu_op2[4:0];
		alu_shr = $signed({instr_sra || instr_srai ? alu_op1[31] : 1'b0, alu_op1}) >>> alu_op2[4:0];
	end

	// Branch and set-less-than conditions
	always @* begin
		alu_compare_result = 'bx;
		// for conditional branch instructions
		case (1'b1)
			instr_beq:
				alu_compare_result = alu_eq;

			instr_bne:
				alu_compare_result = !alu_eq;

			instr_bge:
				alu_compare_result = !alu_lts;

			instr_bgeu:
				alu_compare_result = !alu_ltu;

			instr_slti || instr_blt || instr_slt:
				alu_compare_result = alu_lts;

			instr_sltiu || instr_bltu || instr_sltu:
				alu_compare_result = alu_ltu;
		endcase
	end

	// Final ALU result selection
	always @* begin
		alu_out = 32'bx;

		case (1'b1)
			// Arithmetic and effective address calculation
			instr_lui || instr_auipc ||
			instr_jal || instr_jalr ||
			instr_addi || instr_add || instr_sub ||
			instr_lb || instr_lh || instr_lw ||
			instr_lbu || instr_lhu ||
			instr_sb || instr_sh || instr_sw:
				alu_out = alu_add_sub;

			// Comparison
			instr_beq || instr_bne ||
			instr_blt || instr_bge ||
			instr_bltu || instr_bgeu ||
			instr_slti || instr_sltiu ||
			instr_slt || instr_sltu:
				alu_out = alu_compare_result;

			// Bitwise logic
			instr_xori || instr_xor:
				alu_out = alu_op1 ^ alu_op2;

			instr_ori || instr_or:
				alu_out = alu_op1 | alu_op2;

			instr_andi || instr_and:
				alu_out = alu_op1 & alu_op2;

			// Shift
			instr_slli || instr_sll:
				alu_out = alu_shl;

			instr_srli || instr_srai ||
			instr_srl || instr_sra:
				alu_out = alu_shr;



		endcase
	end

	// Load/store data formatting
	wire [31:0] load_shifted = mem_data >> {alu_out[1:0], 3'b000};

	// Result of load sign/zero extension
	reg [31:0] mem_load_result;

	// Unsupported unaligned accesses are handled by the CPU FSM
	wire data_misaligned =
		((instr_lh || instr_lhu || instr_sh) && alu_out[0]) ||
		((instr_lw || instr_sw) && (alu_out[1:0] != 2'b00));

	always @* begin
		case (1'b1)
			instr_lb:
				mem_load_result = {{24{load_shifted[7]}}, load_shifted[7:0]};

			instr_lbu:
				mem_load_result = {24'b0, load_shifted[7:0]};

			instr_lh:
				mem_load_result = {{16{load_shifted[15]}}, load_shifted[15:0]};

			instr_lhu:
				mem_load_result = {16'b0, load_shifted[15:0]};

			instr_lw:
				mem_load_result = mem_data;

			default:
				mem_load_result = 32'bx;
		endcase
	end

	// for Multiply and Divide instructions
	rv32m_unit u_muldiv (
		.clk         (clk),
		.rst_n       (rst_n),
		.start       (muldiv_start),

		.operand1    (alu_op1),
		.operand2    (alu_op2),

		.instr_mul   (instr_mul),
		.instr_mulh  (instr_mulh),
		.instr_mulhsu(instr_mulhsu),
		.instr_mulhu (instr_mulhu),

		.instr_div   (instr_div),
		.instr_divu  (instr_divu),
		.instr_rem   (instr_rem),
		.instr_remu  (instr_remu),

		.done        (muldiv_done),
		.result      (muldiv_result)
	);


	// CPU execution and register file
	localparam cpu_state_fetch          = 4'd0;
	localparam cpu_state_ld_rs          = 4'd1;
	localparam cpu_state_exec           = 4'd2;
	localparam cpu_state_stmem          = 4'd3;
	localparam cpu_state_ldmem          = 4'd4;
	localparam cpu_state_muldiv         = 4'd5;
	localparam cpu_state_trap           = 4'd6;

	// State and program counters (written by the CPU FSM)
	reg [3:0] cpu_state;
	reg [31:0] current_pc;
	reg [31:0] next_pc;

	// Requests issued by the CPU FSM and consumed by the memory interface
	reg mem_req_instr;
	reg mem_req_load;
	reg mem_req_store;

	// ALU operands and store data (registered in the CPU FSM)
	reg [31:0] alu_op1, alu_op2;
	reg [31:0] mem_store_data;

	// Register file
	reg [31:0] cpuregs [0:31];
	wire [31:0] cpuregs_rs1 = decoded_rs1 ? cpuregs[decoded_rs1] : 0;
	wire [31:0] cpuregs_rs2 = decoded_rs2 ? cpuregs[decoded_rs2] : 0;

	// for Multiply and Divide
	reg         muldiv_start;
	wire        muldiv_done;
	wire [31:0] muldiv_result;

	// Register file reset loop index
	integer i;

	always @(posedge clk) begin
		if (!rst_n) begin
			current_pc <= 32'b0;
			next_pc <= 32'b0;

			cpu_state <= cpu_state_fetch;

			mem_req_instr <= 0;
			mem_req_load <= 0;
			mem_req_store <= 0;
			mem_store_data <= 32'b0;

			for (i = 0; i < 32; i = i + 1) begin
				cpuregs[i] <= 32'd0;
			end

			muldiv_start <= 0;
		end else begin
			case (cpu_state)
				cpu_state_fetch: begin
					if (!mem_req_instr) begin
						mem_req_instr <= 1;
						current_pc <= next_pc;
					end

					// this means having fetched instruction
					if ((mem_xfer & mem_req_instr)) begin
						mem_req_instr <= 0;
						cpu_state <= cpu_state_ld_rs;
					end
				end

				cpu_state_ld_rs: begin
					if (decoder_done) begin

						next_pc <= current_pc + 32'd4;

						case (1'b1)

							// LUI, AUIPC, JAL
							// Operand 1: zero or PC
							// Operand 2: immediate
							instr_lui || instr_auipc || instr_jal: begin
								alu_op1 <= instr_lui ? 32'd0 : current_pc;
								alu_op2 <= decoded_imm;
								cpu_state <= cpu_state_exec;
							end

							// JALR and ALU immediate instructions
							// Operand 1: rs1
							// Operand 2: immediate
							instr_jalr ||
							instr_addi || instr_slti || instr_sltiu ||
							instr_xori || instr_ori || instr_andi: begin
								alu_op1 <= cpuregs_rs1;
								alu_op2 <= decoded_imm;
								cpu_state <= cpu_state_exec;
							end

							// Shift immediate instructions
							// Operand 1: rs1
							// Operand 2: 5-bit shift amount
							instr_slli || instr_srli || instr_srai: begin
								alu_op1 <= cpuregs_rs1;
								alu_op2 <= {27'b0, decoded_rs2};
								cpu_state <= cpu_state_exec;
							end

							// Load instructions
							// Effective address = rs1 + immediate
							instr_lb || instr_lh || instr_lw ||
							instr_lbu || instr_lhu: begin
								alu_op1 <= cpuregs_rs1;
								alu_op2 <= decoded_imm;
								cpu_state <= cpu_state_ldmem;
							end

							// Store instructions
							// Effective address = rs1 + immediate
							// Store data = rs2
							instr_sb || instr_sh || instr_sw: begin
								alu_op1 <= cpuregs_rs1;
								alu_op2 <= decoded_imm;
								mem_store_data <= cpuregs_rs2;
								cpu_state <= cpu_state_stmem;
							end

							// R-type ALU instructions and conditional branches
							// Operand 1: rs1
							// Operand 2: rs2
							instr_add || instr_sub ||
							instr_sll || instr_slt || instr_sltu ||
							instr_xor || instr_srl || instr_sra ||
							instr_or || instr_and ||
							instr_beq || instr_bne ||
							instr_blt || instr_bge ||
							instr_bltu || instr_bgeu: begin
								alu_op1 <= cpuregs_rs1;
								alu_op2 <= cpuregs_rs2;
								cpu_state <= cpu_state_exec;
							end

							// FENCE: NOP in the current memory architecture
							instr_fence: begin
								cpu_state <= cpu_state_fetch;
							end

							// RV32M - Multiplication / Division
							instr_mul || instr_mulh || instr_mulhsu || instr_mulhu ||
							instr_div || instr_divu || instr_rem || instr_remu: begin
								alu_op1 <= cpuregs_rs1;
								alu_op2 <= cpuregs_rs2;
								muldiv_start <= 1'b1;
								cpu_state <= cpu_state_muldiv;
							end

							// Illegal or unsupported instruction
							default: begin
								cpu_state <= cpu_state_trap;
							end

						endcase
					end
				end

				cpu_state_exec: begin
					case (1'b1)
						// LUI, AUIPC, ALU arithmetic, logic, compare, shift
						instr_lui || instr_auipc ||
						instr_addi || instr_slti || instr_sltiu ||
						instr_xori || instr_ori || instr_andi ||
						instr_slli || instr_srli || instr_srai ||
						instr_add || instr_sub || instr_sll ||
						instr_slt || instr_sltu || instr_xor ||
						instr_srl || instr_sra || instr_or || instr_and: begin

							if (decoded_rd != 5'd0)
								cpuregs[decoded_rd] <= alu_out;

							cpu_state <= cpu_state_fetch;
						end

						// JAL
						instr_jal: begin
							if (alu_out[1:0] != 2'b00) begin
								cpu_state <= cpu_state_trap;
							end else begin
								if (decoded_rd != 5'd0)
									cpuregs[decoded_rd] <= current_pc + 32'd4;

								next_pc <= alu_out;
								cpu_state <= cpu_state_fetch;
							end
						end

						// JALR
						instr_jalr: begin
							// COMPRESSED_ISA isn't supported now
							if (alu_out[1]) begin
								cpu_state <= cpu_state_trap;
							end else begin
								if (decoded_rd != 5'd0)
									cpuregs[decoded_rd] <= current_pc + 32'd4;

								next_pc <= alu_out & 32'hfffffffe;
								cpu_state <= cpu_state_fetch;
							end
						end

						// Conditional Branch
						instr_beq || instr_bne ||
						instr_blt || instr_bge ||
						instr_bltu || instr_bgeu: begin

							if (alu_compare_result) begin
								if ((current_pc + decoded_imm) & 32'h2)
									cpu_state <= cpu_state_trap;
								else begin
									next_pc <= current_pc + decoded_imm;
									cpu_state <= cpu_state_fetch;
								end
							end else begin
								cpu_state <= cpu_state_fetch;
							end
						end

						// Illegal / Unsupported Instruction
						default: begin
							cpu_state <= cpu_state_trap;
						end
					endcase
				end

				cpu_state_ldmem: begin
					if (data_misaligned) begin
						cpu_state <= cpu_state_trap;
					end else begin
						// Request a data read
						if (!mem_req_load) begin
							mem_req_load <= 1'b1;
						end

						// Memory read completed
						if (mem_xfer && mem_req_load) begin
							mem_req_load <= 1'b0;

							if (decoded_rd != 5'd0) begin
								cpuregs[decoded_rd] <= mem_load_result;
							end

							cpu_state <= cpu_state_fetch;
						end
					end
				end

				cpu_state_stmem: begin
					if (data_misaligned) begin
						cpu_state <= cpu_state_trap;
					end else begin
						// Request a data write
						if (!mem_req_store) begin
							mem_req_store <= 1'b1;
						end

						// Memory write completed
						if (mem_xfer && mem_req_store) begin
							mem_req_store <= 1'b0;
							cpu_state <= cpu_state_fetch;
						end
					end
				end

				cpu_state_muldiv: begin
					muldiv_start <= 1'b0;

					if (muldiv_done) begin
						if (decoded_rd != 5'd0) begin
							cpuregs[decoded_rd] <= muldiv_result;
						end

						cpu_state <= cpu_state_fetch;
					end
				end

				cpu_state_trap: begin
					mem_req_instr <= 0;
					mem_req_load <= 0;
					mem_req_store <= 0;
					cpu_state <= cpu_state_trap;
				end
			endcase
		end
	end

endmodule
