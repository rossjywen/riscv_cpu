# RV32IM SoC on Arty A7-100T

A simple, multi-cycle 32-bit RISC-V CPU and SoC written in Verilog, targeting the Digilent Arty A7-100T FPGA. The project runs bare-metal C code from on-chip Block RAM and communicates with a host PC through a custom native UART peripheral.


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

The core also implements Zicsr and machine-mode trap/interrupt handling.
**Not yet implemented:** compressed instructions (RVC), RTOS support and instruction/data caches.

## Hardware and Memory Map

- **FPGA board:** Digilent Arty A7-100T (Artix-7 `xc7a100t`)
- **Clock:** 100 MHz board oscillator (`clk` on E3), converted to an 80 MHz SoC clock by Clocking Wizard in `arty_a7_top`
- **CPU reset:** active low (`rst_n` on C2)
- **UART:** `uart_tx` on D10 and `uart_rx` on A9; 115200 baud, 8 data bits, no parity, 1 stop bit
- **Memory interface:** CPU issues 30-bit *word addresses* (`mem_addr = byte_address[31:2]`); BRAM, UART and timer receive these full word addresses directly.

| Byte address range | Size | Device |
| --- | ---: | --- |
| `0x00000000`–`0x0003FFFF` | 256 KiB | On-chip BRAM (program + data) |
| `0x10000000`–`0x10000FFF` | 4 KiB window | Native UART |
| `0x10001000`–`0x10001FFF` | 4 KiB window | Native machine timer (`mtime` / `mtimecmp`) |

BRAM, UART and timer connect directly to the native memory interface.
The interconnect selects one target and returns its ready/data response;
it does not subtract peripheral base addresses. Unmapped addresses complete
with zero data and `mem_error=1`. Unimplemented register offsets within the
UART/timer windows read zero and ignore writes.

### Machine timer registers

The timer runs at 10 kHz (one tick every 100 µs with the 80 MHz SoC clock).
Each register below supports 32-bit reads and byte-enabled writes.

| Byte address | Register |
| --- | --- |
| `0x10001000` | `mtime[31:0]` |
| `0x10001004` | `mtime[63:32]` |
| `0x10001008` | `mtimecmp[31:0]` |
| `0x1000100C` | `mtimecmp[63:32]` |

The timer interrupt feeds the CPU's `irq_timer` input. Firmware must configure
the trap handler and enable `mie.MTIE` and `mstatus.MIE` to take timer interrupts;
the bootloader uses polling. Unimplemented offsets within the
timer window read as zero and ignore writes.

### Native UART registers

`rtl/uart.v` uses the following offsets relative to `UART_BASE = 0x10000000`.
TX and RX each hold one byte, with no FIFO. Writes to TX and Control use
`wstrb[0]`. A TX write while busy is ignored; the polling firmware checks bit 3
before writing.

| Offset | Register | Access | Notes |
| --- | --- | --- | --- |
| `0x00` | RX data | Read | Bits `[7:0]`; reading consumes the received byte |
| `0x04` | TX data | Write | Bits `[7:0]`; reading returns zero |
| `0x08` | Status | Read | Bit 0: RX valid; bit 1: RX full; bit 2: TX idle; bit 3: TX busy; bit 4: interrupts enabled |
| `0x0C` | Control | Read/write | Bit 0: reset TX; bit 1: reset RX; bit 4: interrupt enable; only bit 4 reads back |

Status bits 5/6 report RX overrun/framing error; bit 8 reports TX completion.
Reading Status clears these sticky flags. When enabled, the UART interrupt
remains high until RX data and sticky flags are serviced. The current firmware
continues to use polling with the same register addresses and status bits.

## Bootloader and FPGA Bring-up

Include `rtl/uart.v` and `rtl/arty_a7_top.v` in Vivado's Design Sources.
The board top is `arty_a7_top`; `soc_top` remains independent of vendor clock IP.
With the existing Arty A7-100T project open, run this in the Vivado Tcl Console:

```tcl
source /home/ross/code/riscv_cpu/scripts/create_clocking_wizard.tcl
```

The script creates `clk_wiz_0` if absent: single-ended 100 MHz input, one
80 MHz output, active-low `resetn`, and `locked` enabled. If the IP already
exists, the script checks and reuses it without changing its configuration.
The wrapper connects `resetn` directly to the board's active-low `rst_n`.
The script generates output products and selects `arty_a7_top` as the synthesis
top. An already generated compatible IP does not need to be recreated.
The wrapper holds the SoC in reset until lock, then releases reset after two
80 MHz rising edges.
The UART remains at 115200 baud and the timer remains at 10 kHz.

Keep the board input constraint at **10 ns**. Vivado derives the **12.5 ns**
generated SoC clock through the clock IP. Do not change the physical input
clock constraint to 12.5 ns. The Clocking Wizard's generated XDC supplies the
100 MHz input clock; the board XDC keeps the duplicate definition commented out.
No AXI UART Lite IP or AXI bridge is required.

1. Run `bash firmware/bootloader/build.sh` to build the bootloader for RV32IM with CSR support and the ILP32 ABI. `firmware/bootloader/program.mem` contains the BRAM initialization image.
2. Ensure Vivado's Memory File source points to the **latest** `firmware/bootloader/program.mem`. The BRAM contents are included in the bitstream at configuration time.
3. Run **Synthesis → Implementation → Generate Bitstream** in Vivado. Check `report_clocks` for the 100 MHz input and 80 MHz SoC clock, then verify timing after routing.
4. Connect the board through its Micro-USB JTAG/UART port, open **Hardware Manager**, and choose **Open Target → Auto Connect**.
5. Program the FPGA using `arty_a7_top.bit`; open a serial terminal at 115200 baud and press the board's **RESET** button to enter the bootloader.

Example Linux UART terminal (verify which interface belongs to the board):

```bash
ls -l /dev/serial/by-id/
picocom -b 115200 /dev/ttyUSB1
```

Expected bootloader output after reset:

```text
BOOT READY
```

Exit picocom with **Ctrl+A, then Ctrl+X** before using the uploader. Only one
program should read the board UART at a time.

## UART Application Download

Run the following commands from the repository root. Install the host dependency
in a Python virtual environment (once), then activate that environment in each
new terminal:

```bash
python3 -m venv ~/.venvs/riscv-uart
source ~/.venvs/riscv-uart/bin/activate
python3 -m pip install 'pyserial>=3.5,<4'
```

The uploader is [scripts/uart_upload.py](scripts/uart_upload.py). Specify the
actual UART device and application binary:

```bash
python3 scripts/uart_upload.py /dev/ttyUSB1 /path/to/application.bin
```

Before a new download, press the board's RESET button to return to the bootloader.
The uploader queries the target, sends the image in 128-byte packets, checks
acknowledgements, waits for BRAM CRC verification, and sends RUN. It then displays
application output in the **same terminal by default**. Ctrl+C exits the host
monitor and closes the serial port; the CPU keeps running.

For a test image included in this repository:

```bash
bash tests/build_uart_tx.sh
python3 scripts/uart_upload.py /dev/ttyUSB1 tests/build/uart_tx.bin
```

This application prints `Hello from RISC-V at 0x00010000!` once, followed by
`UART TX test is running.` after each one-second delay.

To download and verify first, then execute later:

```bash
python3 scripts/uart_upload.py /dev/ttyUSB1 tests/build/uart_tx.bin --no-run
python3 scripts/uart_upload.py /dev/ttyUSB1 --run-only
```

`--no-run` exits after verification and leaves the CPU waiting in the bootloader.
`--run-only` sends only RUN, takes no binary path, and starts monitoring by
default. Keep the board powered and **do not press RESET between these two
commands**: RESET clears download readiness and requires another download.

| Option | Behavior / default |
| --- | --- |
| `--monitor` | Display application UART output after RUN; enabled by default |
| `--no-monitor` | Exit after RUN; download debug messages are still displayed |
| `--no-run` | Download and verify only, then exit without monitoring |
| `--run-only` | Execute the image already verified by the bootloader |
| `--baud 115200` | Host baud rate; the current hardware uses 115200, 8N1 |
| `--timeout 10` | Reply timeout in seconds; default 10 |
| `--retries 3` | Additional retries after a failed exchange; default 3; RUN is never retried |

Use `python3 scripts/uart_upload.py --help` for the command-line reference.
After closing the Python monitor, picocom can receive the application's ongoing
output with `picocom -b 115200 /dev/ttyUSB1`; switching monitors does not require
resetting the board.

Link the application at `0x00010000` and pass its raw `.bin` file to the uploader.
Its entry code must initialize its own stack,
trap vector and BSS. The uploader accepts images from 4 bytes to **188 KiB
(192512 bytes)**; application BSS/heap must also fit below its reserved stack.
Application updates use UART and do not
require rebuilding the FPGA bitstream. The bootloader owns
`0x00000000`–`0x0000FFFF`; the application owns the remaining 192 KiB, including
its 4 KiB stack. See the [bootloader implementation](firmware/bootloader/main.c)
and the [test application memory layout](tests/uart_link.ld).

During download, `[boot]` messages report the image size, receive progress,
CRC verification, errors and RUN address. The uploader displays these messages
automatically alongside the binary protocol. The bootloader's small
`uart_printf()` uses the existing polling UART without linking libc.


## Vivado Tcl Commands

```tcl
# Optional: Digilent board files, if they are not already registered
set_param board.repoPaths [list "/home/ross/code/vivado-boards/new/board_files"]
get_board_parts *arty-a7-a100*

# In Hardware Manager, after connecting the hardware target:
set_property PROGRAM.FILE {/home/ross/code/vivado_project/rv32_fpga/rv32_fpga.runs/impl_1/arty_a7_top.bit} [get_hw_devices xc7a100t_0]
program_hw_devices [get_hw_devices xc7a100t_0]

# Inspect timing in an implemented design
report_clocks
report_timing_summary
```


## History

- **2026-10-12:** Project created by Ross.
- **2026-11-01:** RV32IM + AXI UART Lite FPGA bring-up; `From Ross RISC-V` verified on Arty A7-100T.
