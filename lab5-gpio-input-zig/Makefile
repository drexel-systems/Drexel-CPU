# =============================================================================
# CS281 Lab 5 (Zig) — GPIO Input Interrupts
# Requires Zig 0.14.0+ for callconv(.riscv32_interrupt) support
#
# Build strategy: we call `zig build-exe` directly instead of `zig build`.
# `zig build` compiles build.zig into a native macOS binary (the build
# runner), which requires linking against libSystem — and that fails when
# macOS SDK detection is broken (e.g. Xcode 26 on some setups).
# `zig build-exe` cross-compiles src/main.zig to riscv32-freestanding
# directly, never touching the macOS SDK at all.
# =============================================================================

ZIG      := zig
OBJDUMP  := riscv64-elf-objdump
GDB      := riscv64-elf-gdb

ELF      := zig-out/bin/lab5z
HARDWARE := ../hardware

RENODE    := renode
MON_PORT  := 1234
UART_PORT := 3456
GDB_PORT  := 3333

RESC_RUN := lab5z_run.resc
RESC_DBG := lab5z_debug.resc

ifeq ($(OS),Windows_NT)
    KILL_RENODE := taskkill /F /IM renode.exe 2>nul & ping -n 2 127.0.0.1 >nul & exit /b 0
else
    KILL_RENODE := pkill -f renode 2>/dev/null; sleep 0.5; true
endif

.PHONY: all
all: $(ELF)

$(ELF): src/main.zig cs281.ld
	mkdir -p $(dir $(ELF))
	$(ZIG) build-exe \
		-target riscv32-freestanding-none \
		-mcpu=generic_rv32+m \
		-O ReleaseSmall \
		-T cs281.ld \
		-femit-bin=$(ELF) \
		src/main.zig

.PHONY: clean
clean:
	rm -rf zig-out .zig-cache lab5z.o

.PHONY: kill-renode
kill-renode:
	-$(KILL_RENODE)

.PHONY: run
run: $(ELF) kill-renode
	@echo "──────────────────────────────────────────────────"
	@echo " Starting Renode  (Zig lab5)"
	@echo " UART     → telnet localhost $(UART_PORT)  (make uart-connect)"
	@echo " Monitor  → telnet localhost $(MON_PORT)   (make monitor-connect)"
	@echo "──────────────────────────────────────────────────"
	$(RENODE) --plain --disable-xwt \
		-e '$$bin=@$(abspath $(ELF)); $$platform=@$(abspath $(HARDWARE)/cs281_board.repl); i @$(abspath $(RESC_RUN))'

.PHONY: run-debug
run-debug: $(ELF) kill-renode
	@echo "──────────────────────────────────────────────────"
	@echo " Starting Renode debug session  (Zig lab5)"
	@echo " GDB stub → localhost:$(GDB_PORT)"
	@echo " UART     → telnet localhost $(UART_PORT)  (make uart-connect)"
	@echo " CPU is HALTED — connect GDB or press F5 in VS Code"
	@echo "──────────────────────────────────────────────────"
	$(RENODE) --plain --disable-xwt \
		-e '$$bin=@$(abspath $(ELF)); $$platform=@$(abspath $(HARDWARE)/cs281_board.repl); i @$(abspath $(RESC_DBG))'

.PHONY: debug-attach
debug-attach:
	$(GDB) $(ELF) \
		-ex "set architecture riscv:rv32" \
		-ex "target remote localhost:$(GDB_PORT)" \
		-ex "layout src" \
		-ex "layout regs"

.PHONY: uart-connect
uart-connect:
	@echo "Connecting to UART on port $(UART_PORT)  (Ctrl-] then 'quit' to exit)"
	telnet localhost $(UART_PORT)

.PHONY: monitor-connect
monitor-connect:
	@echo "Connecting to Renode monitor on port $(MON_PORT)  (Ctrl-] then 'quit' to exit)"
	telnet localhost $(MON_PORT)

.PHONY: disasm
disasm: $(ELF)
	$(OBJDUMP) -d -M no-aliases $(ELF)
