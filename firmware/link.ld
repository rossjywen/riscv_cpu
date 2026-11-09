OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY {
    RAM (rwx) : ORIGIN = 0x00010000, LENGTH = 192K
}

__stack_top = ORIGIN(RAM) + LENGTH(RAM); /* 0x00040000 */
__stack_bottom = __stack_top - 4K;      /* Startup stack, then interrupt stack. */
__freertos_irq_stack_top = __stack_top;

SECTIONS {
    . = ORIGIN(RAM);

    .text : ALIGN(4) {
        KEEP(*(.text.start))
        *(.text .text.*)
    } > RAM

    .rodata : ALIGN(4) {
        *(.rodata .rodata.*)
        *(.srodata .srodata.*)
        . = ALIGN(4);
    } > RAM

    .data : ALIGN(4) {
        PROVIDE(__global_pointer$ = . + 0x800);
        *(.sdata .sdata.*)
        *(.data .data.*)
        . = ALIGN(4);
    } > RAM

    .bss (NOLOAD) : ALIGN(4) {
        __bss_start = .;
        *(.sbss .sbss.*)
        *(.bss .bss.*)
        *(COMMON)
        . = ALIGN(4);
        __bss_end = .;
    } > RAM

    __image_end = .;
    ASSERT(_start == ORIGIN(RAM), "Application entry must be at 0x00010000")
    ASSERT(__image_end <= __stack_bottom, "Application image/BSS overlaps reserved stack")

    /DISCARD/ : {
        *(.eh_frame .eh_frame.*)
        *(.comment)
        *(.note .note.*)
    }
}
