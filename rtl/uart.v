// Native UART: 80 MHz clock, 115200 baud, 8 data bits, no parity, 1 stop bit.
// TX and RX each hold one byte; there are no FIFOs.
//
// Full WORD addresses, matching bram/m_timer. wstrb == 0 means READ.
// Byte address   Register   Read                         Write (wstrb[0])
// 0x10000000     RX         Received byte; clears valid  Ignored
// 0x10000004     TX         Zero                         Send byte if idle
// 0x10000008     STATUS     Status; clears sticky flags  Ignored
// 0x1000000C     CONTROL    Interrupt enable in bit 4    Reset/enable below
// Unimplemented addresses read zero and ignore writes.
//
// STATUS: bit 0 RX valid, bit 1 RX full (same as valid), bit 2 TX idle,
//         bit 3 TX busy, bit 4 interrupt enable, bit 5 RX overrun,
//         bit 6 RX framing error, bit 7 zero, bit 8 TX done.
// CONTROL: bit 0 reset TX, bit 1 reset RX, bit 4 interrupt enable.
// Reset bits are commands, not stored bits. TX reset aborts transmission.
// Writes while TX is busy are acknowledged but ignored; check STATUS first.
// RX overrun preserves the unread byte and discards the arriving byte.
//
// IRQ stays high while enabled and RX valid or any sticky flag is set.
// Reading STATUS clears TX done/overrun/framing error; reading RX clears valid.
// A new event wins over a simultaneous read; explicit reset commands win last.
// Like bram/m_timer, the master must lower valid after the ready handshake.
module uart (
	input  wire        clk,
	input  wire        rst_n,

	input  wire        valid,
	output reg         ready,
	input  wire [29:0] addr,
	input  wire [31:0] wdata,
	input  wire [3:0]  wstrb,
	output reg  [31:0] data,

	input  wire        uart_rx,
	output reg         uart_tx,
	output wire        uart_irq
);
	// Byte address 0x10000000 -> word address 0x04000000.
	localparam [29:0] ADDR_RX      = 30'h0400_0000;
	localparam [29:0] ADDR_TX      = 30'h0400_0001;
	localparam [29:0] ADDR_STATUS  = 30'h0400_0002;
	localparam [29:0] ADDR_CONTROL = 30'h0400_0003;

	// 80,000,000 / 115,200 rounded to 694 clocks per bit.
	// Counters start at zero, so a full bit ends at 693, half a bit at 346.
	localparam [9:0] BIT_LAST_COUNT      = 10'd693;
	localparam [9:0] HALF_BIT_LAST_COUNT = 10'd346;

	localparam [1:0] TX_IDLE  = 2'd0;
	localparam [1:0] TX_START = 2'd1;
	localparam [1:0] TX_DATA  = 2'd2;
	localparam [1:0] TX_STOP  = 2'd3;

	localparam [2:0] RX_IDLE      = 3'd0;
	localparam [2:0] RX_START     = 3'd1;
	localparam [2:0] RX_DATA      = 3'd2;
	localparam [2:0] RX_STOP      = 3'd3;
	localparam [2:0] RX_WAIT_IDLE = 3'd4;

	reg [1:0] tx_state;
	reg [9:0] tx_clock;
	reg [2:0] tx_bit;
	reg [7:0] tx_shift;
	reg       tx_done;
	wire      tx_busy = (tx_state != TX_IDLE);

	reg [2:0] rx_state;
	reg [9:0] rx_clock;
	reg [2:0] rx_bit;
	reg [7:0] rx_shift;
	reg [7:0] rx_data;
	reg       rx_data_valid;
	reg       rx_overrun;
	reg       rx_framing_error;
	reg       interrupt_enable;

	// RX is asynchronous to clk. Only the second synchronizer stage is sampled.
	(* ASYNC_REG = "TRUE" *) reg rx_meta;
	(* ASYNC_REG = "TRUE" *) reg rx_sync;

	always @(posedge clk) begin
		if (!rst_n) begin
			rx_meta <= 1'b1;
			rx_sync <= 1'b1;
		end else begin
			rx_meta <= uart_rx;
			rx_sync <= rx_meta;
		end
	end

	assign uart_irq = interrupt_enable &&
		(rx_data_valid || tx_done || rx_overrun || rx_framing_error);

	always @(posedge clk) begin
		if (!rst_n) begin
			ready <= 1'b0;
			data <= 32'd0;
			interrupt_enable <= 1'b0;

			uart_tx <= 1'b1;
			tx_state <= TX_IDLE;
			tx_clock <= 10'd0;
			tx_bit <= 3'd0;
			tx_shift <= 8'd0;
			tx_done <= 1'b0;

			rx_state <= RX_IDLE;
			rx_clock <= 10'd0;
			rx_bit <= 3'd0;
			rx_shift <= 8'd0;
			rx_data <= 8'd0;
			rx_data_valid <= 1'b0;
			rx_overrun <= 1'b0;
			rx_framing_error <= 1'b0;
		end else begin
			// 1. Native memory interface: read, write and ready.
			ready <= 1'b0;
			if (valid && !ready) begin
				ready <= 1'b1;
				case (addr)
					ADDR_RX: begin
						if (wstrb == 4'b0000) begin
							data <= rx_data_valid ? {24'd0, rx_data} : 32'd0;
							rx_data_valid <= 1'b0;
						end
					end

					ADDR_TX: begin
						if (wstrb == 4'b0000) begin
							data <= 32'd0;
						end else if (wstrb[0] && !tx_busy) begin
							tx_shift <= wdata[7:0];
							tx_bit <= 3'd0;
							tx_clock <= 10'd0;
							tx_state <= TX_START;
							uart_tx <= 1'b0;
							tx_done <= 1'b0;
						end
					end

					ADDR_STATUS: begin
						if (wstrb == 4'b0000) begin
							data <= {23'd0, tx_done, 1'b0, rx_framing_error,
								rx_overrun, interrupt_enable, tx_busy, !tx_busy,
								rx_data_valid, rx_data_valid};
							tx_done <= 1'b0;
							rx_overrun <= 1'b0;
							rx_framing_error <= 1'b0;
						end
					end

					ADDR_CONTROL: begin
						if (wstrb == 4'b0000) begin
							data <= {27'd0, interrupt_enable, 4'd0};
						end else if (wstrb[0]) begin
							interrupt_enable <= wdata[4];
							// Reset commands are applied after the TX/RX state machines.
						end
					end

					default: begin
						if (wstrb == 4'b0000)
							data <= 32'd0;
					end
				endcase
			end

			// 2. Transmit: start bit, eight data bits (LSB first), stop bit.
			case (tx_state)
				TX_IDLE: begin
					// An accepted TX register write starts the next frame.
				end

				TX_START: begin
					if (tx_clock == BIT_LAST_COUNT) begin
						tx_clock <= 10'd0;
						uart_tx <= tx_shift[0];
						tx_state <= TX_DATA;
					end else
						tx_clock <= tx_clock + 10'd1;
				end

				TX_DATA: begin
					if (tx_clock == BIT_LAST_COUNT) begin
						tx_clock <= 10'd0;
						if (tx_bit == 3'd7) begin
							uart_tx <= 1'b1;
							tx_state <= TX_STOP;
						end else begin
							tx_bit <= tx_bit + 3'd1;
							tx_shift <= {1'b0, tx_shift[7:1]};
							uart_tx <= tx_shift[1];
						end
					end else
						tx_clock <= tx_clock + 10'd1;
				end

				TX_STOP: begin
					if (tx_clock == BIT_LAST_COUNT) begin
						tx_clock <= 10'd0;
						tx_state <= TX_IDLE;
						tx_done <= 1'b1;
					end else
						tx_clock <= tx_clock + 10'd1;
				end
			endcase

			// 3. Receive: confirm the start bit, then sample each bit at its center.
			case (rx_state)
				RX_IDLE: begin
					if (!rx_sync) begin
						rx_clock <= 10'd0;
						rx_state <= RX_START;
					end
				end

				RX_START: begin
					if (rx_clock == HALF_BIT_LAST_COUNT) begin
						rx_clock <= 10'd0;
						if (!rx_sync) begin
							rx_bit <= 3'd0;
							rx_state <= RX_DATA;
						end else
							rx_state <= RX_IDLE; // Reject a short low glitch.
					end else
						rx_clock <= rx_clock + 10'd1;
				end

				RX_DATA: begin
					if (rx_clock == BIT_LAST_COUNT) begin
						rx_clock <= 10'd0;
						rx_shift[rx_bit] <= rx_sync;
						if (rx_bit == 3'd7)
							rx_state <= RX_STOP;
						else
							rx_bit <= rx_bit + 3'd1;
					end else
						rx_clock <= rx_clock + 10'd1;
				end

				RX_STOP: begin
					if (rx_clock == BIT_LAST_COUNT) begin
						rx_clock <= 10'd0;
						if (rx_sync) begin
							rx_state <= RX_IDLE;
							// A simultaneous RX read consumes the old byte, freeing space.
							if (!rx_data_valid || (valid && !ready &&
								wstrb == 4'b0000 && addr == ADDR_RX)) begin
								rx_data <= rx_shift;
								rx_data_valid <= 1'b1;
							end else
								rx_overrun <= 1'b1;
						end else begin
							rx_framing_error <= 1'b1;
							rx_state <= RX_WAIT_IDLE;
						end
					end else
						rx_clock <= rx_clock + 10'd1;
				end

				RX_WAIT_IDLE: begin
					// A held-low line reports one framing error, then waits for idle.
					if (rx_sync)
						rx_state <= RX_IDLE;
				end

				default: rx_state <= RX_IDLE;
			endcase

			// 4. Explicit software resets override activity in the same clock.
			if (valid && !ready && (wstrb != 4'b0000) &&
				wstrb[0] && addr == ADDR_CONTROL) begin
				if (wdata[0]) begin
					uart_tx <= 1'b1;
					tx_state <= TX_IDLE;
					tx_clock <= 10'd0;
					tx_bit <= 3'd0;
					tx_shift <= 8'd0;
					tx_done <= 1'b0;
				end
				if (wdata[1]) begin
					rx_state <= RX_WAIT_IDLE;
					rx_clock <= 10'd0;
					rx_bit <= 3'd0;
					rx_shift <= 8'd0;
					rx_data <= 8'd0;
					rx_data_valid <= 1'b0;
					rx_overrun <= 1'b0;
					rx_framing_error <= 1'b0;
				end
			end
		end
	end
endmodule
