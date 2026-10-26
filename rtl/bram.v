module bram(
    input wire          rst_n,
    input wire          clk,
    input wire          valid,
    input wire [29:0]   addr,
    input wire [3:0]    wstrb,
    input wire [31:0]   wdata,
    output reg          ready,
    output reg [31:0]   data
);
    localparam integer RAM_WORDS = 65536;  // 256 KiB
    (* ram_style = "block" *)
    reg [31:0] mem [0:RAM_WORDS-1];
    
    initial begin
        $readmemh("program.mem", mem);
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            ready <= 1'b0;
        end
        else begin
            ready <= 1'b0;

            if (valid && !ready) begin
                if (wstrb == 4'b0000) begin
                    data <= mem[addr];
                end else begin
                    if (wstrb[0]) begin
                        mem[addr][7:0]   <= wdata[7:0];
                    end

                    if (wstrb[1]) begin
                        mem[addr][15:8]  <= wdata[15:8];
                    end

                    if (wstrb[2]) begin
                        mem[addr][23:16] <= wdata[23:16];
                    end

                    if (wstrb[3]) begin
                        mem[addr][31:24] <= wdata[31:24];
                    end
                end

                ready <= 1;
            end
        end
    end

endmodule
