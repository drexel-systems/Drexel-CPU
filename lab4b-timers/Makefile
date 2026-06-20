# =============================================================================
# CS281 Lab 4b — Interrupt-Based Timers
# RISC-V RV32IM bare-metal build system
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
LDFLAGS  := -T $(LIB)/cs281.ld -nostdlib -Map=$(BUILD)/lab4b.map -m elf32lriscv

# ── Sources and Objects ───────────────────────────────────────────────────────
LIB_SRCS := $(LIB)/startup.S \
             $(LIB)/uart.S \
             $(LIB)/exit.S

APP_SRCS := main.S

LIB_OBJS := $(patsubst $(LIB)/%.S, $(BUILD)/%.o, $(LIB_SRCS))
APP_OBJS := $(patsubst %.S, $(BUILD)/%.o, $(APP_SRCS))
OBJS     := $(LIB_OBJS) $(APP_OBJS)

TARGET   := $(BUILD)/lab4b.elf

# ── Renode / Debug Ports ──────────────────────────────────────────────────────
RENODE    := renode
MON_PORT  := 1234
UART_PORT := 3456
GDB_PORT  := 3333

RESC_RUN  := lab4b_run.resc
RESC_DBG  := lab4b_debug.resc

# ── OS detection (for kill-renode) ────────────────────────────────────────────
ifeq ($(OS),Windows_NT)
    KILL_RENODE := taskkill /F /IM renode.exe 2>nul & ping -n 2 127.0.0.1 >nul & exit /b 0
else
    KILL_RENODE := pkill -f renode 2>/dev/null; sleep 0.5; true
endif

# ── Default Target ────────────────────────────────────────────────────────────
.PHONY: all
all: $(BUILD) $(TARGET)

$(BUILD):
	mkdir -p $(BUILD)

$(BUILD)/%.o: $(LIB)/%.S | $(BUILD)
	$(AS) $(ASFLAGS) -o $@ $<

$(BUILD)/%.o: %.S | $(BUILD)
	$(AS) $(ASFLAGS) -o $@ $<

$(TARGET): $(OBJS)
	$(LD) $(LDFLAGS) -o $@ $^
	@echo ""
	@echo "Memory usage:"
	@$(OBJDUMP) -h $@ | awk '/\.(text|rodata|data|bss)/{printf "  %-12s 0x%s bytes\n", $$2, $$3}'
	@echo ""
	@echo "  Output: $@"
	@echo ""

.PHONY: clean
clean:
	rm -rf $(BUILD)

# ── Kill any running Renode (cross-platform) ──────────────────────────────────
.PHONY: kill-renode
kill-renode:
	-$(KILL_RENODE)

.PHONY: run
run: $(TARGET) kill-renode
	@echo "──────────────────────────────────────────────────"
	@echo " Starting Renode (headless)"
	@echo " UART    → telnet localhost $(UART_PORT)  (make uart-connect)"
	@echo " Monitor → telnet localhost $(MON_PORT)   (make monitor-connect)"
	@echo "──────────────────────────────────────────────────"
	$(RENODE) --disable-xwt \
		-e '$$bin=@$(abspath $(TARGET)); $$platform=@$(abspath $(HARDWARE)/cs281_board.repl); i @$(abspath $(RESC_RUN))'

.PHONY: run-debug
run-debug: $(TARGET) kill-renode
	@echo "──────────────────────────────────────────────────"
	@echo " Starting Renode debug session"
	@echo " GDB stub  → localhost:$(GDB_PORT)"
	@echo " UART      → telnet localhost $(UART_PORT)  (make uart-connect)"
	@echo " Monitor   → telnet localhost $(MON_PORT)   (make monitor-connect)"
	@echo " CPU is HALTED — connect GDB or press F5 in VS Code"
	@echo "──────────────────────────────────────────────────"
	$(RENODE) --disable-xwt \
		-e '$$bin=@$(abspath $(TARGET)); $$platform=@$(abspath $(HARDWARE)/cs281_board.repl); i @$(abspath $(RESC_DBG))'

.PHONY: debug-attach
debug-attach: $(TARGET)
	$(GDB) $(TARGET) \
		-ex "set architecture riscv:rv32" \
		-ex "target remote localhost:$(GDB_PORT)" \
		-ex "layout asm" \
		-ex "layout regs"

.PHONY: uart-connect
uart-connect:
	@echo "Connecting to UART on port $(UART_PORT)  (Ctrl-] then 'quit' to exit)"
	telnet localhost $(UART_PORT)

.PHONY: monitor-connect
monitor-connect:
	@echo "Connecting to Renode monitor on port $(MON_PORT)  (type 'quit' to exit Renode)"
	telnet localhost $(MON_PORT)

.PHONY: disasm
disasm: $(TARGET)
	$(OBJDUMP) -d -M no-aliases $<
