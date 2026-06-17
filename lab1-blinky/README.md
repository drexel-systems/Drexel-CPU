# Lab 1 — Blinky

The classic embedded systems first program: blink an LED and print status over a serial port. Lab 1 establishes the full toolchain and runtime environment that every subsequent lab builds on.

## What It Does

The program toggles LED0 on and off in an infinite loop, printing `LED0 ON` and `LED0 OFF` over UART each time it switches. Between each toggle it burns CPU cycles in a busy-wait countdown loop to create a visible delay.

## Learning Objectives

**Bare-metal boot sequence** — Before `main()` runs, the processor needs a valid stack, initialized global variables, and zeroed BSS. On a hosted system (Linux, macOS) the OS sets all of this up invisibly. Here students see `startup.S` do it explicitly: set the stack pointer, copy `.data` from ROM to RAM, zero `.bss`, then call `main`. This makes the distinction between LMA (load address in ROM) and VMA (run address in RAM) concrete.

**Memory-mapped I/O** — There is no `digitalWrite()` or HAL. Writing the value `0x01` to address `0xe0015000` turns on LED0 because that address is the GPIO output register. Reading and writing peripherals is indistinguishable from reading and writing memory — students see this directly in the `sw` and `lw` instructions in `main.S`.

**UART as a debug tool** — The UART peripheral at `0xe0001800` is the primary window into a running bare-metal program. Students learn to poll `TXFULL` before writing a character and to connect via `telnet` to see output, which mirrors how embedded engineers interact with hardware over a serial console.

**Software delay loops** — The `delay()` function is a simple countdown: decrement a register until it hits zero. Students see why this works (each iteration takes a predictable number of CPU cycles) and why it is fragile (the actual wall-clock time depends on CPU frequency, which varies between simulation and real hardware). This sets up the motivation for Lab 2.

**Linker script and ELF sections** — The Makefile produces a `.elf` file with distinct sections: `.text` in ROM, `.data` copied to RAM, `.bss` zeroed in RAM. `make disasm` lets students inspect the final binary and see where everything landed.

## Key Files

| File | Role |
|------|------|
| `main.S` | Application: blink loop and software delay |
| `../hardware/lib/startup.S` | Boot: stack, `.data` copy, `.bss` zero, call `main` |
| `../hardware/lib/uart.S` | Library: `uart_putchar`, `uart_puts`, `uart_getchar` |
| `../hardware/lib/cs281.ld` | Linker script: places sections in ROM and RAM |
| `../hardware/lib/cs281.inc` | Register map: peripheral addresses as `.equ` constants |

## Running It

```bash
make run          # build and launch Renode
make uart-connect # (second terminal) telnet to UART — watch LED0 ON / OFF scroll
```

To inspect the GPIO register live while the program runs, connect to the Renode monitor (`make monitor-connect`) and type:

```
sysbus.gpio_led0 State    # True when LED0 is on, False when off
```

## What to Notice

- `startup.S` runs before `main`. Set a breakpoint on `_start` in GDB (`make run-debug`, then F5 in VS Code) and step through the boot sequence before `main` is reached.
- The delay loop in `main.S` keeps the CPU 100% busy while waiting. Compare this with Lab 2, where the CPU idles at near-zero activity between blinks.
- Change `BLINK_DELAY` in `main.S` and observe how the blink rate changes. The value is simulation-speed dependent — this is a limitation of software delays that hardware timers fix.
