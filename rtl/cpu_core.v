module cpu_core (
    input wire          rst_n,
    input wire          clk,

    input wire          mem_ready,
    input wire [31:0]   mem_data,
    output reg          mem_valid,
    output reg [29:0]   mem_addr   // aligned to 4 bytes
);
 
    localparam MEM_IDLE = 2'b01;
    localparam MEM_WAIT = 2'b10;

    // fsm
    reg [1:0] mem_state;
    reg [2:0] cpu_state;

    // memory operation from fetch module
    reg mem_do_rinst;
    reg mem_do_rdata;
    reg mem_do_wdata;

    wire mem_xfer;
    assign mem_xfer = mem_ready & mem_valid;

    reg [31:0] mem_data_q;


    // pc
    reg [29:0] current_pc;
    reg first_ins;


    // memory interface
    always @(posedge clk) begin
        if (!rst_n) begin
            mem_state <= MEM_IDLE;
            mem_valid <= 1'b0;
            mem_addr <= 30'b0;
        end else begin
            case (mem_state)
                MEM_IDLE: begin
                    if (mem_do_rinst) begin
                        mem_valid <= 1'b1;
                        mem_state <= MEM_WAIT;
                        mem_addr <= current_pc;
                    end
                end
                MEM_WAIT: begin
                    if (mem_xfer) begin
                        mem_data_q <= mem_data;
                        mem_valid <= 0;
                        mem_state <= MEM_IDLE;
                        $display("memory data: %08h", mem_data);
                    end
                end
            endcase
        end
    end


    reg decoder_1_stage;
    reg decoder_done;

    reg instr_lui, instr_auipc, instr_jal, instr_jalr;
	reg instr_beq, instr_bne, instr_blt, instr_bge, instr_bltu, instr_bgeu;
	reg instr_lb, instr_lh, instr_lw, instr_lbu, instr_lhu, instr_sb, instr_sh, instr_sw;
	reg instr_addi, instr_slti, instr_sltiu, instr_xori, instr_ori, instr_andi, instr_slli, instr_srli, instr_srai;
	reg instr_add, instr_sub, instr_sll, instr_slt, instr_sltu, instr_xor, instr_srl, instr_sra, instr_or, instr_and;
	reg instr_rdcycle, instr_rdcycleh, instr_rdinstr, instr_rdinstrh, instr_ecall_ebreak, instr_fence;
	reg instr_getq, instr_setq, instr_retirq, instr_maskirq, instr_waitirq, instr_timer;
	//wire instr_trap;

	reg [4:0] decoded_rd, decoded_rs1;
	reg [4:0] decoded_rs2;
	reg [31:0] decoded_imm, decoded_imm_j;

	reg is_lui_auipc_jal;
	reg is_lb_lh_lw_lbu_lhu;
	reg is_slli_srli_srai;
	reg is_jalr_addi_slti_sltiu_xori_ori_andi;
	reg is_sb_sh_sw;
	reg is_sll_srl_sra;
	reg is_lui_auipc_jal_jalr_addi_add_sub;
	reg is_slti_blt_slt;
	reg is_sltiu_bltu_sltu;
	reg is_beq_bne_blt_bge_bltu_bgeu;
	reg is_lbu_lhu_lw;
	reg is_alu_reg_imm;
	reg is_alu_reg_reg;
	reg is_compare;


    // decorder module
    always @(posedge clk) begin
        if (!rst_n) begin
            decoder_1_stage <= 0;
            decoder_done <= 0;

            is_beq_bne_blt_bge_bltu_bgeu <= 0;
            is_compare <= 0;

            instr_beq   <= 0;
            instr_bne   <= 0;
            instr_blt   <= 0;
            instr_bge   <= 0;
            instr_bltu  <= 0;
            instr_bgeu  <= 0;

            instr_addi  <= 0;
            instr_slti  <= 0;
            instr_sltiu <= 0;
            instr_xori  <= 0;
            instr_ori   <= 0;
            instr_andi  <= 0;

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

        end else begin
            decoder_done <= 0;

            // this is 1-st decode stage
            if (mem_xfer & mem_do_rinst) begin
                decoder_1_stage <= 1;

                instr_lui     <= mem_data[6:0] == 7'b0110111;
                instr_auipc   <= mem_data[6:0] == 7'b0010111;
                instr_jal     <= mem_data[6:0] == 7'b1101111;
                instr_jalr    <= mem_data[6:0] == 7'b1100111 && mem_data[14:12] == 3'b000;
                //instr_retirq  <= mem_data[6:0] == 7'b0001011 && mem_data[31:25] == 7'b0000010 && ENABLE_IRQ;
                //instr_waitirq <= mem_data[6:0] == 7'b0001011 && mem_data[31:25] == 7'b0000100 && ENABLE_IRQ;

                is_beq_bne_blt_bge_bltu_bgeu <= mem_data[6:0] == 7'b1100011;
                is_lb_lh_lw_lbu_lhu          <= mem_data[6:0] == 7'b0000011;
                is_sb_sh_sw                  <= mem_data[6:0] == 7'b0100011;
                is_alu_reg_imm               <= mem_data[6:0] == 7'b0010011;
                is_alu_reg_reg               <= mem_data[6:0] == 7'b0110011;

                // this is for U-type
                { decoded_imm_j[31:20], decoded_imm_j[10:1], decoded_imm_j[11], decoded_imm_j[19:12], decoded_imm_j[0] } <= $signed({mem_data[31:12], 1'b0});

                decoded_rd <= mem_data[11:7];
                decoded_rs1 <= mem_data[19:15];
                decoded_rs2 <= mem_data[24:20];

                // if (mem_data[6:0] == 7'b0001011 && mem_data[31:25] == 7'b0000000 && ENABLE_IRQ && ENABLE_IRQ_QREGS)
                // 	decoded_rs1[regindex_bits-1] <= 1; // instr_getq

                // if (mem_data[6:0] == 7'b0001011 && mem_data[31:25] == 7'b0000010 && ENABLE_IRQ)
                // 	decoded_rs1 <= ENABLE_IRQ_QREGS ? irqregs_offset : 3; // instr_retirq
            end


            // this is 2-nd decode stage
            if (decoder_1_stage) begin
                decoder_1_stage <= 0;
                decoder_done <= 1;

                instr_beq   <= is_beq_bne_blt_bge_bltu_bgeu && mem_data_q[14:12] == 3'b000;
                instr_bne   <= is_beq_bne_blt_bge_bltu_bgeu && mem_data_q[14:12] == 3'b001;
                instr_blt   <= is_beq_bne_blt_bge_bltu_bgeu && mem_data_q[14:12] == 3'b100;
                instr_bge   <= is_beq_bne_blt_bge_bltu_bgeu && mem_data_q[14:12] == 3'b101;
                instr_bltu  <= is_beq_bne_blt_bge_bltu_bgeu && mem_data_q[14:12] == 3'b110;
                instr_bgeu  <= is_beq_bne_blt_bge_bltu_bgeu && mem_data_q[14:12] == 3'b111;

                instr_lb    <= is_lb_lh_lw_lbu_lhu && mem_data_q[14:12] == 3'b000;
                instr_lh    <= is_lb_lh_lw_lbu_lhu && mem_data_q[14:12] == 3'b001;
                instr_lw    <= is_lb_lh_lw_lbu_lhu && mem_data_q[14:12] == 3'b010;
                instr_lbu   <= is_lb_lh_lw_lbu_lhu && mem_data_q[14:12] == 3'b100;
                instr_lhu   <= is_lb_lh_lw_lbu_lhu && mem_data_q[14:12] == 3'b101;

                instr_sb    <= is_sb_sh_sw && mem_data_q[14:12] == 3'b000;
                instr_sh    <= is_sb_sh_sw && mem_data_q[14:12] == 3'b001;
                instr_sw    <= is_sb_sh_sw && mem_data_q[14:12] == 3'b010;

                instr_addi  <= is_alu_reg_imm && mem_data_q[14:12] == 3'b000;
                instr_slti  <= is_alu_reg_imm && mem_data_q[14:12] == 3'b010;
                instr_sltiu <= is_alu_reg_imm && mem_data_q[14:12] == 3'b011;
                instr_xori  <= is_alu_reg_imm && mem_data_q[14:12] == 3'b100;
                instr_ori   <= is_alu_reg_imm && mem_data_q[14:12] == 3'b110;
                instr_andi  <= is_alu_reg_imm && mem_data_q[14:12] == 3'b111;

                instr_slli  <= is_alu_reg_imm && mem_data_q[14:12] == 3'b001 && mem_data_q[31:25] == 7'b0000000;
                instr_srli  <= is_alu_reg_imm && mem_data_q[14:12] == 3'b101 && mem_data_q[31:25] == 7'b0000000;
                instr_srai  <= is_alu_reg_imm && mem_data_q[14:12] == 3'b101 && mem_data_q[31:25] == 7'b0100000;

                instr_add   <= is_alu_reg_reg && mem_data_q[14:12] == 3'b000 && mem_data_q[31:25] == 7'b0000000;
                instr_sub   <= is_alu_reg_reg && mem_data_q[14:12] == 3'b000 && mem_data_q[31:25] == 7'b0100000;
                instr_sll   <= is_alu_reg_reg && mem_data_q[14:12] == 3'b001 && mem_data_q[31:25] == 7'b0000000;
                instr_slt   <= is_alu_reg_reg && mem_data_q[14:12] == 3'b010 && mem_data_q[31:25] == 7'b0000000;
                instr_sltu  <= is_alu_reg_reg && mem_data_q[14:12] == 3'b011 && mem_data_q[31:25] == 7'b0000000;
                instr_xor   <= is_alu_reg_reg && mem_data_q[14:12] == 3'b100 && mem_data_q[31:25] == 7'b0000000;
                instr_srl   <= is_alu_reg_reg && mem_data_q[14:12] == 3'b101 && mem_data_q[31:25] == 7'b0000000;
                instr_sra   <= is_alu_reg_reg && mem_data_q[14:12] == 3'b101 && mem_data_q[31:25] == 7'b0100000;
                instr_or    <= is_alu_reg_reg && mem_data_q[14:12] == 3'b110 && mem_data_q[31:25] == 7'b0000000;
                instr_and   <= is_alu_reg_reg && mem_data_q[14:12] == 3'b111 && mem_data_q[31:25] == 7'b0000000;

                // instr_rdcycle  <= ((mem_data_q[6:0] == 7'b1110011 && mem_data_q[31:12] == 'b11000000000000000010) ||
                //                 (mem_data_q[6:0] == 7'b1110011 && mem_data_q[31:12] == 'b11000000000100000010)) && ENABLE_COUNTERS;
                // instr_rdcycleh <= ((mem_data_q[6:0] == 7'b1110011 && mem_data_q[31:12] == 'b11001000000000000010) ||
                //                 (mem_data_q[6:0] == 7'b1110011 && mem_data_q[31:12] == 'b11001000000100000010)) && ENABLE_COUNTERS && ENABLE_COUNTERS64;
                // instr_rdinstr  <=  (mem_data_q[6:0] == 7'b1110011 && mem_data_q[31:12] == 'b11000000001000000010) && ENABLE_COUNTERS;
                // instr_rdinstrh <=  (mem_data_q[6:0] == 7'b1110011 && mem_data_q[31:12] == 'b11001000001000000010) && ENABLE_COUNTERS && ENABLE_COUNTERS64;

                // instr_ecall_ebreak <= ((mem_data_q[6:0] == 7'b1110011 && !mem_data_q[31:21] && !mem_data_q[19:7]) ||
                //         (COMPRESSED_ISA && mem_data_q[15:0] == 16'h9002));
                instr_fence <= (mem_data_q[6:0] == 7'b0001111 && !mem_data_q[14:12]);

                // instr_getq    <= mem_data_q[6:0] == 7'b0001011 && mem_data_q[31:25] == 7'b0000000 && ENABLE_IRQ && ENABLE_IRQ_QREGS;
                // instr_setq    <= mem_data_q[6:0] == 7'b0001011 && mem_data_q[31:25] == 7'b0000001 && ENABLE_IRQ && ENABLE_IRQ_QREGS;
                // instr_maskirq <= mem_data_q[6:0] == 7'b0001011 && mem_data_q[31:25] == 7'b0000011 && ENABLE_IRQ;
                // instr_timer   <= mem_data_q[6:0] == 7'b0001011 && mem_data_q[31:25] == 7'b0000101 && ENABLE_IRQ && ENABLE_IRQ_TIMER;

                is_slli_srli_srai <= is_alu_reg_imm && |{
                    mem_data_q[14:12] == 3'b001 && mem_data_q[31:25] == 7'b0000000,
                    mem_data_q[14:12] == 3'b101 && mem_data_q[31:25] == 7'b0000000,
                    mem_data_q[14:12] == 3'b101 && mem_data_q[31:25] == 7'b0100000
                };

                is_jalr_addi_slti_sltiu_xori_ori_andi <= instr_jalr || is_alu_reg_imm && |{
                    mem_data_q[14:12] == 3'b000,
                    mem_data_q[14:12] == 3'b010,
                    mem_data_q[14:12] == 3'b011,
                    mem_data_q[14:12] == 3'b100,
                    mem_data_q[14:12] == 3'b110,
                    mem_data_q[14:12] == 3'b111
                };

                is_sll_srl_sra <= is_alu_reg_reg && |{
                    mem_data_q[14:12] == 3'b001 && mem_data_q[31:25] == 7'b0000000,
                    mem_data_q[14:12] == 3'b101 && mem_data_q[31:25] == 7'b0000000,
                    mem_data_q[14:12] == 3'b101 && mem_data_q[31:25] == 7'b0100000
                };

                is_lui_auipc_jal_jalr_addi_add_sub <= 0;
                is_compare <= 0;

                (* parallel_case *)
                case (1'b1)
                    instr_jal:
                        decoded_imm <= decoded_imm_j;
                    |{instr_lui, instr_auipc}:
                        decoded_imm <= mem_data_q[31:12] << 12;
                    |{instr_jalr, is_lb_lh_lw_lbu_lhu, is_alu_reg_imm}:
                        decoded_imm <= $signed(mem_data_q[31:20]);
                    is_beq_bne_blt_bge_bltu_bgeu:
                        decoded_imm <= $signed({mem_data_q[31], mem_data_q[7], mem_data_q[30:25], mem_data_q[11:8], 1'b0});
                    is_sb_sh_sw:
                        decoded_imm <= $signed({mem_data_q[31:25], mem_data_q[11:7]});
                    default:
                        decoded_imm <= 1'bx;
                endcase

            end
        end
    end

    // decoder debug module
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

		if (instr_rdcycle)  new_ascii_instr = "rdcycle";
		if (instr_rdcycleh) new_ascii_instr = "rdcycleh";
		if (instr_rdinstr)  new_ascii_instr = "rdinstr";
		if (instr_rdinstrh) new_ascii_instr = "rdinstrh";
		if (instr_fence)    new_ascii_instr = "fence";

		if (instr_getq)     new_ascii_instr = "getq";
		if (instr_setq)     new_ascii_instr = "setq";
		if (instr_retirq)   new_ascii_instr = "retirq";
		if (instr_maskirq)  new_ascii_instr = "maskirq";
		if (instr_waitirq)  new_ascii_instr = "waitirq";
		if (instr_timer)    new_ascii_instr = "timer";
	end



	// localparam cpu_state_trap   = 8'b10000000;
	localparam cpu_state_fetch  = 3'd0;
	localparam cpu_state_ld_rs1 = 3'd1;
	localparam cpu_state_ld_rs2 = 3'd2;
	localparam cpu_state_exec   = 3'd3;
	// localparam cpu_state_shift  = 8'b00000100;
	// localparam cpu_state_stmem  = 8'b00000010;
	// localparam cpu_state_ldmem  = 8'b00000001;

    // cpu module
    // fetch + exec
    always @(posedge clk) begin
        if (!rst_n) begin
            current_pc <= 30'b0;
            cpu_state <= cpu_state_fetch;
            mem_do_rinst <= 0;
            first_ins <= 1;
        end else begin
            case (cpu_state)
                cpu_state_fetch: begin
                    if (!mem_do_rinst) begin
                        mem_do_rinst <= 1;
                        first_ins <= 0;

                        if (first_ins) begin
                            current_pc <= 0;
                        end else begin
                            current_pc <= current_pc + 1;
                        end
                    end

                    // todo, add branch write-back

                    if ((mem_xfer & mem_do_rinst)) begin
                        mem_do_rinst <= 0;
                        cpu_state <= cpu_state_ld_rs1;
                    end
                end

                cpu_state_ld_rs1: begin
                    // make sure cpu_state_ld_rs1 happen after fully decoding
                    if (decoder_done) begin
                        cpu_state <= cpu_state_fetch;
                    end

                end
            endcase
        end
    end



endmodule

