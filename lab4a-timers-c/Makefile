# =============================================================================
# CS281 Lab 4a — Interrupt-Based Timers (C)
# RISC-V RV32IM bare-metal build system
# =============================================================================

# ── Toolchain ─────────────────────────────────────────────────────────────────
CROSS   := riscv64-elf
CC      := $(CROSS)-gcc
OBJDUMP := $(CROSS)-objdump
GDB     := $(CROSS)-gdb

# ── Paths ─────────────────────────────────────────────────────────────────────
HARDWARE := ../hardware
LIB      := $(HARDWARE)/lib
BUILD    := build

# ── Flags ─────────────────────────────────────────────────────────────────────
CFLAGS   := -march=rv32im_zicsr -mabi=ilp32 -g -O0 -ffreestanding -nostdlib \
             -Wall -Wextra
LDFLAGS  := -T $(LIB)/cs281.ld -nostdlib

# ── Sources ───────────────────────────────────────────────────────────────────
LIB_SRCS := $(LIB)/startup.S \
             $(LIB)/uart.S \
             $(LIB)/exit.S

APP_SRCS := main.c

LIB_OBJS := $(patsubst $(LIB)/%.S, $(BUILD)/%.o, $(LIB_SRCS))
APP_OBJS := $(patsubst %.c, $(BUILD)/%.o, $(APP_SRCS))
OBJS     := $(LIB_OBJS) $(APP_OBJS)

TARGET   := $(BUILD)/lab4a.elf

# ── Renode / Debug Ports ──────────────────────────────────────────────────────
RENODE    := renode
MON_PORT  := 1234
UART_PORT := 3456
GDB_PORT  := 3333

RESC_RUN  := lab4a_run.resc
RESC_DBG  := lab4a_debug.resc

# ── OS detection (for kill-renode) ────────────────────────────────────────────
ifeq ($(OS),Windows_NT)
    KILL_RENODE := taskkill /F /IM renode.exe 2>nul & ping -n 2 127.0.0.1 >nul & exit /b 0
else
    KILL_RENODE := pkill -f renode 2>/dev/null; sleep 0.5; true
endif

# ── Build ─────────────────────────────────────────────────────────────────────
.PHONY: all
all: $(BUILD) $(TARGET)

$(BUILD):
	mkdir -p $(BUILD)

$(BUILD)/%.o: $(LIB)/%.S | $(BUILD)
	$(CC) $(CFLAGS) -c -o $@ $<

$(BUILD)/%.o: %.c | $(BUILD)
	$(CC) $(CFLAGS) -c -o $@ $<

$(TARGET): $(OBJS)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $^
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
	$(RENODE) --plain --disable-xwt \
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
	$(RENODE) --plain --disable-xwt \
		-e '$$bin=@$(abspath $(TARGET)); $$platform=@$(abspath $(HARDWARE)/cs281_board.repl); i @$(abspath $(RESC_DBG))'

.PHONY: uart-connect
uart-connect:
	@echo "Connecting to UART on port $(UART_PORT)  (Ctrl-] then 'quit' to exit)"
	telnet localhost $(UART_PORT)

.PHONY: monitor-connect
monitor-connect:
	telnet localhost $(MON_PORT)

.PHONY: disasm
disasm: $(TARGET)
	$(OBJDUMP) -d -M no-aliases $<
