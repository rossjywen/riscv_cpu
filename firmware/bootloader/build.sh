#!/usr/bin/env bash
set -euo pipefail

# Build only the UART bootloader.
# Usage: bash firmware/bootloader/build.sh
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ $# -ne 0 ]]; then
    echo "Usage: bash firmware/bootloader/build.sh" >&2
    exit 1
fi

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

TARGET_FLAGS=()
if [[ "$CC" == clang ]]; then
    TARGET_FLAGS=(--target=riscv32-unknown-elf -fuse-ld=lld)
fi

# Modern tools require explicit Zicsr for CSR instructions. The installed
# GCC 10 toolchain includes them in its older RV32I definition instead.
ISA=rv32im
if "$CC" "${TARGET_FLAGS[@]}" -march=rv32im_zicsr -mabi=ilp32 \
    -E -x c /dev/null -o /dev/null 2>/dev/null; then
    ISA=rv32im_zicsr
fi

COMMON_FLAGS=(
    "${TARGET_FLAGS[@]}" -march="$ISA" -mabi=ilp32
    -O0 -g -Wall -Wextra
    -ffreestanding -fno-builtin -fno-stack-protector
    -fno-unwind-tables -fno-asynchronous-unwind-tables
    -msmall-data-limit=0 -mno-relax -mno-save-restore
    -nostdlib
    -Wl,--no-relax -Wl,--build-id=none
)

echo "Compiler: $CC ($ISA)"
OUT="$ROOT/build"
mkdir -p "$OUT"
"$CC" "${COMMON_FLAGS[@]}" -T "$ROOT/link.ld" -Wl,-Map,"$OUT/bootloader.map" \
    "$ROOT/crt.s" "$ROOT/main.c" "$ROOT/uart_printf.c" \
    "${EXTRA_LIBS[@]}" -o "$OUT/bootloader.elf"
"$OBJCOPY" -O binary "$OUT/bootloader.elf" "$OUT/bootloader.bin"
"$OBJDUMP" -d "$OUT/bootloader.elf" > "$OUT/bootloader.dis"
if [[ -n "$NM" ]]; then
    "$NM" -n "$OUT/bootloader.elf" > "$OUT/bootloader.symbols"
else
    "$OBJDUMP" -t "$OUT/bootloader.elf" > "$OUT/bootloader.symbols"
fi
python3 "$ROOT/bin_to_mem.py" "$OUT/bootloader.bin" "$ROOT/program.mem" --ram-size 65536
echo "Built bootloader: $OUT/bootloader.bin"
