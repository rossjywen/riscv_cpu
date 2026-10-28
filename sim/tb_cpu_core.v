`timescale 1ns / 1ps

// -----------------------------------------------------------------------------
// Generic CPU simulation testbench
//
// Runs any program loaded by bram.v from program.mem.
// No instruction-specific scoreboard, timeout, $finish, or $stop.
// Use "run 10 us" (or another finite duration) in Vivado to inspect waveforms.
// -----------------------------------------------------------------------------
module tb_cpu_core;

    // -------------------------------------------------------------------------
    // Clock and reset
    // -------------------------------------------------------------------------
    reg clk   = 1'b0;
    reg rst_n = 1'b0;

    always #5 clk = ~clk;  // 100 MHz, 10 ns period

    initial begin
        repeat (5) @(negedge clk);
        rst_n = 1'b1;
    end

    // -------------------------------------------------------------------------
    // CPU <-> BRAM interface
    // -------------------------------------------------------------------------
    wire        mem_valid;
    wire        mem_ready;
    wire [29:0] mem_addr;
    wire [31:0] mem_wdata;
    wire [3:0]  mem_wstrb;
    wire [31:0] mem_data;

    // -------------------------------------------------------------------------
    // CPU under test
    // -------------------------------------------------------------------------
    cpu_core dut (
        .rst_n     (rst_n),
        .clk       (clk),
        .mem_ready (mem_ready),
        .mem_data  (mem_data),
        .mem_valid (mem_valid),
        .mem_addr  (mem_addr),
        .mem_wdata (mem_wdata),
        .mem_wstrb (mem_wstrb)
    );

    // -------------------------------------------------------------------------
    // Actual on-chip RAM RTL (loads program.mem using $readmemh)
    // -------------------------------------------------------------------------
    bram u_mem (
        .rst_n (rst_n),
        .clk   (clk),
        .valid (mem_valid),
        .addr  (mem_addr),
        .wstrb (mem_wstrb),
        .wdata (mem_wdata),
        .ready (mem_ready),
        .data  (mem_data)
    );

    // -------------------------------------------------------------------------
    // Optional waveform markers (no effect on CPU execution)
    // -------------------------------------------------------------------------
    integer tb_cycle = 0;

    always @(posedge clk) begin
        if (!rst_n)
            tb_cycle <= 0;
        else
            tb_cycle <= tb_cycle + 1;
    end

endmodule
