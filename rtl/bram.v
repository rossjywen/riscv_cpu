module bram(
    input wire          rst_n,
    input wire          clk,
    input wire          valid,
    input wire [29:0]    addr,
    output reg          ready,
    output reg [31:0]   data
);
    (* rom_style = "block" *)
    reg [31:0] mem [0:1023];
    
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
                data <= mem[addr];
                ready <= 1;
            end
        end
    end

endmodule
