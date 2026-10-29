`timescale 1ns / 1ps

// -----------------------------------------------------------------------------
// Bare-metal C firmware testbench
//
// Tests the real CPU and BRAM RTL. The C firmware writes one of these signatures
// to the global "status" variable:
//     0x600D600D : PASS
//     0xBAD0BAD0 : FAIL
//
// Unlike the assembly regression testbench, this test does not assume a fixed
// instruction trace or fixed linker-assigned variable addresses.
// -----------------------------------------------------------------------------
module tb_c_program;

    // -------------------------------------------------------------------------
    // Clock and reset
    // -------------------------------------------------------------------------
    reg clk   = 1'b0;
    reg rst_n = 1'b0;

    always #5 clk = ~clk;  // 100 MHz

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
    // Test status and waveform markers
    // -------------------------------------------------------------------------
    localparam [31:0] STATUS_PASS = 32'h600d600d;
    localparam [31:0] STATUS_FAIL = 32'hbad0bad0;
    localparam integer MAX_CYCLES = 10000;

    integer    tb_cycles = 0;
    reg        tb_pass = 1'b0;
    reg        tb_status_write = 1'b0;
    reg [31:0] tb_status_addr = 32'd0;   // Byte address discovered at runtime
    reg [31:0] tb_status_value = 32'd0;

    // -------------------------------------------------------------------------
    // Firmware completion monitor
    // -------------------------------------------------------------------------
    // The BRAM accepts the store before asserting ready. By mem_valid &&
    // mem_ready, its contents should already reflect the completed write.
    always @(posedge clk) begin
        if (rst_n) begin
            tb_cycles <= tb_cycles + 1;

            if (tb_cycles >= MAX_CYCLES)
                $fatal(1, "TIMEOUT: no C firmware signature after %0d cycles; PC=%08h",
                       tb_cycles, dut.current_pc);

            if (dut.cpu_state == 4'd6)
                $fatal(1, "CPU TRAP: PC=%08h instruction=%08h",
                       dut.current_pc, dut.instr_word);

            if (dut.cpuregs[0] !== 32'd0)
                $fatal(1, "Register x0 changed: %08h", dut.cpuregs[0]);

            if (mem_valid && mem_ready) begin
                if (|mem_addr[29:16])
                    $fatal(1, "Memory address outside 256 KiB RAM: %08h",
                           {mem_addr, 2'b00});

                // The sample main.c writes a full 32-bit signature to status.
                if (mem_wstrb == 4'b1111 &&
                    (mem_wdata == STATUS_PASS || mem_wdata == STATUS_FAIL)) begin

                    tb_status_write <= 1'b1;
                    tb_status_addr  <= {mem_addr, 2'b00};
                    tb_status_value <= mem_wdata;

                    if (mem_wdata == STATUS_FAIL)
                        $fatal(1, "C TEST FAIL: firmware wrote 0xBAD0BAD0 at %08h",
                               {mem_addr, 2'b00});

                    if (u_mem.mem[mem_addr[15:0]] !== STATUS_PASS)
                        $fatal(1, "BRAM WRITE FAIL: status memory contents do not match");

                    if (dut.cpuregs[2][3:0] !== 4'b0000)
                        $fatal(1, "STACK ALIGNMENT FAIL: sp=%08h", dut.cpuregs[2]);

                    tb_pass <= 1'b1;
                    $display("=====================================================");
                    $display("PASS: Bare-metal C firmware completed successfully");
                    $display("  CPU cycles      : %0d", tb_cycles);
                    $display("  Status address  : %08h", {mem_addr, 2'b00});
                    $display("  Status value    : %08h", mem_wdata);
                    $display("  Stack pointer   : %08h", dut.cpuregs[2]);
                    $display("  Last PC         : %08h", dut.current_pc);
                    $display("=====================================================");
                    #1 $finish;  // Let waveform markers settle before stopping.
                end
            end
        end
    end

endmodule
