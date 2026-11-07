// Arty A7 board wrapper: 100 MHz oscillator -> Clocking Wizard -> 80 MHz SoC.
// Uses clk_wiz_0 with active-low resetn, matching the generated IP interface.
// For a new project, create it with scripts/create_clocking_wizard.tcl.
// Top-level port names match the existing Arty-A7-100-Master.xdc constraints.
module arty_a7_top (
	input  wire clk,
	input  wire rst_n,
	input  wire uart_rx,
	output wire uart_tx
);
	wire clk_80mhz;
	wire clock_locked;

	clk_wiz_0 u_clock (
		.clk_in1(clk),
		.resetn(rst_n),
		.clk_out1(clk_80mhz),
		.locked(clock_locked)
	);

	// Assert reset immediately on button reset or loss of clock lock.
	// Release it only after two rising edges of the stable 80 MHz clock.
	wire clock_ready = rst_n && clock_locked;
	(* ASYNC_REG = "TRUE" *) reg reset_meta_n = 1'b0;
	(* ASYNC_REG = "TRUE" *) reg reset_sync_n = 1'b0;

	always @(posedge clk_80mhz or negedge clock_ready) begin
		if (!clock_ready) begin
			reset_meta_n <= 1'b0;
			reset_sync_n <= 1'b0;
		end else begin
			reset_meta_n <= 1'b1;
			reset_sync_n <= reset_meta_n;
		end
	end

	soc_top u_soc (
		.clk(clk_80mhz),
		.rst_n(reset_sync_n),
		.uart_rx(uart_rx),
		.uart_tx(uart_tx)
	);
endmodule
