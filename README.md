# RV32IM SoC on Arty A7-100T

A simple, multi-cycle 32-bit RISC-V CPU and SoC written in Verilog, targeting the Digilent Arty A7-100T FPGA. The project currently runs bare-metal C code from on-chip Block RAM and communicates with a host PC through an AXI4-Lite UART peripheral.

## Current Progress

- Implemented a multi-cycle CPU core with instruction fetch, decode, execute, and load/store operations (not yet a pipelined CPU).
- Implemented an RV32I integer register file with 32 × 32-bit registers; `x0` always reads as zero.
- Implemented integer ALU, shifts, comparisons, branches, jumps, and byte/halfword/word loads and stores, including sign extension and byte write enables.
- Implemented all eight RV32M multiply/divide/remainder instructions in a separate `rv32m_unit` module. Multiplication has been divided into two clock stages to improve timing; division/remainder use an iterative implementation.
- Implemented a ready/valid native memory interface, an address decoder, and 256 KiB of writable on-chip Block RAM initialized from `program.mem`.
- Implemented a native-memory-to-AXI4-Lite master bridge and integrated the AMD AXI UART Lite IP.
- Built and executed a bare-metal C UART "Hello RISC-V!" program on the physical FPGA. UART transmission and the CPU reset button have been verified.
- Completed synthesis, placement, routing, and bitstream generation in Vivado 2025.1 for the Arty A7-100T.

## Supported Instructions

| Category | Instructions |
| --- | --- |
| Upper immediates | `LUI`, `AUIPC` |
| Jumps | `JAL`, `JALR` |
| Conditional branches | `BEQ`, `BNE`, `BLT`, `BGE`, `BLTU`, `BGEU` |
| Loads | `LB`, `LH`, `LW`, `LBU`, `LHU` |
| Stores | `SB`, `SH`, `SW` |
| Integer immediate | `ADDI`, `SLTI`, `SLTIU`, `XORI`, `ORI`, `ANDI` |
| Shift immediate | `SLLI`, `SRLI`, `SRAI` |
| Integer register | `ADD`, `SUB`, `SLL`, `SLT`, `SLTU`, `XOR`, `SRL`, `SRA`, `OR`, `AND` |
| Multiply (RV32M) | `MUL`, `MULH`, `MULHSU`, `MULHU` |
| Divide / remainder (RV32M) | `DIV`, `DIVU`, `REM`, `REMU` |
| Memory ordering | `FENCE` (currently treated as a no-op) |

**Not yet implemented:** compressed instructions (RVC), CSRs, machine-mode interrupts/exceptions, and `ECALL`/`EBREAK`. RTOS support and instruction/data caches are future work.

## Hardware and Memory Map

- **FPGA board:** Digilent Arty A7-100T (Artix-7 `xc7a100t`)
- **Clock:** 100 MHz (`clk` on E3)
- **CPU reset:** active low (`rst_n` on C2)
- **UART:** `uart_tx` on D10 and `uart_rx` on A9; 115200 baud, 8 data bits, no parity, 1 stop bit
- **Memory interface:** CPU issues 30-bit *word addresses* (`mem_addr = byte_address[31:2]`); the AXI bridge reconstructs the corresponding byte addresses.

| Byte address range | Size | Device |
| --- | ---: | --- |
| `0x00000000`–`0x0003FFFF` | 256 KiB | On-chip BRAM (program + data) |
| `0x10000000`–`0x10000FFF` | 4 KiB window | AXI UART Lite |
| `0x10001000`–`0x10001FFF` | 4 KiB window | Native machine timer (`mtime` / `mtimecmp`) |

The timer connects directly to the native memory interface, alongside BRAM.
Only the UART uses the AXI4-Lite bridge. Timer requests retain the full word
address; the interconnect does not subtract the timer base address.

### Machine timer registers

The timer runs at 10 kHz (one tick every 100 µs with the 100 MHz input clock).
Each register below supports 32-bit reads and byte-enabled writes.

| Byte address | Register |
| --- | --- |
| `0x10001000` | `mtime[31:0]` |
| `0x10001004` | `mtime[63:32]` |
| `0x10001008` | `mtimecmp[31:0]` |
| `0x1000100C` | `mtimecmp[63:32]` |

The timer interrupt feeds the CPU's `irq_timer` input. Firmware must configure
the trap handler and enable `mie.MTIE` and `mstatus.MIE` to take timer interrupts;
the current UART demo still uses polling. Unimplemented offsets within the
timer window read as zero and ignore writes.

### AXI UART Lite registers

The UART IP uses the following offsets relative to `UART_BASE = 0x10000000`:

| Offset | Register | Access | Notes |
| --- | --- | --- | --- |
| `0x00` | RX FIFO | Read | Received data is in bits `[7:0]` |
| `0x04` | TX FIFO | Write | Transmit data is in bits `[7:0]` |
| `0x08` | Status | Read | Bit 0: RX data valid; bit 3: TX FIFO full |
| `0x0C` | Control | Write | Bit 0: reset TX FIFO; bit 1: reset RX FIFO; bit 4: interrupt enable |

The current firmware uses polling, so no interrupt controller or interrupt-related ISA/CSR support is required for UART transmission/reception.

## Firmware and FPGA Bring-up

1. Build the bare-metal firmware using the existing firmware build script. The RISC-V GCC target uses `-march=rv32im -mabi=ilp32`.
2. Ensure Vivado's Memory File source points to the **latest** `program.mem`. The BRAM contents are included in the bitstream at configuration time.
3. Run **Synthesis → Implementation → Generate Bitstream** in Vivado. Check timing against the 10 ns clock constraint.
4. Connect the board through its Micro-USB JTAG/UART port, open **Hardware Manager**, and choose **Open Target → Auto Connect**.
5. Program the FPGA using `soc_top.bit`; open a serial terminal at 115200 baud and press the board's **RESET** button to run the firmware again.

Example Linux UART terminal (verify which interface belongs to the board):

```bash
ls -l /dev/serial/by-id/
picocom -b 115200 /dev/ttyUSB1
```

Expected first bring-up output:

```text
From Ross RISC-V
```


## Vivado Tcl Commands

```tcl
# Optional: Digilent board files, if they are not already registered
set_param board.repoPaths [list "/home/ross/code/vivado-boards/new/board_files"]
get_board_parts *arty-a7-a100*

# In Hardware Manager, after connecting the hardware target:
set_property PROGRAM.FILE {/home/ross/code/vivado_project/rv32_fpga/rv32_fpga.runs/impl_1/soc_top.bit} [get_hw_devices xc7a100t_0]
program_hw_devices [get_hw_devices xc7a100t_0]

# Inspect timing in an implemented design
report_clocks
report_timing_summary
```


## History

- **2026-10-12:** Project created by Ross.
- **2026-11-01:** RV32IM + AXI UART Lite FPGA bring-up; `From Ross RISC-V` verified on Arty A7-100T.
