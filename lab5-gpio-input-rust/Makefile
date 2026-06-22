# =============================================================================
# CS281 Lab 5 (Rust) — GPIO Input Interrupts
# Bare-metal Rust build for riscv32im-unknown-none-elf
# =============================================================================

# ── Toolchain ─────────────────────────────────────────────────────────────────
CARGO     := cargo
TARGET    := riscv32im-unknown-none-elf
OBJDUMP   := riscv64-elf-objdump
GDB       := riscv64-elf-gdb

# ── Output ELF (name matches [[bin]] name in Cargo.toml) ─────────────────────
ELF := target/$(TARGET)/release/lab5r

# ── Shared hardware paths ─────────────────────────────────────────────────────
HARDWARE := ../hardware

# ── Renode / debug ports ──────────────────────────────────────────────────────
RENODE    := renode
MON_PORT  := 1234
UART_PORT := 3456
GDB_PORT  := 3333

RESC_RUN := lab5r_run.resc
RESC_DBG := lab5r_debug.resc

# ── OS detection (for kill-renode) ───────────────────────────────────────────
ifeq ($(OS),Windows_NT)
    KILL_RENODE := taskkill /F /IM renode.exe 2>nul & ping -n 2 127.0.0.1 >nul & exit /b 0
else
    KILL_RENODE := pkill -f renode 2>/dev/null; sleep 0.5; true
endif

# ── Default target ────────────────────────────────────────────────────────────
.PHONY: all
all: $(ELF)

$(ELF):
	$(CARGO) build --release

.PHONY: clean
clean:
	$(CARGO) clean

# ── Kill any running Renode ───────────────────────────────────────────────────
.PHONY: kill-renode
kill-renode:
	-$(KILL_RENODE)

# ── Run in Renode ─────────────────────────────────────────────────────────────
.PHONY: run
run: $(ELF) kill-renode
	@echo "──────────────────────────────────────────────────"
	@echo " Starting Renode  (Rust lab5)"
	@echo " UART     → telnet localhost $(UART_PORT)  (make uart-connect)"
	@echo " Monitor  → telnet localhost $(MON_PORT)   (make monitor-connect)"
	@echo "──────────────────────────────────────────────────"
	$(RENODE) --plain --disable-xwt \
		-e '$$bin=@$(abspath $(ELF)); $$platform=@$(abspath $(HARDWARE)/cs281_board.repl); i @$(abspath $(RESC_RUN))'

# ── Debug session (GDB stub, CPU halted) ──────────────────────────────────────
.PHONY: run-debug
run-debug: $(ELF) kill-renode
	@echo "──────────────────────────────────────────────────"
	@echo " Starting Renode debug session  (Rust lab5)"
	@echo " GDB stub → localhost:$(GDB_PORT)"
	@echo " UART     → telnet localhost $(UART_PORT)  (make uart-connect)"
	@echo " CPU is HALTED — connect GDB or press F5 in VS Code"
	@echo "──────────────────────────────────────────────────"
	$(RENODE) --plain --disable-xwt \
		-e '$$bin=@$(abspath $(ELF)); $$platform=@$(abspath $(HARDWARE)/cs281_board.repl); i @$(abspath $(RESC_DBG))'

.PHONY: debug-attach
debug-attach: $(ELF)
	$(GDB) $(ELF) \
		-ex "set architecture riscv:rv32" \
		-ex "target remote localhost:$(GDB_PORT)" \
		-ex "layout src" \
		-ex "layout regs"

# ── UART / monitor connections ────────────────────────────────────────────────
.PHONY: uart-connect
uart-connect:
	@echo "Connecting to UART on port $(UART_PORT)  (Ctrl-] then 'quit' to exit)"
	telnet localhost $(UART_PORT)

.PHONY: monitor-connect
monitor-connect:
	@echo "Connecting to Renode monitor on port $(MON_PORT)  (Ctrl-] then 'quit' to exit)"
	telnet localhost $(MON_PORT)

# ── Disassemble ───────────────────────────────────────────────────────────────
.PHONY: disasm
disasm: $(ELF)
	$(OBJDUMP) -d -M no-aliases $(ELF)
