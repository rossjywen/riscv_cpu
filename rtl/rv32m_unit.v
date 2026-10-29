// -----------------------------------------------------------------------------
// RV32M - Integer multiply/divide execution unit
// -----------------------------------------------------------------------------
// Supported: MUL, MULH, MULHSU, MULHU, DIV, DIVU, REM, REMU
//
// Interface:
//   start  : one-clock pulse; instruction flags and operands valid at this edge
//   done   : one-clock pulse; result is valid when done is high
//   result : 32-bit value to write into rd
//
// One operation at a time. The CPU must wait for done before issuing another.
// Multiplication uses the synthesis tool's multiplier; division uses 32 steps.
// -----------------------------------------------------------------------------
module rv32m_unit (
	input  wire        clk,
	input  wire        rst_n,
	input  wire        start,
	input  wire [31:0] operand1,
	input  wire [31:0] operand2,

	input  wire        instr_mul,
	input  wire        instr_mulh,
	input  wire        instr_mulhsu,
	input  wire        instr_mulhu,
	input  wire        instr_div,
	input  wire        instr_divu,
	input  wire        instr_rem,
	input  wire        instr_remu,

	output reg         done,
	output reg  [31:0] result
);

	// -------------------------------------------------------------------------
	// Multiplier
	// -------------------------------------------------------------------------
	// Extra sign bit allows signed and unsigned operands to share one multiplier.
	wire signed [32:0] mul_operand1 = {
		(instr_mulh || instr_mulhsu) && operand1[31], operand1
	};
	wire signed [32:0] mul_operand2 = {
		instr_mulh && operand2[31], operand2
	};
	wire signed [65:0] mul_product = mul_operand1 * mul_operand2;

	// -------------------------------------------------------------------------
	// Divider: unsigned restoring division with signed input/output correction
	// -------------------------------------------------------------------------
	reg         div_busy;
	reg [5:0]   div_step;
	reg [31:0]  div_divisor;
	reg [31:0]  div_quotient;
	reg [32:0]  div_remainder;
	reg         div_return_remainder;
	reg         div_negate_quotient;
	reg         div_negate_remainder;

	wire div_signed = instr_div || instr_rem;
	wire [31:0] div_abs_op1 = div_signed && operand1[31]
		? (~operand1 + 32'd1) : operand1;
	wire [31:0] div_abs_op2 = div_signed && operand2[31]
		? (~operand2 + 32'd1) : operand2;

	// One quotient bit is calculated per clock while div_busy is asserted.
	wire [32:0] div_trial_remainder = {div_remainder[31:0], div_quotient[31]};
	wire div_subtract = div_trial_remainder >= {1'b0, div_divisor};
	wire [32:0] div_next_remainder = div_subtract
		? div_trial_remainder - {1'b0, div_divisor}
		: div_trial_remainder;
	wire [31:0] div_next_quotient = {div_quotient[30:0], div_subtract};

	// -------------------------------------------------------------------------
	// Operation controller and result register
	// -------------------------------------------------------------------------
	always @(posedge clk) begin
		if (!rst_n) begin
			done <= 1'b0;
			result <= 32'b0;
			div_busy <= 1'b0;
			div_step <= 6'd0;
			div_divisor <= 32'b0;
			div_quotient <= 32'b0;
			div_remainder <= 33'b0;
			div_return_remainder <= 1'b0;
			div_negate_quotient <= 1'b0;
			div_negate_remainder <= 1'b0;
		end else begin
			done <= 1'b0;

			if (start && !div_busy) begin
				if (instr_mul || instr_mulh || instr_mulhsu || instr_mulhu) begin
					result <= instr_mul ? mul_product[31:0] : mul_product[63:32];
					done <= 1'b1;
				end else if (instr_div || instr_divu || instr_rem || instr_remu) begin
					if (operand2 == 32'b0) begin
						// RISC-V: division by zero never raises a trap.
						result <= (instr_rem || instr_remu) ? operand1 : 32'hffffffff;
						done <= 1'b1;
					end else if (div_signed && operand1 == 32'h80000000 &&
					             operand2 == 32'hffffffff) begin
						// RISC-V: signed overflow (INT_MIN / -1).
						result <= instr_rem ? 32'b0 : 32'h80000000;
						done <= 1'b1;
					end else begin
						div_busy <= 1'b1;
						div_step <= 6'd0;
						div_divisor <= div_abs_op2;
						div_quotient <= div_abs_op1;
						div_remainder <= 33'b0;
						div_return_remainder <= instr_rem || instr_remu;
						div_negate_quotient <= div_signed && (operand1[31] ^ operand2[31]);
						div_negate_remainder <= div_signed && operand1[31];
					end
				end
			end else if (div_busy) begin
				div_quotient <= div_next_quotient;
				div_remainder <= div_next_remainder;
				div_step <= div_step + 6'd1;

				if (div_step == 6'd31) begin
					div_busy <= 1'b0;
					done <= 1'b1;
					if (div_return_remainder)
						result <= div_negate_remainder
							? -div_next_remainder[31:0] : div_next_remainder[31:0];
					else
						result <= div_negate_quotient
							? -div_next_quotient : div_next_quotient;
				end
			end
		end
	end
endmodule
