`timescale 1ns / 1ps

// ============================================================================
// Testbench: mem_interconnect + axi_lite_master
//
// No cpu_core, program.mem, real BRAM or AMD UART IP required.
// The AXI slave below is a BEHAVIORAL MODEL, not a serial UART transmitter.
//
// Run in Vivado: set tb_axi_subsystem as simulation top; run -all
// ============================================================================
module tb_axi_subsystem;
	reg clk = 1'b0;
	always #5 clk = ~clk; // 100 MHz

	reg rst_n = 1'b0;

	// ------------------------------------------------------------------------
	// CPU native interface (WORD address)
	// ------------------------------------------------------------------------
	reg         mem_valid = 1'b0;
	wire        mem_ready;
	reg [29:0]  mem_addr = 30'b0;
	reg [31:0]  mem_wdata = 32'b0;
	reg [3:0]   mem_wstrb = 4'b0;
	wire [31:0] mem_rdata;
	wire        mem_error;

	// Native BRAM interface
	wire        bram_valid, bram_ready;
	wire [29:0] bram_addr;
	wire [31:0] bram_wdata, bram_rdata;
	wire [3:0]  bram_wstrb;

	// Native AXI request interface
	wire        axi_valid, axi_ready, axi_error;
	wire [29:0] axi_addr;
	wire [31:0] axi_wdata, axi_rdata;
	wire [3:0]  axi_wstrb;

	// AXI4-Lite physical channels
	wire [31:0] awaddr, wdata, araddr, rdata;
	wire [3:0]  wstrb;
	wire [2:0]  awprot, arprot;
	wire [1:0]  bresp, rresp;
	wire awvalid, awready, wvalid, wready, bvalid, bready;
	wire arvalid, arready, rvalid, rready;

	// Programmable slave delay: independently hold off AW, W and AR.
	reg [7:0] aw_delay = 0;
	reg [7:0] w_delay  = 0;
	reg [7:0] ar_delay = 0;

	// ------------------------------------------------------------------------
	// DUT: the user's two unmodified modules
	// ------------------------------------------------------------------------
	mem_interconnect u_map (
		.mem_valid(mem_valid), .mem_ready(mem_ready),
		.mem_addr(mem_addr), .mem_wdata(mem_wdata), .mem_wstrb(mem_wstrb),
		.mem_rdata(mem_rdata), .mem_error(mem_error),
		.bram_valid(bram_valid), .bram_ready(bram_ready),
		.bram_addr(bram_addr), .bram_wdata(bram_wdata),
		.bram_wstrb(bram_wstrb), .bram_rdata(bram_rdata),
		.axi_valid(axi_valid), .axi_ready(axi_ready),
		.axi_addr(axi_addr), .axi_wdata(axi_wdata),
		.axi_wstrb(axi_wstrb), .axi_rdata(axi_rdata),
		.axi_error(axi_error)
	);

	axi_lite_master u_master (
		.clk(clk), .rst_n(rst_n),
		.req_valid(axi_valid), .req_ready(axi_ready),
		.req_addr(axi_addr), .req_wdata(axi_wdata), .req_wstrb(axi_wstrb),
		.req_rdata(axi_rdata), .req_error(axi_error),
		.m_axi_awaddr(awaddr), .m_axi_awprot(awprot),
		.m_axi_awvalid(awvalid), .m_axi_awready(awready),
		.m_axi_wdata(wdata), .m_axi_wstrb(wstrb),
		.m_axi_wvalid(wvalid), .m_axi_wready(wready),
		.m_axi_bresp(bresp), .m_axi_bvalid(bvalid), .m_axi_bready(bready),
		.m_axi_araddr(araddr), .m_axi_arprot(arprot),
		.m_axi_arvalid(arvalid), .m_axi_arready(arready),
		.m_axi_rdata(rdata), .m_axi_rresp(rresp),
		.m_axi_rvalid(rvalid), .m_axi_rready(rready)
	);

	tb_native_bram u_bram (
		.clk(clk), .rst_n(rst_n),
		.valid(bram_valid), .ready(bram_ready),
		.addr(bram_addr), .wdata(bram_wdata),
		.wstrb(bram_wstrb), .rdata(bram_rdata)
	);

	tb_axi_uart_slave u_uart (
		.clk(clk), .rst_n(rst_n),
		.aw_delay(aw_delay), .w_delay(w_delay), .ar_delay(ar_delay),
		.awaddr(awaddr), .awvalid(awvalid), .awready(awready),
		.wdata(wdata), .wstrb(wstrb), .wvalid(wvalid), .wready(wready),
		.bresp(bresp), .bvalid(bvalid), .bready(bready),
		.araddr(araddr), .arvalid(arvalid), .arready(arready),
		.rdata(rdata), .rresp(rresp), .rvalid(rvalid), .rready(rready)
	);

	// ------------------------------------------------------------------------
	// Self-checking native transaction driver
	// ------------------------------------------------------------------------
	integer tests = 0;
	integer aw_before, w_before, b_before, ar_before, r_before;
	integer clock_count;
	reg completed;

	// All addresses given to this task are BYTE addresses, like in C.
	// They must be aligned to 4 bytes for the current native CPU interface.
	// hold_cycles holds mem_valid HIGH after READY to detect duplicate AXI ops.
	task access;
		input [31:0] byte_addr;
		input [31:0] write_data;
		input [3:0]  write_strobe;
		input [31:0] expected_read;
		input        expected_error;
		input integer hold_cycles;
		integer i;
		reg use_axi;
		begin
			if (byte_addr[1:0] != 2'b00)
				$fatal(1, "Unaligned test address: %08h", byte_addr);

			use_axi = (byte_addr >= 32'h10000000 && byte_addr <= 32'h10000FFF);
			aw_before = u_uart.aw_count;
			w_before  = u_uart.w_count;
			b_before  = u_uart.b_count;
			ar_before = u_uart.ar_count;
			r_before  = u_uart.r_count;

			@(negedge clk);
			mem_addr  = byte_addr[31:2];
			mem_wdata = write_data;
			mem_wstrb = write_strobe;
			mem_valid = 1'b1;

			completed = 1'b0;
			begin : wait_for_response
				for (i = 0; i < 200; i = i + 1) begin
					@(posedge clk);
					#1;
					if (mem_ready) begin
						if (mem_error !== expected_error)
							$fatal(1, "Error mismatch addr=%08h got=%b expected=%b",
								byte_addr, mem_error, expected_error);
						if (write_strobe == 0 && !expected_error && mem_rdata !== expected_read)
							$fatal(1, "Read mismatch addr=%08h got=%08h expected=%08h",
								byte_addr, mem_rdata, expected_read);
						completed = 1'b1;
						disable wait_for_response;
					end
				end
			end
			if (!completed)
				$fatal(1, "Timeout waiting for CPU mem_ready at %08h", byte_addr);

			// Let the CPU-side receiver sample the response at the NEXT posedge.
			// Then deliberately keep VALID high a few extra clocks.
			@(posedge clk);
			#1;
			repeat (hold_cycles) begin
				@(posedge clk);
				#1;
			end
			@(negedge clk);
			mem_valid = 1'b0;
			repeat (3) @(posedge clk);
			#1;

			// Exactly one AW + W + B or one AR + R per mapped AXI request.
			if (use_axi) begin
				if (write_strobe != 0) begin
					if (u_uart.aw_count != aw_before+1 ||
					    u_uart.w_count  != w_before+1  ||
					    u_uart.b_count  != b_before+1  ||
					    u_uart.ar_count != ar_before  ||
					    u_uart.r_count  != r_before)
						$fatal(1, "Duplicate/missing write AXI handshake at %08h", byte_addr);
				end else begin
					if (u_uart.ar_count != ar_before+1 ||
					    u_uart.r_count  != r_before+1  ||
					    u_uart.aw_count != aw_before    ||
					    u_uart.w_count  != w_before     ||
					    u_uart.b_count  != b_before)
						$fatal(1, "Duplicate/missing read AXI handshake at %08h", byte_addr);
				end
			end else begin
				if (u_uart.aw_count != aw_before || u_uart.w_count != w_before ||
				    u_uart.b_count != b_before || u_uart.ar_count != ar_before ||
				    u_uart.r_count != r_before)
					$fatal(1, "Non-UART request leaked into AXI at %08h", byte_addr);
			end

			tests = tests + 1;
			$display("PASS %0d: addr=%08h  %s  error=%b", tests, byte_addr,
				write_strobe != 0 ? "WRITE" : "READ ", expected_error);
		end
	endtask

	// Verify native address routing and ensure the unselected port is idle.
	always @(posedge clk) begin
		if (rst_n && mem_valid) begin
			if (bram_valid && axi_valid)
				$fatal(1, "Both BRAM and AXI selected");
			if (mem_addr[29:16] == 0 && !bram_valid)
				$fatal(1, "BRAM range was not selected");
			if (mem_addr[29:10] == 20'h10000 && !axi_valid)
				$fatal(1, "UART range was not selected");
		end
	end

	initial begin
		repeat (6) @(negedge clk);
		rst_n = 1'b1;

		// BRAM full write, full read, and byte-lane write/read.
		access(32'h00000100, 32'hDEADBEEF, 4'hF, 32'b0, 0, 0);
		access(32'h00000100, 32'b0,       4'h0, 32'hDEADBEEF, 0, 0);
		access(32'h00000100, 32'h00004100, 4'h2, 32'b0, 0, 0);
		access(32'h00000100, 32'b0,       4'h0, 32'hDEAD41EF, 0, 0);

		// Last word of BRAM (256 KiB boundary).
		access(32'h0003FFFC, 32'h12345678, 4'hF, 32'b0, 0, 0);
		access(32'h0003FFFC, 32'b0,       4'h0, 32'h12345678, 0, 0);

		// UART TX: AW accepted before W; hold valid to catch duplicates.
		aw_delay = 0;
		w_delay  = 5;
		access(32'h10000004, 32'h00000041, 4'hF, 32'b0, 0, 4);
		if (u_uart.tx_writes !== 1 || u_uart.tx_last !== 32'h00000041)
			$fatal(1, "First UART TX FIFO write incorrect");

		// UART TX: W accepted before AW.
		aw_delay = 6;
		w_delay  = 0;
		access(32'h10000004, 32'h00000042, 4'hF, 32'b0, 0, 3);
		if (u_uart.tx_writes !== 2 || u_uart.tx_last !== 32'h00000042)
			$fatal(1, "Second UART TX FIFO write incorrect");

		// UART STATUS: bit 2 (TX FIFO empty) = 1; bit 3 (full) = 0.
		ar_delay = 4;
		access(32'h10000008, 32'b0, 4'h0, 32'h00000004, 0, 2);

		// In-window invalid register -> AXI SLVERR (not decoder error).
		access(32'h10000010, 32'b0, 4'h0, 32'b0, 1, 0);
		access(32'h10000010, 32'hABCDEF01, 4'hF, 32'b0, 1, 0);

		// Outside BRAM and UART: decode error, no AXI transactions.
		access(32'h00040000, 32'b0, 4'h0, 32'b0, 1, 0);
		access(32'h0FFFFFFC, 32'b0, 4'h0, 32'b0, 1, 0);
		access(32'h10001000, 32'b0, 4'h0, 32'b0, 1, 0); // reserved timer
		access(32'h10001000, 32'hCAFE1234, 4'hF, 32'b0, 1, 0);

		$display("============================================================");
		$display("PASS: %0d memory mapping + AXI4-Lite transactions", tests);
		$display("AXI handshakes: AW=%0d W=%0d B=%0d AR=%0d R=%0d",
			u_uart.aw_count, u_uart.w_count, u_uart.b_count,
			u_uart.ar_count, u_uart.r_count);
		$display("============================================================");
		$finish;
	end

	initial begin
		#100000;
		$fatal(1, "Global simulation timeout");
	end
endmodule

// ============================================================================
// Simulation BRAM: 256 KiB, 32-bit words, matching native valid/ready.
// ============================================================================
module tb_native_bram (
	input wire clk, rst_n, valid,
	output reg ready,
	input wire [29:0] addr,
	input wire [31:0] wdata,
	input wire [3:0] wstrb,
	output reg [31:0] rdata
);
	reg [31:0] memory [0:65535];

	always @(posedge clk) begin
		if (!rst_n) begin
			ready <= 1'b0;
			rdata <= 32'b0;
		end else begin
			ready <= 1'b0;
			if (valid && !ready) begin
				if (addr[29:16] != 0)
					$fatal(1, "BRAM received an out-of-range address");
				if (wstrb == 0) begin
					rdata <= memory[addr[15:0]];
				end else begin
					if (wstrb[0]) memory[addr[15:0]][7:0]   <= wdata[7:0];
					if (wstrb[1]) memory[addr[15:0]][15:8]  <= wdata[15:8];
					if (wstrb[2]) memory[addr[15:0]][23:16] <= wdata[23:16];
					if (wstrb[3]) memory[addr[15:0]][31:24] <= wdata[31:24];
				end
				ready <= 1'b1;
			end
		end
	end
endmodule

// ============================================================================
// Simulation AXI4-Lite UART register stub.
// - AW, W, AR ready delays are independently programmable.
// - All responses stay VALID until READY.
// - Only TX FIFO (write at +0x04) and STATUS (read at +0x08) are emulated.
// - Unsupported offsets return SLVERR. This is NOT the AMD UART IP.
// ============================================================================
module tb_axi_uart_slave (
	input  wire        clk, rst_n,
	input  wire [7:0]  aw_delay, w_delay, ar_delay,
	input  wire [31:0] awaddr,
	input  wire        awvalid,
	output reg         awready,
	input  wire [31:0] wdata,
	input  wire [3:0]  wstrb,
	input  wire        wvalid,
	output reg         wready,
	output reg  [1:0]  bresp,
	output reg         bvalid,
	input  wire        bready,
	input  wire [31:0] araddr,
	input  wire        arvalid,
	output reg         arready,
	output reg  [31:0] rdata,
	output reg  [1:0]  rresp,
	output reg         rvalid,
	input  wire        rready
);
	reg got_aw, got_w;
	reg [31:0] awaddr_q, wdata_q;
	reg [3:0] wstrb_q;
	reg [7:0] aw_ticks, w_ticks, ar_ticks;
	integer aw_count, w_count, b_count, ar_count, r_count;
	integer tx_writes;
	reg [31:0] tx_last;

	// Each READY is independent. Delays force both AW-first and W-first cases.
	always @(*) begin
		awready = rst_n && !got_aw && (aw_ticks >= aw_delay);
		wready  = rst_n && !got_w  && (w_ticks  >= w_delay);
		arready = rst_n && !rvalid && (ar_ticks >= ar_delay);
	end

	always @(posedge clk) begin
		if (!rst_n) begin
			got_aw <= 0;
			got_w <= 0;
			awaddr_q <= 0;
			wdata_q <= 0;
			wstrb_q <= 0;
			aw_ticks <= 0;
			w_ticks <= 0;
			ar_ticks <= 0;
			bvalid <= 0;
			bresp <= 0;
			rvalid <= 0;
			rdata <= 0;
			rresp <= 0;
			aw_count <= 0;
			w_count <= 0;
			b_count <= 0;
			ar_count <= 0;
			r_count <= 0;
			tx_writes <= 0;
			tx_last <= 0;
		end else begin
			// AW channel
			if (awvalid && !awready)
				aw_ticks <= aw_ticks + 1'b1;
			if (awvalid && awready) begin
				got_aw <= 1;
				awaddr_q <= awaddr;
				aw_count <= aw_count + 1;
			end

			// W channel (independent from AW)
			if (wvalid && !wready)
				w_ticks <= w_ticks + 1'b1;
			if (wvalid && wready) begin
				got_w <= 1;
				wdata_q <= wdata;
				wstrb_q <= wstrb;
				w_count <= w_count + 1;
			end

			// B response only after BOTH address and data were accepted.
			if (got_aw && got_w && !bvalid) begin
				bvalid <= 1;
				if (awaddr_q == 32'h10000004 && wstrb_q == 4'hF) begin
					bresp <= 2'b00; // OKAY
					tx_writes <= tx_writes + 1;
					tx_last <= wdata_q;
				end else begin
					bresp <= 2'b10; // SLVERR
				end
			end
			if (bvalid && bready) begin
				b_count <= b_count + 1;
				bvalid <= 0;
				got_aw <= 0;
				got_w <= 0;
				aw_ticks <= 0;
				w_ticks <= 0;
			end

			// AR channel
			if (arvalid && !arready)
				ar_ticks <= ar_ticks + 1'b1;
			if (arvalid && arready) begin
				ar_count <= ar_count + 1;
				rvalid <= 1;
				if (araddr == 32'h10000008) begin
					rdata <= 32'h00000004; // TX FIFO empty, not full
					rresp <= 2'b00; // OKAY
				end else begin
					rdata <= 32'b0;
					rresp <= 2'b10; // SLVERR
				end
			end
			if (rvalid && rready) begin
				r_count <= r_count + 1;
				rvalid <= 0;
				ar_ticks <= 0;
			end
		end
	end
endmodule
