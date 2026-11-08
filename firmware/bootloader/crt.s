    .section .text.start, "ax", @progbits
    .globl _start
    .type  _start, @function

# -----------------------------------------------------------------------------
# Bootloader startup at reset address zero. link.ld reserves 64 KiB of RAM.
# -----------------------------------------------------------------------------
_start:
    # Stack grows downward from this image's reserved stack area.
    lui     sp, %hi(__stack_top)
    addi    sp, sp, %lo(__stack_top)

    # Establish a known M-mode environment before calling any C code.
    csrci   mstatus, 8
    csrw    mie, zero
    lui     t0, %hi(trap_halt)
    addi    t0, t0, %lo(trap_halt)
    csrw    mtvec, t0

    # Initialize .bss to zero (word-aligned bounds from linker script).
    lui     t0, %hi(__bss_start)
    addi    t0, t0, %lo(__bss_start)
    lui     t1, %hi(__bss_end)
    addi    t1, t1, %lo(__bss_end)

bss_clear:
    bgeu    t0, t1, bss_done
    sw      zero, 0(t0)
    addi    t0, t0, 4
    jal     zero, bss_clear

bss_done:
    # .data is already initialized in program.mem at its runtime address.
    jal     ra, main

# main() should not return, but halt safely if it does.
halt:
    jal     zero, halt

    .size _start, . - _start

    .balign 4
trap_halt:
    # Leave the fault context in t0/t1/t2 for simulation or debugger inspection.
    csrr    t0, mcause
    csrr    t1, mepc
    csrr    t2, mtval
trap_loop:
    jal     zero, trap_loop
