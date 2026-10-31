// AXI4-Lite Master
// Convert one CPU native memory request into one AXI4-Lite transaction.
//
// CPU native interface:
//   req_addr  : 30-bit WORD address (not byte address)
//   req_wstrb : 4'b0000 means READ; any other value means WRITE
//   req_valid: held high until req_ready is observed
//   req_ready: held high until req_valid goes low


module axi_lite_master (
	input  wire        clk,
	input  wire        rst_n,

	// CPU native memory request
	input  wire        req_valid,
	output reg         req_ready,
	input  wire [29:0] req_addr,
	input  wire [31:0] req_wdata,
	input  wire [3:0]  req_wstrb,
	output reg  [31:0] req_rdata,
	output reg         req_error,

	// AXI4-Lite: AW - Write Address
	output reg  [31:0] m_axi_awaddr,
	output reg  [2:0]  m_axi_awprot,
	output reg         m_axi_awvalid,
	input  wire        m_axi_awready,

	// AXI4-Lite: W - Write Data
	output reg  [31:0] m_axi_wdata,
	output reg  [3:0]  m_axi_wstrb,
	output reg         m_axi_wvalid,
	input  wire        m_axi_wready,

	// AXI4-Lite: B - Write Response
	input  wire [1:0]  m_axi_bresp,
	input  wire        m_axi_bvalid,
	output reg         m_axi_bready,

	// AXI4-Lite: AR - Read Address
	output reg  [31:0] m_axi_araddr,
	output reg  [2:0]  m_axi_arprot,
	output reg         m_axi_arvalid,
	input  wire        m_axi_arready,

	// AXI4-Lite: R - Read Data + Response
	input  wire [31:0] m_axi_rdata,
	input  wire [1:0]  m_axi_rresp,
	input  wire        m_axi_rvalid,
	output reg         m_axi_rready
);

	// FSM states
	localparam [2:0] ST_IDLE         = 3'd0;
	localparam [2:0] ST_WRITE_AW_W   = 3'd1;
	localparam [2:0] ST_WRITE_B      = 3'd2;
	localparam [2:0] ST_READ_AR      = 3'd3;
	localparam [2:0] ST_READ_R       = 3'd4;
	localparam [2:0] ST_CPU_RESPONSE = 3'd5;

	reg [2:0] state;

	// One CPU request is captured here and stays unchanged throughout AXI.
	reg [31:0] addr_q;
	reg [31:0] wdata_q;
	reg [3:0]  wstrb_q;

	// Results returned to CPU.
	reg [31:0] rdata_q;
	reg        error_q;

	// AW and W are independent channels; each needs its own completion flag.
	reg aw_done;
	reg w_done;

	// Combinational logic: drive CPU and AXI interface outputs
	always @(*) begin
		// Default: no handshakes requested.
		req_ready     = 1'b0;
		req_rdata     = rdata_q;
		req_error     = error_q;

		// AXI payload comes from registered CPU request, not live CPU inputs.
		m_axi_awaddr  = addr_q;
		m_axi_awprot  = 3'b000;
		m_axi_awvalid = 1'b0;

		m_axi_wdata   = wdata_q;
		m_axi_wstrb   = wstrb_q;
		m_axi_wvalid  = 1'b0;

		m_axi_bready  = 1'b0;

		m_axi_araddr  = addr_q;
		m_axi_arprot  = 3'b000;
		m_axi_arvalid = 1'b0;

		m_axi_rready  = 1'b0;

		case (state)
			ST_WRITE_AW_W: begin
				// Present AW and W independently until each is accepted.
				if (!aw_done) begin
					m_axi_awvalid = 1'b1;
				end

				if (!w_done) begin
					m_axi_wvalid = 1'b1;
				end
			end

			ST_WRITE_B: begin
				// The write is NOT complete until the B handshake.
				m_axi_bready = 1'b1;
			end

			ST_READ_AR: begin
				// Request one read address.
				m_axi_arvalid = 1'b1;
			end

			ST_READ_R: begin
				// Wait until data and response arrive together.
				m_axi_rready = 1'b1;
			end

			ST_CPU_RESPONSE: begin
				// The native CPU request has completed.
				req_ready = 1'b1;
			end

			default: begin
				// ST_IDLE: all VALID / READY outputs stay low.
			end
		endcase
	end

	// Sequential logic: capture requests, observe AXI handshakes, move states
	always @(posedge clk) begin
		if (!rst_n) begin
			state   <= ST_IDLE;
			addr_q  <= 32'b0;
			wdata_q <= 32'b0;
			wstrb_q <= 4'b0;
			rdata_q <= 32'b0;
			error_q <= 1'b0;
			aw_done <= 1'b0;
			w_done  <= 1'b0;
		end else begin
			case (state)
				ST_IDLE: begin
					if (req_valid) begin
						// Native word address -> AXI byte address.
						addr_q  <= {req_addr, 2'b00};
						wdata_q <= req_wdata;
						wstrb_q <= req_wstrb;
						rdata_q <= 32'b0;
						error_q <= 1'b0;
						aw_done <= 1'b0;
						w_done  <= 1'b0;

						if (req_wstrb == 4'b0000)
							state <= ST_READ_AR;
						else
							state <= ST_WRITE_AW_W;
					end
				end

				ST_WRITE_AW_W: begin
					// AW transfer completes on AWVALID && AWREADY.
					if (m_axi_awvalid && m_axi_awready)
						aw_done <= 1'b1;

					// W transfer completes independently on WVALID && WREADY.
					if (m_axi_wvalid && m_axi_wready)
						w_done <= 1'b1;

					// These are registered flags: a simple, explicit extra
					// clock is allowed after the last address/data handshake.
					if (aw_done && w_done)
						state <= ST_WRITE_B;
				end

				ST_WRITE_B: begin
					// Response completes only on BVALID && BREADY.
					if (m_axi_bvalid && m_axi_bready) begin
						error_q <= (m_axi_bresp != 2'b00); // OKAY
						state <= ST_CPU_RESPONSE;
					end
				end

				ST_READ_AR: begin
					// AR transfer completes on ARVALID && ARREADY.
					if (m_axi_arvalid && m_axi_arready)
						state <= ST_READ_R;
				end

				ST_READ_R: begin
					// Read data and RRESP are accepted in the same R transfer.
					if (m_axi_rvalid && m_axi_rready) begin
						rdata_q <= m_axi_rdata;
						error_q <= (m_axi_rresp != 2'b00); // OKAY
						state <= ST_CPU_RESPONSE;
					end
				end

				ST_CPU_RESPONSE: begin
					// Avoid issuing the same CPU request more than once.
					// The CPU must lower req_valid before another request.
					if (!req_valid)
						state <= ST_IDLE;
				end

				default: begin
					state <= ST_IDLE;
				end
			endcase
		end
	end
endmodule
