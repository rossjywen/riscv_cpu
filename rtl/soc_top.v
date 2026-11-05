// RV32IM SoC top: CPU + BRAM + AXI4-Lite + AXI UART Lite.
// Generate axi_uartlite_0 IP in Vivado before synthesis.
// Check the generated IP instantiation template for address-port widths.
// All blocks are clocked from the SAME clock. Reset is active-low.
module soc_top (
	input  wire clk,
	input  wire rst_n,
	input  wire uart_rx,
	output wire uart_tx
);
	wire        mem_error_debug; // Unused by current CPU; visible in simulation.
	wire        cpu_mem_valid, cpu_mem_ready;
	wire [29:0] cpu_mem_addr;
	wire [31:0] cpu_mem_wdata, cpu_mem_rdata;
	wire [3:0]  cpu_mem_wstrb;

	wire        bram_valid, bram_ready;
	wire [29:0] bram_addr;
	wire [31:0] bram_wdata, bram_rdata;
	wire [3:0]  bram_wstrb;

	wire        axi_valid, axi_ready, axi_error;
	wire [29:0] axi_addr;
	wire [31:0] axi_wdata, axi_rdata;
	wire [3:0]  axi_wstrb;

	wire [31:0] awaddr, araddr, wdata, rdata;
	wire [3:0]  wstrb;
	wire [2:0]  awprot, arprot;
	wire [1:0]  bresp, rresp;
	wire awvalid, awready, wvalid, wready, bvalid, bready;
	wire arvalid, arready, rvalid, rready;

	// peripheral interrupt
	wire uart_irq, timer_irq;

	cpu_core u_cpu (
		.clk(clk), .rst_n(rst_n),
		.mem_valid(cpu_mem_valid), .mem_ready(cpu_mem_ready),
		.mem_addr(cpu_mem_addr), .mem_wdata(cpu_mem_wdata),
		.mem_wstrb(cpu_mem_wstrb), .mem_data(cpu_mem_rdata),
		.irq_external(uart_irq),
		.irq_timer(1'b0)
	);

	mem_interconnect u_map (
		.mem_valid(cpu_mem_valid), .mem_ready(cpu_mem_ready),
		.mem_addr(cpu_mem_addr), .mem_wdata(cpu_mem_wdata),
		.mem_wstrb(cpu_mem_wstrb), .mem_rdata(cpu_mem_rdata),
		.mem_error(mem_error_debug),
		.bram_valid(bram_valid), .bram_ready(bram_ready),
		.bram_addr(bram_addr), .bram_wdata(bram_wdata),
		.bram_wstrb(bram_wstrb), .bram_rdata(bram_rdata),
		.axi_valid(axi_valid), .axi_ready(axi_ready),
		.axi_addr(axi_addr), .axi_wdata(axi_wdata),
		.axi_wstrb(axi_wstrb), .axi_rdata(axi_rdata),
		.axi_error(axi_error)
	);

	bram u_bram (
		.clk(clk), .rst_n(rst_n),
		.valid(bram_valid), .ready(bram_ready),
		.addr(bram_addr), .wdata(bram_wdata),
		.wstrb(bram_wstrb), .data(bram_rdata)
	);

	axi_lite_master u_axi (
		.clk(clk), .rst_n(rst_n),
		.req_valid(axi_valid), .req_ready(axi_ready),
		.req_addr(axi_addr), .req_wdata(axi_wdata),
		.req_wstrb(axi_wstrb), .req_rdata(axi_rdata),
		.req_error(axi_error),
		.m_axi_awaddr(awaddr), .m_axi_awprot(awprot),
		.m_axi_awvalid(awvalid), .m_axi_awready(awready),
		.m_axi_wdata(wdata), .m_axi_wstrb(wstrb),
		.m_axi_wvalid(wvalid), .m_axi_wready(wready),
		.m_axi_bresp(bresp), .m_axi_bvalid(bvalid),
		.m_axi_bready(bready),
		.m_axi_araddr(araddr), .m_axi_arprot(arprot),
		.m_axi_arvalid(arvalid), .m_axi_arready(arready),
		.m_axi_rdata(rdata), .m_axi_rresp(rresp),
		.m_axi_rvalid(rvalid), .m_axi_rready(rready)
	);

	// The UART IP sees local register offsets 0x0/0x4/0x8/0xC.
	// Native address decoding has already selected the UART window.
	// The UART is the only AXI slave, so use the low register-offset bits.
	// Confirmed from axi_uartlite_0.veo: address ports are [3:0].
	// This UART Lite IP configuration does not expose AWPROT/ARPROT.
	axi_uartlite_0 u_uart (
		.s_axi_aclk(clk), 
		.s_axi_aresetn(rst_n),
		.s_axi_awaddr(awaddr[3:0]),
		.s_axi_awvalid(awvalid), 
		.s_axi_awready(awready),
		.s_axi_wdata(wdata), 
		.s_axi_wstrb(wstrb),
		.s_axi_wvalid(wvalid), 
		.s_axi_wready(wready),
		.s_axi_bresp(bresp), 
		.s_axi_bvalid(bvalid),
		.s_axi_bready(bready),
		.s_axi_araddr(araddr[3:0]),
		.s_axi_arvalid(arvalid), 
		.s_axi_arready(arready),
		.s_axi_rdata(rdata), 
		.s_axi_rresp(rresp),
		.s_axi_rvalid(rvalid), 
		.s_axi_rready(rready),
		.rx(uart_rx), 
		.tx(uart_tx), 
		.interrupt(uart_irq)
	);
endmodule
