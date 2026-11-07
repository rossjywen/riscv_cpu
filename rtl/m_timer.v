
module m_timer (
	input  wire        clk,
	input  wire        rst_n,

	// Native memory interface (word address)
	input  wire        valid,
	output reg         ready,
	input  wire [29:0] addr,
	input  wire [31:0] wdata,
	input  wire [3:0]  wstrb,
	output reg  [31:0] data,

	output wire        timer_irq
);

	// Register addresses (word addresses)
	// Byte address 0x10001000 -> word address 0x04000400
	localparam [29:0] ADDR_MTIME_LO    = 30'h0400_0400;
	localparam [29:0] ADDR_MTIME_HI    = 30'h0400_0401;
	localparam [29:0] ADDR_MTIMECMP_LO = 30'h0400_0402;
	localparam [29:0] ADDR_MTIMECMP_HI = 30'h0400_0403;

	// 80 MHz clock / 8,000 = 10 kHz timer
	// One timer tick = 100 us
	reg [13:0] clock_divider;

	// Machine timer registers
	reg [63:0] mtime;
	reg [63:0] mtimecmp;

	wire timer_tick = (clock_divider == 14'd7999);

	// Machine Timer Interrupt
	assign timer_irq = (mtime >= mtimecmp);


	always @(posedge clk) begin
		if (!rst_n) begin
			clock_divider <= 14'd0;
			mtime         <= 64'd0;
			mtimecmp      <= 64'hFFFF_FFFF_FFFF_FFFF;
			ready         <= 1'b0;
			data          <= 32'd0;
		end else begin
			// 1. Clock divider
			if (timer_tick)
				clock_divider <= 14'd0;
			else
				clock_divider <= clock_divider + 14'd1;

			// 2. mtime counter
			// Only an accepted mtime write suppresses this tick.
			if (timer_tick &&
				!(valid && !ready && (wstrb != 4'b0000) &&
				  (addr == ADDR_MTIME_LO || addr == ADDR_MTIME_HI))) begin
				mtime <= mtime + 64'd1;
			end


			// 3. Memory interface: read, write and ready
			ready <= 1'b0;

			if (valid && !ready) begin
				ready <= 1'b1;

				case (addr)
					ADDR_MTIME_LO: begin
						if (wstrb == 4'b0000) begin
							data <= mtime[31:0];
						end else begin
							if (wstrb[0]) mtime[7:0]   <= wdata[7:0];
							if (wstrb[1]) mtime[15:8]  <= wdata[15:8];
							if (wstrb[2]) mtime[23:16] <= wdata[23:16];
							if (wstrb[3]) mtime[31:24] <= wdata[31:24];
						end
					end

					ADDR_MTIME_HI: begin
						if (wstrb == 4'b0000) begin
							data <= mtime[63:32];
						end else begin
							if (wstrb[0]) mtime[39:32] <= wdata[7:0];
							if (wstrb[1]) mtime[47:40] <= wdata[15:8];
							if (wstrb[2]) mtime[55:48] <= wdata[23:16];
							if (wstrb[3]) mtime[63:56] <= wdata[31:24];
						end
					end

					ADDR_MTIMECMP_LO: begin
						if (wstrb == 4'b0000) begin
							data <= mtimecmp[31:0];
						end else begin
							if (wstrb[0]) mtimecmp[7:0]   <= wdata[7:0];
							if (wstrb[1]) mtimecmp[15:8]  <= wdata[15:8];
							if (wstrb[2]) mtimecmp[23:16] <= wdata[23:16];
							if (wstrb[3]) mtimecmp[31:24] <= wdata[31:24];
						end
					end

					ADDR_MTIMECMP_HI: begin
						if (wstrb == 4'b0000) begin
							data <= mtimecmp[63:32];
						end else begin
							if (wstrb[0]) mtimecmp[39:32] <= wdata[7:0];
							if (wstrb[1]) mtimecmp[47:40] <= wdata[15:8];
							if (wstrb[2]) mtimecmp[55:48] <= wdata[23:16];
							if (wstrb[3]) mtimecmp[63:56] <= wdata[31:24];
						end
					end

					default: begin
						if (wstrb == 4'b0000)
							data <= 32'd0;
					end
				endcase
			end

		end
	end

endmodule
