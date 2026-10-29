#!/usr/bin/env bash
set -euo pipefail

# Build RV32IM bare-metal firmware and generate program.mem for $readmemh.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$ROOT/build"
mkdir -p "$OUT"

# Prefer the RISC-V GCC cross-compiler; LLVM is a fallback.
if command -v riscv64-unknown-elf-gcc >/dev/null 2>&1; then
    CC=riscv64-unknown-elf-gcc
    OBJCOPY=riscv64-unknown-elf-objcopy
    OBJDUMP=riscv64-unknown-elf-objdump
    NM=riscv64-unknown-elf-nm
    EXTRA_LIBS=(-lgcc)
elif command -v riscv32-unknown-elf-gcc >/dev/null 2>&1; then
    CC=riscv32-unknown-elf-gcc
    OBJCOPY=riscv32-unknown-elf-objcopy
    OBJDUMP=riscv32-unknown-elf-objdump
    NM=riscv32-unknown-elf-nm
    EXTRA_LIBS=(-lgcc)
elif command -v clang >/dev/null 2>&1 && command -v ld.lld >/dev/null 2>&1 && command -v llvm-objcopy >/dev/null 2>&1; then
    CC=clang
    OBJCOPY=llvm-objcopy
    OBJDUMP=llvm-objdump
    NM=""
    EXTRA_LIBS=()
else
    echo "ERROR: Install a RISC-V bare-metal GCC toolchain or Clang/LLVM." >&2
    exit 1
fi

for tool in "$OBJCOPY" "$OBJDUMP" python3; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "ERROR: Missing tool: $tool" >&2
        exit 1
    }
done

CFLAGS=(
    -march=rv32im -mabi=ilp32
    -O0 -g
    -ffreestanding -fno-builtin -fno-stack-protector
    -fno-unwind-tables -fno-asynchronous-unwind-tables
    -msmall-data-limit=0 -mno-relax -mno-save-restore
    -nostdlib
    -Wl,--no-relax -Wl,--build-id=none
    -Wl,-Map,"$OUT/firmware.map"
    -T "$ROOT/link.ld"
)

if [[ "$CC" == clang ]]; then
    CFLAGS=(--target=riscv32-unknown-elf -fuse-ld=lld "${CFLAGS[@]}")
fi

echo "Compiler: $CC"
"$CC" "${CFLAGS[@]}" "$ROOT/crt.s" "$ROOT/main.c" \
    "${EXTRA_LIBS[@]}" -o "$OUT/firmware.elf"

"$OBJCOPY" -O binary "$OUT/firmware.elf" "$OUT/firmware.bin"
"$OBJDUMP" -d "$OUT/firmware.elf" > "$OUT/firmware.dis"

if [[ -n "$NM" ]]; then
    "$NM" -n "$OUT/firmware.elf" > "$OUT/firmware.symbols"
else
    "$OBJDUMP" -t "$OUT/firmware.elf" > "$OUT/firmware.symbols"
fi

python3 "$ROOT/bin_to_mem.py" "$OUT/firmware.bin" "$ROOT/program.mem"

echo "Build succeeded."
echo "  program.mem             Verilog BRAM image"
echo "  build/firmware.elf      Linked ELF"
echo "  build/firmware.dis      Disassembly"
echo "  build/firmware.symbols  Symbol addresses"
echo "  build/firmware.map      Linker memory map"
