// Decode the CPU's native WORD address into either BRAM or AXI UART.
// BRAM: 0x0000_0000 - 0x0003_FFFF (256 KiB)
// UART: 0x1000_0000 - 0x1000_0FFF (4 KiB window)
// Timer:0x1000_1000 - 0x1000_1FFF RESERVED (currently unmapped)
// Unmapped accesses complete with mem_error=1, mem_rdata=0.
// IMPORTANT: current cpu_core has NO error input. Connect mem_error to
// simulation/debug; add a CPU trap/error interface when required later.
module mem_interconnect (
	// CPU native memory interface
	input  wire        mem_valid,
	output wire        mem_ready,
	input  wire [29:0] mem_addr,
	input  wire [31:0] mem_wdata,
	input  wire [3:0]  mem_wstrb,
	output wire [31:0] mem_rdata,
	output wire        mem_error,

	// Existing BRAM native interface
	output wire        bram_valid,
	input  wire        bram_ready,
	output wire [29:0] bram_addr,
	output wire [31:0] bram_wdata,
	output wire [3:0]  bram_wstrb,
	input  wire [31:0] bram_rdata,

	// AXI master native request interface
	output wire        axi_valid,
	input  wire        axi_ready,
	output wire [29:0] axi_addr,
	output wire [31:0] axi_wdata,
	output wire [3:0]  axi_wstrb,
	input  wire [31:0] axi_rdata,
	input  wire        axi_error
);

	// CPU addresses are WORD addresses, so these tests correspond to:
	// BRAM [byte 31:18] == 0, UART [byte 31:12] == 0x10000.
	wire select_bram = (mem_addr[29:16] == 14'b0);
	wire select_uart = (mem_addr[29:10] == 20'h10000);
	wire unmapped    = !select_bram && !select_uart;

	assign bram_valid = mem_valid && select_bram;
	assign bram_addr  = mem_addr;
	assign bram_wdata = mem_wdata;
	assign bram_wstrb = mem_wstrb;

	assign axi_valid = mem_valid && select_uart;
	assign axi_addr  = mem_addr;
	assign axi_wdata = mem_wdata;
	assign axi_wstrb = mem_wstrb;

	assign mem_ready = mem_valid && (
		select_bram ? bram_ready :
		select_uart ? axi_ready  :
		1'b1 // unmapped: return an error completion; do not hang CPU
	);

	assign mem_rdata = select_bram ? bram_rdata : select_uart ? axi_rdata  : 32'b0;

	assign mem_error = mem_valid && (
		unmapped || (select_uart && axi_ready && axi_error)
	);

endmodule
