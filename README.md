<img src="logo.svg" alt="CS281 Virtual Dev Board" width="480"/>

# CS281 Virtual Development Board

A bare-metal RISC-V RV32IM emulated development platform for **CS281 Systems Architecture** at Drexel University. Built on [Renode](https://renode.io), it gives students a realistic hardware environment — GPIO, UART, timers, interrupts — without requiring physical hardware.

📄 **[CS281 Technical Reference Manual](hardware/docs/CS281_TRM.pdf)** — memory map, peripheral registers, interrupt reference, boot sequence, and register quick reference.
*(Also available as [CS281_TRM.docx](hardware/docs/CS281_TRM.docx) for editing.)*

---

## What's Here

```
hardware/               Shared platform definition (used by every lab)
  cs281_board.repl      Renode machine description (CPU, memory, peripherals)
  cs281_run.resc        Renode script — normal run
  cs281_debug.resc      Renode script — GDB debug session
  lib/
    cs281.ld            Linker script (ROM @ 0x20000000, RAM @ 0x40000000)
    startup.S           Reset handler: stack init, .data copy, .bss zero
    uart.S              uart_putchar / uart_puts / uart_getchar
    cs281.inc           Assembly register map (.equ definitions)
    cs281.h             C register map (for future C labs)
  docs/
    CS281_TRM.docx      Technical Reference Manual / datasheet

lab1-blinky/            Lab 1: blink LED0 and print status over UART
  main.S
  Makefile
  .vscode/              Tasks, launch config, IntelliSense settings
```

## Memory Map

| Region | Address | Size | Contents |
|--------|---------|------|----------|
| ROM | `0x20000000` | 256 KB | Code, read-only data |
| RAM | `0x40000000` | 512 KB | `.data`, `.bss`, stack |
| UART | `0xe0001800` | — | Serial console (telnet :3456) |
| Timer | `0xe0002000` | — | LiteX Timer, IRQ line 11 |
| CLINT | `0xe0005000` | — | Machine timer + software IRQ |
| GPIO Out | `0xe0015000` | — | LED0–LED3 |
| GPIO In | `0xe0015400` | — | BTN0, BTN1, DIP_SW0, DIP_SW1 |
| 7-Seg | `0xe0004400` | — | 8-bit segment display |
| Buzzer | `0xe0004000` | — | 1-bit GPIO out |

## Prerequisites

| Tool | Notes |
|------|-------|
| [Renode](https://renode.io/get/) | Tested with 1.16+ |
| `riscv64-elf-*` toolchain | macOS: `brew install riscv-gnu-toolchain` |
| `telnet` | For UART and monitor connections |
| VS Code + [cortex-debug](https://marketplace.visualstudio.com/items?itemName=marus25.cortex-debug) | Optional, for graphical debugging |

## Quick Start

```bash
cd lab1-blinky
make              # assemble and link → build/lab1.elf
make run          # launch Renode headless
```

In a second terminal:
```bash
make uart-connect # telnet to UART — see LED0 ON / LED0 OFF output
```

### All Make Targets

| Target | Description |
|--------|-------------|
| `make` / `make all` | Build `build/lab1.elf` |
| `make clean` | Remove `build/` |
| `make run` | Run in Renode (headless) |
| `make run-debug` | Run with GDB stub on `:3333`, CPU halted |
| `make debug-attach` | Attach `riscv64-elf-gdb` (command-line) |
| `make uart-connect` | `telnet localhost 3456` — UART output |
| `make monitor-connect` | `telnet localhost 1234` — Renode monitor |
| `make disasm` | Disassemble ELF to stdout |

### Renode Monitor Commands

Once connected via `make monitor-connect`:

```
pause                        # halt CPU
start                        # resume
cpu PC                       # show program counter
sysbus.gpio_led0 State       # read LED0 state (True/False)
gpio_in SetGPIO 0 true       # press BTN0
gpio_in SetGPIO 0 false      # release BTN0
quit                         # exit Renode
```

## Lab Progression

| Lab | Topic |
|-----|-------|
| Lab 1 | Blinky — GPIO output, UART, software delay |
| Lab 2 | Buttons & Switches — GPIO input, polling |
| Lab 3 | 7-Segment Display — memory-mapped output |
| Lab 4 | Timer Interrupts — trap handler, CLINT, mtvec |
| Lab 5 | Full I/O — combine peripherals, interrupt-driven design |

## Architecture

- **CPU**: RISC-V RV32IM + Zicsr (32-bit, integer multiply/divide, CSR instructions)
- **Emulator**: [Renode](https://renode.io) with LiteX-compatible peripheral models
- **Language**: Assembly-first (C supported via same toolchain and linker script)
- **Debug**: GDB stub in Renode + VS Code cortex-debug (external server mode)

---

*Drexel University — CS281 Systems Architecture*
