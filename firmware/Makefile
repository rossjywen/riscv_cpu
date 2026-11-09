.DEFAULT_GOAL := all

ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
APP_DIR := $(ROOT)/app
BSP_DIR := $(ROOT)/bsp
KERNEL_DIR := $(ROOT)/os/freertos_kernel
PORT_DIR := $(ROOT)/os/freertos_port
RISCV_PORT_DIR := $(KERNEL_DIR)/portable/GCC/RISC-V
LIBC_DIR := $(ROOT)/libc
BUILD_DIR := $(ROOT)/build
TARGET := $(BUILD_DIR)/app

# This builds the application at 0x10000, independently of the bootloader.
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

CPPFLAGS := -I$(BSP_DIR) -I$(PORT_DIR) \
    -I$(KERNEL_DIR)/include -I$(RISCV_PORT_DIR) -I$(LIBC_DIR)/include
CFLAGS := $(TARGET_FLAGS) -march=$(ISA) -mabi=ilp32 \
    -O0 -g -Wall -Wextra \
    -ffreestanding -fno-builtin -fno-stack-protector \
    -fno-unwind-tables -fno-asynchronous-unwind-tables \
    -msmall-data-limit=0 -mno-relax -mno-save-restore -nostdlib
LDFLAGS := -T$(ROOT)/link.ld -Wl,-Map,$(TARGET).map \
    -Wl,--no-relax -Wl,--build-id=none

APP_MAIN ?= $(APP_DIR)/main.c
SOURCES := $(APP_MAIN) $(PORT_DIR)/freertos_hooks.c \
    $(BSP_DIR)/uart.c $(BSP_DIR)/timer.c $(BSP_DIR)/uart_printf.c \
    $(LIBC_DIR)/string.c $(PORT_DIR)/port_timer.c \
    $(KERNEL_DIR)/tasks.c $(KERNEL_DIR)/queue.c $(KERNEL_DIR)/list.c \
    $(KERNEL_DIR)/portable/MemMang/heap_4.c \
    $(RISCV_PORT_DIR)/port.c $(RISCV_PORT_DIR)/portASM.S
HEADERS := $(wildcard $(APP_DIR)/*.h) $(wildcard $(BSP_DIR)/*.h) \
    $(wildcard $(PORT_DIR)/*.h) $(wildcard $(LIBC_DIR)/include/*.h) \
    $(wildcard $(KERNEL_DIR)/include/*.h) $(wildcard $(RISCV_PORT_DIR)/*.h)

.PHONY: all clean
all: $(TARGET).bin $(TARGET).dis $(TARGET).symbols

$(BUILD_DIR):
	mkdir -p "$@"

$(TARGET).elf: $(SOURCES) $(HEADERS) $(APP_DIR)/crt.s $(ROOT)/link.ld $(ROOT)/Makefile | $(BUILD_DIR)
	$(CC) $(CPPFLAGS) $(CFLAGS) $(LDFLAGS) $(APP_DIR)/crt.s $(SOURCES) $(LDLIBS) -o "$@"

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

clean:
	rm -rf -- "$(BUILD_DIR)"
