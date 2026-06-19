# Lab 4a — Interrupt-Based Timers (C)

A fully working reference implementation of LiteX Timer interrupt handling in C. Read and run this before writing the assembly version in Lab 4b.

## What It Does

`main` loops forever printing a dot every ~200 ms. Every 1 second the LiteX Timer fires CPU interrupt line 11, the CPU jumps to `machine_trap_handler`, the ISR prints `[TICK N]` and clears the hardware flag, then `mret` returns the CPU to exactly the instruction in `main` where it was interrupted.

```
=== CS281 Lab 4a: Interrupt-Based Timers (C) ===

Main loop running -- printing a dot every ~500 ms
Timer interrupt fires every 1 second

. . . . 
[TICK 1]
. . . . 
[TICK 2]
. . . . 
[TICK 3]
```

## Learning Objectives

**LiteX Timer sub-register scheme** — The LiteX_Timer peripheral stores 32-bit LOAD and RELOAD values across four 8-bit registers at consecutive 4-byte addresses. You cannot write a full 32-bit value in one store — you must write each byte separately, MSB first. `timer_write32()` shows the pattern; Lab 4b requires you to reproduce it with explicit `sw` instructions.

**Interrupt enable hierarchy** — Two gates must both be open before an interrupt reaches the CPU. `mie` bit 11 enables CPU line 11 (the LiteX Timer source); `mstatus` bit 3 (`MIE`) is the global gate. Both must be set. `enable_interrupts()` in `main.c` shows the two `csrs` instructions required.

**`__attribute__((interrupt("machine")))` vs. a hand-rolled handler** — GCC automatically generates the full save/restore frame (all GPRs) and replaces `ret` with `mret`. In Lab 4b you write that prologue and epilogue yourself. Reading the C ISR first gives you a clear picture of what the compiler produces.

**Clearing the interrupt flag** — Writing 1 to `TIMER_EV_PENDING` (offset 0x3C from `TIMER_BASE`) tells the peripheral the interrupt is acknowledged. Skipping this write leaves the line asserted; the moment `mret` executes the CPU sees it still high, jumps back into the ISR, and never returns to `main`. This is the most common bug in Lab 4b.

**`volatile` shared state** — `tick_count` is written by the ISR and read by `main`. Without `volatile`, the compiler might cache the value in a register and never reload it. The same principle applies to all memory-mapped registers — every peripheral register access in this file uses `volatile`.

## LiteX Timer Register Map

| Offset | Register | Description |
|--------|----------|-------------|
| 0x00 | LOAD[31:24] | Countdown start value, bits 31–24 |
| 0x04 | LOAD[23:16] | |
| 0x08 | LOAD[15:8] | |
| 0x0C | LOAD[7:0] | |
| 0x10 | RELOAD[31:24] | Auto-reload value, bits 31–24 |
| 0x14 | RELOAD[23:16] | |
| 0x18 | RELOAD[15:8] | |
| 0x1C | RELOAD[7:0] | |
| 0x20 | EN | Write 1 to start, 0 to stop |
| 0x3C | EV_PENDING | Write 1 to **clear** the interrupt |
| 0x40 | EV_ENABLE | Write 1 to route timer → CPU line 11 |

All offsets are relative to `TIMER_BASE = 0xe0002000`.

## Writing 100,000,000 (0x05F5E100) to LOAD

In C (`timer_write32` handles this):
```c
TIMER_LOAD_REGS[0] = 0x05;   // bits[31:24]
TIMER_LOAD_REGS[1] = 0xF5;   // bits[23:16]
TIMER_LOAD_REGS[2] = 0xE1;   // bits[15:8]
TIMER_LOAD_REGS[3] = 0x00;   // bits[7:0]
```

In assembly (Lab 4b — you write this):
```asm
li   t0, 0xe0002000
li   t1, 0x05
sw   t1, 0x00(t0)     # LOAD[31:24]
li   t1, 0xF5
sw   t1, 0x04(t0)     # LOAD[23:16]
li   t1, 0xE1
sw   t1, 0x08(t0)     # LOAD[15:8]
sw   x0, 0x0C(t0)     # LOAD[7:0] = 0
```

## Key Files

| File | Role |
|------|------|
| `main.c` | Complete working implementation — read this carefully |
| `../hardware/lib/startup.S` | Boot sequence |
| `../hardware/lib/uart.S` | UART library |
| `../hardware/lib/cs281.inc` | Register map (used by Lab 4b assembly) |
| `../hardware/docs/CS281_TRM.pdf` | TRM Section 6 — full timer documentation |

## Running It

```bash
make run          # build and launch Renode
make uart-connect # (second terminal) see interleaved dots and tick messages
```

## C → Assembly Mapping

Each C construct in `main.c` has a comment showing the equivalent assembly. These are exactly the instructions you need for Lab 4b:

| C construct | Assembly equivalent |
|-------------|---------------------|
| `TIMER_EV_ENABLE = 1` | `li t1, 1 / sw t1, 0x40(t0)` |
| `csrs mie, (1<<11)` | `li t0, (1<<11) / csrs mie, t0` |
| `csrs mstatus, (1<<3)` | `li t0, (1<<3) / csrs mstatus, t0` |
| `tick_count++` | `la t0, tick_count / lw t1, 0(t0) / addi t1, t1, 1 / sw t1, 0(t0)` |
| `TIMER_EV_PENDING = 1` | `li t0, 0xe000203C / li t1, 1 / sw t1, 0(t0)` |

## What to Notice

- The dots and tick messages are interleaved — `main` has no idea the timer exists.
- Set a breakpoint on `machine_trap_handler` (F5 in VS Code after `make run-debug`). Each time the timer fires the debugger stops there. Step through: count the tick, print it, clear `EV_PENDING`, then `mret` jumps back into the middle of the dot loop.
- Remove the `TIMER_EV_PENDING = 1` line, rebuild, and run. The program immediately gets stuck in the ISR and dots stop — this is the "sticky interrupt" bug you will encounter if you forget to clear `EV_PENDING` in Lab 4b.
