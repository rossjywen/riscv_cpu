    .section .text.start, "ax", @progbits
    .globl _start
    .type  _start, @function

# -----------------------------------------------------------------------------
# Bare-metal startup for RV32I
# CPU reset PC = 0x00000000; code and data share the same writable BRAM.
# -----------------------------------------------------------------------------
_start:
    # Stack grows downward from the end of the 256 KiB RAM.
    lui     sp, %hi(__stack_top)
    addi    sp, sp, %lo(__stack_top)

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
