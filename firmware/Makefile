.DEFAULT_GOAL := all

ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
APP_DIR := $(ROOT)/app
BOOTLOADER_DIR := $(ROOT)/bootloader
BSP_DIR := $(ROOT)/bsp
KERNEL_DIR := $(ROOT)/os/freertos_kernel
PORT_DIR := $(ROOT)/os/freertos_port
RISCV_PORT_DIR := $(KERNEL_DIR)/portable/GCC/RISC-V
LIBC_DIR := $(ROOT)/libc
SCRIPTS_DIR := $(abspath $(ROOT)/../scripts)
BUILD_DIR := $(ROOT)/build
BOOTLOADER_BUILD_DIR := $(BOOTLOADER_DIR)/build
APP_TARGET := $(BUILD_DIR)/app
BOOTLOADER_TARGET := $(BOOTLOADER_BUILD_DIR)/bootloader

# Both images use link.ld, with separate RAM regions and startup code.
BOOTLOADER_RAM_ORIGIN := 0x00000000
BOOTLOADER_RAM_SIZE := 65536
APP_RAM_ORIGIN := 0x00010000
APP_RAM_SIZE := 196608

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
APP_CPPFLAGS := -I$(PORT_DIR) \
    -I$(KERNEL_DIR)/include -I$(RISCV_PORT_DIR) -I$(LIBC_DIR)/include
CFLAGS := $(TARGET_FLAGS) -march=$(ISA) -mabi=ilp32 \
    -O0 -g -Wall -Wextra \
    -ffreestanding -fno-builtin -fno-stack-protector \
    -fno-unwind-tables -fno-asynchronous-unwind-tables \
    -msmall-data-limit=0 -mno-relax -mno-save-restore -nostdlib
LDFLAGS := -T$(ROOT)/link.ld -Wl,--no-relax -Wl,--build-id=none

# Each image links its own copy of the shared BSP sources.
BSP_SOURCES := $(BSP_DIR)/uart.c $(BSP_DIR)/timer.c $(BSP_DIR)/uart_printf.c
BSP_HEADERS := $(wildcard $(BSP_DIR)/*.h)

BOOTLOADER_SOURCES := $(BOOTLOADER_DIR)/main.c $(BSP_SOURCES)
BOOTLOADER_HEADERS := $(BOOTLOADER_DIR)/protocol.h $(BSP_HEADERS)

APP_MAIN ?= $(APP_DIR)/main.c
APP_SOURCES := $(APP_MAIN) $(PORT_DIR)/freertos_hooks.c $(BSP_SOURCES) \
    $(LIBC_DIR)/string.c $(PORT_DIR)/port_timer.c \
    $(KERNEL_DIR)/tasks.c $(KERNEL_DIR)/queue.c $(KERNEL_DIR)/list.c \
    $(KERNEL_DIR)/portable/MemMang/heap_4.c \
    $(RISCV_PORT_DIR)/port.c $(RISCV_PORT_DIR)/portASM.S
APP_HEADERS := $(wildcard $(APP_DIR)/*.h) $(BSP_HEADERS) \
    $(wildcard $(PORT_DIR)/*.h) $(wildcard $(LIBC_DIR)/include/*.h) \
    $(wildcard $(KERNEL_DIR)/include/*.h) $(wildcard $(RISCV_PORT_DIR)/*.h)

.PHONY: all bootloader app clean
all: bootloader app

bootloader: $(BOOTLOADER_TARGET).bin $(BOOTLOADER_TARGET).dis \
    $(BOOTLOADER_TARGET).symbols $(BOOTLOADER_DIR)/program.mem

app: $(APP_TARGET).bin $(APP_TARGET).dis $(APP_TARGET).symbols

$(BUILD_DIR) $(BOOTLOADER_BUILD_DIR):
	mkdir -p "$@"

$(BOOTLOADER_TARGET).elf: $(BOOTLOADER_SOURCES) $(BOOTLOADER_HEADERS) $(BOOTLOADER_DIR)/crt.s $(ROOT)/link.ld $(ROOT)/Makefile | $(BOOTLOADER_BUILD_DIR)
	$(CC) $(CPPFLAGS) $(CFLAGS) \
	    -Wl,--defsym=__ram_origin=$(BOOTLOADER_RAM_ORIGIN) \
	    -Wl,--defsym=__ram_size=$(BOOTLOADER_RAM_SIZE) \
	    $(LDFLAGS) -Wl,-Map,$(BOOTLOADER_TARGET).map \
	    $(BOOTLOADER_DIR)/crt.s $(BOOTLOADER_SOURCES) $(LDLIBS) -o "$@"

$(APP_TARGET).elf: $(APP_SOURCES) $(APP_HEADERS) $(APP_DIR)/crt.s $(ROOT)/link.ld $(ROOT)/Makefile | $(BUILD_DIR)
	$(CC) $(CPPFLAGS) $(APP_CPPFLAGS) $(CFLAGS) \
	    -Wl,--defsym=__ram_origin=$(APP_RAM_ORIGIN) \
	    -Wl,--defsym=__ram_size=$(APP_RAM_SIZE) \
	    $(LDFLAGS) -Wl,-Map,$(APP_TARGET).map \
	    $(APP_DIR)/crt.s $(APP_SOURCES) $(LDLIBS) -o "$@"

$(APP_TARGET).bin $(BOOTLOADER_TARGET).bin: %.bin: %.elf
	$(OBJCOPY) -O binary "$<" "$@"

$(APP_TARGET).dis $(BOOTLOADER_TARGET).dis: %.dis: %.elf
	$(OBJDUMP) -d "$<" > "$@"

$(APP_TARGET).symbols $(BOOTLOADER_TARGET).symbols: %.symbols: %.elf
ifneq ($(NM),)
	$(NM) -n "$<" > "$@"
else
	$(OBJDUMP) -t "$<" > "$@"
endif

$(BOOTLOADER_DIR)/program.mem: $(BOOTLOADER_TARGET).bin $(SCRIPTS_DIR)/bin_to_mem.py
	python3 "$(SCRIPTS_DIR)/bin_to_mem.py" "$<" "$@" --ram-size $(BOOTLOADER_RAM_SIZE)

clean:
	rm -rf -- "$(BUILD_DIR)" "$(BOOTLOADER_BUILD_DIR)" "$(BOOTLOADER_DIR)/program.mem"
