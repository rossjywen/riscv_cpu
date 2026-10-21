
`timescale 1ns / 1ps

module tb_cpu_core;

    reg clk = 0;
    reg rst_n = 0;

    // CPU <-> BRAM signals
    wire        mem_valid;
    wire        mem_ready;
    wire [29:0] mem_addr;
    wire [31:0] mem_data;

    // 100 MHz clock
    always #5 clk = ~clk;

    // CPU instance
    cpu_core u_cpu (
        .clk       (clk),
        .rst_n     (rst_n),
        .mem_valid (mem_valid),
        .mem_ready (mem_ready),
        .mem_addr  (mem_addr),
        .mem_data  (mem_data)
    );

    // BRAM instance
    bram u_bram (
        .clk   (clk),
        .rst_n (rst_n),
        .valid (mem_valid),
        .ready (mem_ready),
        .addr  (mem_addr),
        .data  (mem_data)
    );

    // Test sequence
    initial begin

        // Reset
        repeat (2) @(negedge clk);
        rst_n = 1'b1;

        // Let CPU run for 3000 ns
        #3000

        $display("CPU simulation finished.");
        $finish;

    end

    // Monitor memory handshakes
    always @(posedge clk) begin
        if (rst_n && mem_valid && mem_ready) begin
            $display("FETCH: addr=%08h, data=%08h", mem_addr, mem_data);
        end
    end

endmodule
