// RV32IM SoC top: CPU + BRAM + native timer + native UART.
// Receives an 80 MHz clock and synchronized reset from the board wrapper.
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

	wire        timer_valid, timer_ready;
	wire [29:0] timer_addr;
	wire [31:0] timer_wdata, timer_rdata;
	wire [3:0]  timer_wstrb;

	wire        uart_valid, uart_ready;
	wire [29:0] uart_addr;
	wire [31:0] uart_wdata, uart_rdata;
	wire [3:0]  uart_wstrb;

	// peripheral interrupt
	wire uart_irq, timer_irq;

	cpu_core u_cpu (
		.clk(clk), .rst_n(rst_n),
		.mem_valid(cpu_mem_valid), .mem_ready(cpu_mem_ready),
		.mem_addr(cpu_mem_addr), .mem_wdata(cpu_mem_wdata),
		.mem_wstrb(cpu_mem_wstrb), .mem_data(cpu_mem_rdata),
		.irq_external(uart_irq),
		.irq_timer(timer_irq)
	);

	mem_interconnect u_map (
		.mem_valid(cpu_mem_valid), .mem_ready(cpu_mem_ready),
		.mem_addr(cpu_mem_addr), .mem_wdata(cpu_mem_wdata),
		.mem_wstrb(cpu_mem_wstrb), .mem_rdata(cpu_mem_rdata),
		.mem_error(mem_error_debug),
		.bram_valid(bram_valid), .bram_ready(bram_ready),
		.bram_addr(bram_addr), .bram_wdata(bram_wdata),
		.bram_wstrb(bram_wstrb), .bram_rdata(bram_rdata),
		.timer_valid(timer_valid), .timer_ready(timer_ready),
		.timer_addr(timer_addr), .timer_wdata(timer_wdata),
		.timer_wstrb(timer_wstrb), .timer_rdata(timer_rdata),
		.uart_valid(uart_valid), .uart_ready(uart_ready),
		.uart_addr(uart_addr), .uart_wdata(uart_wdata),
		.uart_wstrb(uart_wstrb), .uart_rdata(uart_rdata)
	);

	bram u_bram (
		.clk(clk), .rst_n(rst_n),
		.valid(bram_valid), .ready(bram_ready),
		.addr(bram_addr), .wdata(bram_wdata),
		.wstrb(bram_wstrb), .data(bram_rdata)
	);

	m_timer u_timer (
		.clk(clk), .rst_n(rst_n),
		.valid(timer_valid), .ready(timer_ready),
		.addr(timer_addr), .wdata(timer_wdata),
		.wstrb(timer_wstrb), .data(timer_rdata),
		.timer_irq(timer_irq)
	);

	uart u_uart (
		.clk(clk), .rst_n(rst_n),
		.valid(uart_valid), .ready(uart_ready),
		.addr(uart_addr), .wdata(uart_wdata),
		.wstrb(uart_wstrb), .data(uart_rdata),
		.uart_rx(uart_rx), .uart_tx(uart_tx),
		.uart_irq(uart_irq)
	);
endmodule
