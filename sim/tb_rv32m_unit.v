`timescale 1ns / 1ps

module tb_rv32m_unit;
	reg clk = 1'b0;
	always #5 clk = ~clk;

	reg rst_n = 1'b0;
	reg start = 1'b0;
	reg [31:0] operand1 = 32'b0;
	reg [31:0] operand2 = 32'b0;
	reg instr_mul = 1'b0;
	reg instr_mulh = 1'b0;
	reg instr_mulhsu = 1'b0;
	reg instr_mulhu = 1'b0;
	reg instr_div = 1'b0;
	reg instr_divu = 1'b0;
	reg instr_rem = 1'b0;
	reg instr_remu = 1'b0;
	wire done;
	wire [31:0] result;

	rv32m_unit dut (
		.clk(clk), .rst_n(rst_n), .start(start),
		.operand1(operand1), .operand2(operand2),
		.instr_mul(instr_mul), .instr_mulh(instr_mulh),
		.instr_mulhsu(instr_mulhsu), .instr_mulhu(instr_mulhu),
		.instr_div(instr_div), .instr_divu(instr_divu),
		.instr_rem(instr_rem), .instr_remu(instr_remu),
		.done(done), .result(result)
	);

	integer checked = 0;

	// Operation numbers match RV32M funct3 values.
	task run_case;
		input [2:0]  op;
		input [31:0] a;
		input [31:0] b;
		input [31:0] expected;
		integer cycles;
		begin
			@(negedge clk);
			operand1 = a;
			operand2 = b;
			{instr_remu, instr_rem, instr_divu, instr_div,
			 instr_mulhu, instr_mulhsu, instr_mulh, instr_mul} = 8'b1 << op;
			start = 1'b1;

			@(negedge clk);
			start = 1'b0;
			cycles = 0;
			while (done !== 1'b1 && cycles < 40) begin
				@(negedge clk);
				cycles = cycles + 1;
			end

			if (done !== 1'b1)
				$fatal(1, "RV32M timeout op=%0d a=%h b=%h", op, a, b);
			if (result !== expected)
				$fatal(1, "RV32M FAIL op=%0d a=%h b=%h expected=%h got=%h",
				       op, a, b, expected, result);

			checked = checked + 1;
			$display("PASS op=%0d a=%h b=%h result=%h cycles=%0d",
			         op, a, b, result, cycles + 1);
		end
	endtask

	initial begin
		repeat (5) @(negedge clk);
		rst_n = 1'b1;

		run_case(3'd0, 32'hffffffff, 32'h00000002, 32'hfffffffe); // MUL
		run_case(3'd1, 32'h80000000, 32'h00000002, 32'hffffffff); // MULH
		run_case(3'd2, 32'hffffffff, 32'hffffffff, 32'hffffffff); // MULHSU
		run_case(3'd3, 32'hffffffff, 32'hffffffff, 32'hfffffffe); // MULHU
		run_case(3'd4, 32'hfffffff9, 32'h00000003, 32'hfffffffe); // DIV -7/3
		run_case(3'd5, 32'hffffffff, 32'h00000002, 32'h7fffffff); // DIVU
		run_case(3'd6, 32'hfffffff9, 32'h00000003, 32'hffffffff); // REM -7%3
		run_case(3'd7, 32'hffffffff, 32'h00000002, 32'h00000001); // REMU

		// Division by zero: quotient = all ones; remainder = dividend.
		run_case(3'd4, 32'hfffffff9, 32'h00000000, 32'hffffffff);
		run_case(3'd5, 32'h00000007, 32'h00000000, 32'hffffffff);
		run_case(3'd6, 32'hfffffff9, 32'h00000000, 32'hfffffff9);
		run_case(3'd7, 32'h00000007, 32'h00000000, 32'h00000007);

		// Signed overflow: INT_MIN / -1 and INT_MIN % -1.
		run_case(3'd4, 32'h80000000, 32'hffffffff, 32'h80000000);
		run_case(3'd6, 32'h80000000, 32'hffffffff, 32'h00000000);

		$display("PASS: %0d RV32M unit test cases", checked);
		$finish;
	end
endmodule
