**implement RV32I instruction decode and execution**
- Implement two-stage instruction decoder
- Implement RV32I instructions:
  - U-type: LUI, AUIPC
  - Jump: JAL, JALR
  - Branch: BEQ, BNE, BLT, BGE, BLTU, BGEU
  - Immediate ALU: ADDI, SLTI, SLTIU, XORI, ORI, ANDI, SLLI, SRLI, SRAI
  - Register ALU: ADD, SUB, SLL, SLT, SLTU, XOR, SRL, SRA, OR, AND
  - FENCE (NOP)
  - Load: LB, LH, LW, LBU, LHU
  - Store: SB, SH, SW
- Implement combinational ALU and barrel shifter
- Implement register file writeback in EXEC state
- Implement PC-relative jumps and conditional branches
- Add instruction alignment checks and trap state




**vivado tcl command line**
```tcl
set_param board.repoPaths [list "/home/ross/code/vivado-boards/new/board_files"]
get_board_parts *arty-a7-a100*
```

**history**
created by Ross in 12 Oct 2026

