OUTPUT_ARCH(riscv)
ENTRY(_start)

/* The Makefile supplies __ram_origin and __ram_size for each image. */
MEMORY {
    RAM (rwx) : ORIGIN = __ram_origin, LENGTH = __ram_size
}

__stack_top = ORIGIN(RAM) + LENGTH(RAM);
__stack_bottom = __stack_top - 4K; /* Startup stack; reused by app interrupts. */
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
    ASSERT(_start == ORIGIN(RAM), "Image entry must be at the start of its RAM region")
    ASSERT(__image_end <= __stack_bottom, "Image/BSS overlaps reserved stack")

    /DISCARD/ : {
        *(.eh_frame .eh_frame.*)
        *(.comment)
        *(.note .note.*)
    }
}
