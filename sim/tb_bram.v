`timescale 1ns / 1ps

module tb_bram;

    reg clk = 0;
    reg rst_n = 0;
    reg valid = 0;
    reg [9:0] addr = 0;

    wire ready;
    wire [31:0] data;

    // Generate 100 MHz clock
    always #5 clk = ~clk;

    // Instantiate DUT
    bram dut (
        .clk   (clk),
        .rst_n (rst_n),
        .valid (valid),
        .addr  (addr),
        .ready (ready),
        .data  (data)
    );

    initial begin

        // Reset
        repeat (2) @(negedge clk);
        rst_n = 1;

        // Read first instruction
        @(negedge clk);
        valid = 1;
        addr = 0;

        // Wait for BRAM response
        wait (ready === 1'b1);

        // Complete handshake
        @(posedge clk);
        #1;

        // Check instruction
        if (data !== 32'h00500093)
            $fatal(1, "BRAM data mismatch!");

        $display("BRAM read PASS: %h", data);

        @(negedge clk);
        valid = 0;

        #10;
        $finish;

    end

endmodule
