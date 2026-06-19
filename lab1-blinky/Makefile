# =============================================================================
# CS281 Lab 1 — Blinky
# RISC-V RV32IM bare-metal build system
#
# Targets
#   make / make all    — assemble + link  →  build/lab1.elf
#   make clean         — remove build/
#   make run           — load into Renode (headless) and run
#   make run-debug     — load into Renode with GDB stub, halted
#   make debug-attach  — attach riscv32 GDB to running Renode session
#   make uart-connect  — telnet to UART on port 3456
#   make monitor-connect — telnet to Renode monitor on port 1234
#   make disasm        — disassemble ELF to stdout (for inspection)
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
LDFLAGS  := -T $(LIB)/cs281.ld -nostdlib -Map=$(BUILD)/lab1.map -m elf32lriscv

# ── Sources and Objects ───────────────────────────────────────────────────────
# Library sources (in hardware/lib/)
LIB_SRCS := $(LIB)/startup.S \
             $(LIB)/uart.S \
             $(LIB)/exit.S

# Application sources (in this directory)
APP_SRCS := main.S

# Object files — all land in build/
LIB_OBJS := $(patsubst $(LIB)/%.S, $(BUILD)/%.o, $(LIB_SRCS))
APP_OBJS := $(patsubst %.S, $(BUILD)/%.o, $(APP_SRCS))
OBJS     := $(LIB_OBJS) $(APP_OBJS)

TARGET   := $(BUILD)/lab1.elf

# ── Renode / Debug Ports ──────────────────────────────────────────────────────
RENODE    := renode
MON_PORT  := 1234
UART_PORT := 3456
GDB_PORT  := 3333

RESC_RUN  := $(HARDWARE)/cs281_run.resc
RESC_DBG  := $(HARDWARE)/cs281_debug.resc

# ── OS detection (for kill-renode) ────────────────────────────────────────────
ifeq ($(OS),Windows_NT)
    KILL_RENODE := taskkill /F /IM renode.exe 2>nul & ping -n 2 127.0.0.1 >nul & exit /b 0
else
    KILL_RENODE := pkill -f renode 2>/dev/null; sleep 0.5; true
endif

# ── Default Target ────────────────────────────────────────────────────────────
.PHONY: all
all: $(BUILD) $(TARGET)

# ── Create build directory ────────────────────────────────────────────────────
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

# ── Kill any running Renode (cross-platform) ──────────────────────────────────
.PHONY: kill-renode
kill-renode:
	-$(KILL_RENODE)

# ── Run (headless) ────────────────────────────────────────────────────────────
# Renode runs in this terminal.  Monitor on port 1234, UART on port 3456.
# Useful monitor commands (via make monitor-connect):
#   pause                      — halt the CPU
#   start                      — resume
#   sysbus.gpio_led0 State     — inspect LED0 state
#   gpio_in SetGPIO 0 true     — press BTN0
#   quit                       — exit Renode
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
# Starts Renode with a GDB stub on port $(GDB_PORT).  CPU is HALTED.
# Then either:
#   a) Press F5 in VS Code (uses launch.json)
#   b) Run: make debug-attach
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

# ── Attach GDB ────────────────────────────────────────────────────────────────
# Run this after 'make run-debug' is already running in another terminal.
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
# Renode opens its monitor on port 1234 automatically when run with --plain.
# Useful monitor commands:
#   pause                        — halt the CPU
#   start                        — resume execution
#   sysbus.gpio_led0 State       — read LED0 state (True/False)
#   sysbus.gpio_out State        — read all LED bits
#   gpio_in SetGPIO 0 true       — press BTN0
#   gpio_in SetGPIO 0 false      — release BTN0
#   cpu PC                       — show current program counter
#   cpu Step                     — single-step one instruction
#   quit                         — exit Renode
.PHONY: monitor-connect
monitor-connect:
	@echo "Connecting to Renode monitor on port $(MON_PORT)  (type 'quit' to exit Renode)"
	telnet localhost $(MON_PORT)

# ── Disassemble ───────────────────────────────────────────────────────────────
.PHONY: disasm
disasm: $(TARGET)
	$(OBJDUMP) -d -M no-aliases $<
