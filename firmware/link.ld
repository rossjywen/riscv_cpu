OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY {
    RAM (rwx) : ORIGIN = 0x00000000, LENGTH = 256K
}

__stack_top = ORIGIN(RAM) + LENGTH(RAM);  /* 0x00040000 */
__stack_bottom = __stack_top - 4K;       /* reserve 4 KiB for stack */

SECTIONS {
    . = ORIGIN(RAM);

    .text : ALIGN(4) {
        KEEP(*(.text.start))
        *(.text .text.*)
    } > RAM

    .rodata : ALIGN(4) {
        *(.rodata .rodata.*)
        . = ALIGN(4);
    } > RAM

    .data : ALIGN(4) {
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
    ASSERT(__image_end <= __stack_bottom, "Program/data overlaps reserved stack")

    /DISCARD/ : {
        *(.eh_frame .eh_frame.*)
        *(.comment)
        *(.note .note.*)
    }
}
