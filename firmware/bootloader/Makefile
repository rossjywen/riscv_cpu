.DEFAULT_GOAL := all

ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
BSP_DIR := $(abspath $(ROOT)/../bsp)
BUILD_DIR := $(ROOT)/build
TARGET := $(BUILD_DIR)/bootloader

# Prefer the RISC-V GCC toolchain; retain LLVM as a fallback.
ifneq ($(shell command -v riscv64-unknown-elf-gcc 2>/dev/null),)
CC := riscv64-unknown-elf-gcc
OBJCOPY := riscv64-unknown-elf-objcopy
OBJDUMP := riscv64-unknown-elf-objdump
NM := riscv64-unknown-elf-nm
LDLIBS := -lgcc
else ifneq ($(shell command -v riscv32-unknown-elf-gcc 2>/dev/null),)
CC := riscv32-unknown-elf-gcc
OBJCOPY := riscv32-unknown-elf-objcopy
OBJDUMP := riscv32-unknown-elf-objdump
NM := riscv32-unknown-elf-nm
LDLIBS := -lgcc
else ifneq ($(shell command -v clang 2>/dev/null),)
CC := clang
OBJCOPY := llvm-objcopy
OBJDUMP := llvm-objdump
NM :=
TARGET_FLAGS := --target=riscv32-unknown-elf -fuse-ld=lld
else
$(error Install a RISC-V bare-metal GCC toolchain or Clang/LLVM)
endif

# Older GCC includes CSR instructions in RV32I; newer tools require Zicsr.
ISA := $(shell $(CC) $(TARGET_FLAGS) -march=rv32im_zicsr -mabi=ilp32 \
    -E -x c /dev/null -o /dev/null 2>/dev/null \
    && echo rv32im_zicsr || echo rv32im)

CPPFLAGS := -I$(BSP_DIR)
CFLAGS := $(TARGET_FLAGS) -march=$(ISA) -mabi=ilp32 \
    -O0 -g -Wall -Wextra \
    -ffreestanding -fno-builtin -fno-stack-protector \
    -fno-unwind-tables -fno-asynchronous-unwind-tables \
    -msmall-data-limit=0 -mno-relax -mno-save-restore -nostdlib
LDFLAGS := -T$(ROOT)/link.ld -Wl,-Map,$(TARGET).map \
    -Wl,--no-relax -Wl,--build-id=none

# Each firmware image links its own copy of these shared BSP sources.
SOURCES := $(ROOT)/main.c $(BSP_DIR)/uart.c $(BSP_DIR)/timer.c $(BSP_DIR)/uart_printf.c
HEADERS := $(ROOT)/protocol.h $(wildcard $(BSP_DIR)/*.h)

.PHONY: all clean
all: $(TARGET).bin $(TARGET).dis $(TARGET).symbols $(ROOT)/program.mem

$(BUILD_DIR):
	mkdir -p "$@"

$(TARGET).elf: $(SOURCES) $(HEADERS) $(ROOT)/crt.s $(ROOT)/link.ld $(ROOT)/Makefile | $(BUILD_DIR)
	$(CC) $(CPPFLAGS) $(CFLAGS) $(LDFLAGS) $(ROOT)/crt.s $(SOURCES) $(LDLIBS) -o "$@"

$(TARGET).bin: $(TARGET).elf
	$(OBJCOPY) -O binary "$<" "$@"

$(TARGET).dis: $(TARGET).elf
	$(OBJDUMP) -d "$<" > "$@"

$(TARGET).symbols: $(TARGET).elf
ifneq ($(NM),)
	$(NM) -n "$<" > "$@"
else
	$(OBJDUMP) -t "$<" > "$@"
endif

$(ROOT)/program.mem: $(TARGET).bin $(ROOT)/bin_to_mem.py
	python3 "$(ROOT)/bin_to_mem.py" "$<" "$@" --ram-size 65536

clean:
	rm -rf -- "$(BUILD_DIR)" "$(ROOT)/program.mem"
