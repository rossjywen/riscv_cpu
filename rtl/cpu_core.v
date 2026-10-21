module cpu_core (
    input wire          rst_n,
    input wire          clk,

    input wire          mem_ready,
    input wire [31:0]   mem_data,
    output reg          mem_valid,
    output reg [29:0]   mem_addr   // aligned to 4 bytes
);
 
    localparam MEM_IDLE = 2'b01;
    localparam MEM_WAIT = 2'b10;

    // fsm
    reg [1:0] mem_state;
    reg [2:0] cpu_state;

    // memory operation from fetch module
    reg mem_do_rinst;
    reg mem_do_rdata;
    reg mem_do_wdata;

    wire mem_xfer;
    assign mem_xfer = mem_ready & mem_valid;

    // memory look-ahead
    //wire [29:0] mem_la_addr;
    //assign mem_la_addr = mem_do_rinst? next_pc : 0;

    // pc
    reg [29:0] current_pc;
    reg [29:0] next_pc;
    //wire [29:0] next_pc_la;
    //assign next_pc = 


    // memory interface
    always @(posedge clk) begin
        if (!rst_n) begin
            mem_state <= MEM_IDLE;
            mem_valid <= 1'b0;
            mem_addr <= 30'b0;
        end else begin
            case (mem_state)
                MEM_IDLE: begin
                    if (mem_do_rinst) begin
                        mem_valid <= 1'b1;
                        mem_state <= MEM_WAIT;
                        mem_addr <= current_pc;
                    end
                end
                MEM_WAIT: begin
                    if (mem_xfer) begin
                        mem_valid <= 0;
                        mem_state <= MEM_IDLE;
                        $display("memory data: %08h", mem_data);
                    end
                end
            endcase
        end
    end


    // fetch module
    always @(posedge clk) begin
        if (!rst_n) begin
            current_pc <= 30'b0;
            next_pc <= 30'b0;
            cpu_state <= 0;
            mem_do_rinst <= 0;
        end else begin
            case (cpu_state)
                0: begin
                    if (!mem_do_rinst) begin
                        mem_do_rinst <= 1;
                        next_pc <= next_pc + 30'd1;
                        current_pc <= next_pc;

                        cpu_state <= 1;
                    end
                end
                1: begin
                    if ((mem_xfer & mem_do_rinst)) begin
                        mem_do_rinst <= 0;
                        cpu_state <= 0;
                    end
                end
            endcase
        end
    end


    // // decorder module
    // always @(posedge clk) begin
    //     if (mem_xfer & mem_do_rinst) begin

    //     end
    // end

endmodule