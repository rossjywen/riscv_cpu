## Current Progress

- Implemented a multi-cycle CPU core with instruction fetch, decode, execution, and load/store operations.
- Implemented a 32-register, 32-bit integer register file, with `x0` hardwired to zero.
- Implemented integer arithmetic, logical operations, shifts, comparisons, branches, and jumps.
- Implemented byte-, halfword-, and word-sized memory accesses, including signed and unsigned loads, byte write enables, and alignment checks.
- Implemented a ready/valid memory interface and a writable on-chip Block RAM module initialized from `program.mem`.
- Completed an initial RTL cleanup focused on readability and maintainability.

The CPU and load/store logic are implemented in RTL. Full instruction regression testing, bare-metal C execution, and FPGA hardware validation have not yet been completed.

## Supported Instructions

The following instructions are implemented:

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
| Memory ordering | `FENCE` (currently treated as a no-op) |

Compressed instructions, multiply/divide instructions, CSR operations, interrupts, and `ECALL`/`EBREAK` are not supported in the current version.


## vivado tcl command line
```tcl
set_param board.repoPaths [list "/home/ross/code/vivado-boards/new/board_files"]
get_board_parts *arty-a7-a100*
```

## history
created by Ross in 12 Oct 2026

