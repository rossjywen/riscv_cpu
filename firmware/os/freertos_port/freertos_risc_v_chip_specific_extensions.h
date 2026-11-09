#ifndef FREERTOS_RISCV_CHIP_SPECIFIC_EXTENSIONS_H
#define FREERTOS_RISCV_CHIP_SPECIFIC_EXTENSIONS_H

// Use the application interrupt hook in port_timer.c for our 10 kHz timer.
// This disables the upstream MTIME path; the RTL still provides MTIME.
#define portasmHAS_MTIME                 0
#define portasmHAS_SIFIVE_CLINT          0
#define portasmADDITIONAL_CONTEXT_SIZE   0

// RV32IM has no additional registers beyond the standard integer context.
.macro portasmSAVE_ADDITIONAL_REGISTERS
.endm

.macro portasmRESTORE_ADDITIONAL_REGISTERS
.endm

#endif
