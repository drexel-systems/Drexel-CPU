# =============================================================================
# CS281 Lab 2 — Blinky with Timer Interrupt
# RISC-V RV32IM bare-metal build system
#
# Targets
#   make / make all    — assemble + link  →  build/lab2.elf
#   make clean         — remove build/
#   make run           — load into Renode (headless) and run
#   make run-debug     — load into Renode with GDB stub, halted
#   make debug-attach  — attach riscv64-elf-gdb (command-line)
#   make uart-connect  — telnet to UART on port 3456
#   make monitor-connect — telnet to Renode monitor on port 1234
#   make disasm        — disassemble ELF to stdout
# =============================================================================

# ── Toolchain ─────────────────────────────────────────────────────────────────
CROSS   := riscv64-elf
AS      := $(CROSS)-as
LD      := $(CROSS)-ld
OBJDUMP := $(CROSS)-objdump
GDB     := $(CROSS)-gdb

# ── Paths ─────────────────────────────────────────────────────────────────────
HARDWARE := ../hardware
LIB      := $(HARDWARE)/lib
BUILD    := build

# ── Flags ─────────────────────────────────────────────────────────────────────
ASFLAGS  := -march=rv32im_zicsr -mabi=ilp32 -g
LDFLAGS  := -T $(LIB)/cs281.ld -nostdlib -Map=$(BUILD)/lab2.map -m elf32lriscv

# ── Sources and Objects ───────────────────────────────────────────────────────
LIB_SRCS := $(LIB)/startup.S \
             $(LIB)/uart.S \
             $(LIB)/exit.S

APP_SRCS := main.S

LIB_OBJS := $(patsubst $(LIB)/%.S, $(BUILD)/%.o, $(LIB_SRCS))
APP_OBJS := $(patsubst %.S, $(BUILD)/%.o, $(APP_SRCS))
OBJS     := $(LIB_OBJS) $(APP_OBJS)

TARGET   := $(BUILD)/lab2.elf

# ── Renode / Debug Ports ──────────────────────────────────────────────────────
RENODE    := renode
MON_PORT  := 1234
UART_PORT := 3456
GDB_PORT  := 3333

RESC_RUN  := $(HARDWARE)/cs281_run.resc
RESC_DBG  := $(HARDWARE)/cs281_debug.resc

# ── Default Target ────────────────────────────────────────────────────────────
.PHONY: all
all: $(BUILD) $(TARGET)

$(BUILD):
	mkdir -p $(BUILD)

# ── Compile library sources ───────────────────────────────────────────────────
$(BUILD)/%.o: $(LIB)/%.S | $(BUILD)
	$(AS) $(ASFLAGS) -o $@ $<

# ── Compile application sources ───────────────────────────────────────────────
$(BUILD)/%.o: %.S | $(BUILD)
	$(AS) $(ASFLAGS) -o $@ $<

# ── Link ──────────────────────────────────────────────────────────────────────
$(TARGET): $(OBJS)
	$(LD) $(LDFLAGS) -o $@ $^
	@echo ""
	@echo "Memory usage:"
	@$(OBJDUMP) -h $@ | awk '/\.(text|rodata|data|bss)/{printf "  %-12s 0x%s bytes\n", $$2, $$3}'
	@echo ""
	@echo "  Output: $@"
	@echo ""

# ── Clean ─────────────────────────────────────────────────────────────────────
.PHONY: clean
clean:
	rm -rf $(BUILD)

# ── Run (headless) ────────────────────────────────────────────────────────────
.PHONY: run
run: $(TARGET)
	@echo "──────────────────────────────────────────────────"
	@echo " Starting Renode (headless)"
	@echo " UART    → telnet localhost $(UART_PORT)  (make uart-connect)"
	@echo " Monitor → telnet localhost $(MON_PORT)   (make monitor-connect)"
	@echo "──────────────────────────────────────────────────"
	$(RENODE) --plain --disable-xwt \
		-e '$$bin=@$(abspath $(TARGET)); $$platform=@$(abspath $(HARDWARE)/cs281_board.repl); i @$(abspath $(RESC_RUN))'

# ── Run Debug ─────────────────────────────────────────────────────────────────
.PHONY: run-debug
run-debug: $(TARGET)
	@echo "──────────────────────────────────────────────────"
	@echo " Starting Renode debug session"
	@echo " GDB stub  → localhost:$(GDB_PORT)"
	@echo " UART      → telnet localhost $(UART_PORT)  (make uart-connect)"
	@echo " Monitor   → telnet localhost $(MON_PORT)   (make monitor-connect)"
	@echo " CPU is HALTED — connect GDB or press F5 in VS Code"
	@echo "──────────────────────────────────────────────────"
	$(RENODE) --plain --disable-xwt \
		-e '$$bin=@$(abspath $(TARGET)); $$platform=@$(abspath $(HARDWARE)/cs281_board.repl); i @$(abspath $(RESC_DBG))'

# ── Attach GDB ────────────────────────────────────────────────────────────────
.PHONY: debug-attach
debug-attach: $(TARGET)
	$(GDB) $(TARGET) \
		-ex "set architecture riscv:rv32" \
		-ex "target remote localhost:$(GDB_PORT)" \
		-ex "layout asm" \
		-ex "layout regs"

# ── Connect to UART terminal ──────────────────────────────────────────────────
.PHONY: uart-connect
uart-connect:
	@echo "Connecting to UART on port $(UART_PORT)  (Ctrl-] then 'quit' to exit)"
	telnet localhost $(UART_PORT)

# ── Connect to Renode monitor ─────────────────────────────────────────────────
.PHONY: monitor-connect
monitor-connect:
	@echo "Connecting to Renode monitor on port $(MON_PORT)  (type 'quit' to exit Renode)"
	telnet localhost $(MON_PORT)

# ── Disassemble ───────────────────────────────────────────────────────────────
.PHONY: disasm
disasm: $(TARGET)
	$(OBJDUMP) -d -M no-aliases $<
