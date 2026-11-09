    .section .text.start, "ax", @progbits
    .globl _start
    .type _start, @function

# The bootloader jumps here at byte address 0x00010000.
_start:
    csrci   mstatus, 8
    csrw    mie, zero

    lui     sp, %hi(__stack_top)
    addi    sp, sp, %lo(__stack_top)

    # Prevent linker relaxation from assuming gp was already initialized.
    .option push
    .option norelax
    lui     gp, %hi(__global_pointer$)
    addi    gp, gp, %lo(__global_pointer$)
    .option pop

    lui     t0, %hi(trap_halt)
    addi    t0, t0, %lo(trap_halt)
    csrw    mtvec, t0

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
    # .data is already downloaded to its runtime RAM address in the binary.
    jal     ra, main
halt:
    jal     zero, halt
    .size _start, . - _start

    .balign 4
trap_halt:
    # Keep the fault context in t0/t1/t2 for debugging.
    csrr    t0, mcause
    csrr    t1, mepc
    csrr    t2, mtval
trap_loop:
    jal     zero, trap_loop
