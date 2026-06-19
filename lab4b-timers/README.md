# Lab 4b — Interrupt-Based Timers (Assembly)

Implement the same LiteX Timer interrupt program as Lab 4a, but entirely in RISC-V assembly. Three functions have TODO stubs; everything else (startup, trap vector setup, ISR frame, print helpers, busy-work loop) is provided.

## Prerequisites

**Read Lab 4a first.** `lab4a-timers-c/main.c` is the C reference implementation of exactly what you are building here. Every C construct has a comment showing the assembly equivalent. Run Lab 4a and verify you see the interleaved dots and tick messages before starting Lab 4b.

Also read **TRM Section 6** (`hardware/docs/CS281_TRM.pdf`) for the complete LiteX Timer register map and ISR pattern.

## What It Does (when complete)

```
=== CS281 Lab 4b: Interrupt-Based Timers (Assembly) ===

Main loop running -- printing a dot every ~1 s
Timer interrupt fires every 1 second

. . . . 
[TICK 1]
. . . . 
[TICK 2]
```

Until the three TODOs are filled in, you will see only dots (timer never fires) or only tick messages (ISR stuck in a loop).

## Your Task

Three functions in `main.S` have TODO stubs:

### 1. `timer_init` — configure the LiteX Timer

```asm
timer_init:
    # TODO: implement
    #
    # Steps (in order):
    #   1. Write 1 to TIMER_EV_ENABLE (offset 0x40) — routes IRQ → CPU line 11
    #   2. Write 0x05F5E100 (100,000,000) to LOAD sub-registers:
    #        offset 0x00 ← 0x05   (bits 31:24)
    #        offset 0x04 ← 0xF5   (bits 23:16)
    #        offset 0x08 ← 0xE1   (bits 15:8)
    #        offset 0x0C ← 0x00   (bits 7:0)
    #   3. Write same bytes to RELOAD sub-registers (offsets 0x10–0x1C)
    #   4. Write 1 to TIMER_EN (offset 0x20) — start counting
    #
    # Constants from cs281.inc:
    #   TIMER_BASE, TIMER_LOAD0–LOAD3, TIMER_RELOAD0–RELOAD3, TIMER_EN
    #   TIMER_EV_ENABLE, TIMER_FREQ_B0–B3
    ret   # remove this and replace with your implementation
```

### 2. `enable_interrupts` — open the CPU interrupt gates

```asm
enable_interrupts:
    # TODO: implement
    #
    # Steps:
    #   1. csrs mie, (1<<11)      — enable CPU line 11 source in mie
    #   2. csrs mstatus, (1<<3)   — set global MIE bit (master enable)
    #
    # Both gates must be open or no interrupt ever reaches the CPU.
    ret   # remove this and replace with your implementation
```

### 3. ISR body — inside `machine_trap_handler`

The provided trap handler already saves all registers and checks `mcause`. Inside the `mcause == 0x8000000B` branch there is a TODO section:

```asm
# TODO: implement the three ISR steps
#
# Step A — increment tick_count:
#   la   t0, tick_count
#   lw   t1, 0(t0)
#   addi t1, t1, 1
#   sw   t1, 0(t0)
#
# Step B — print the tick (provided: call print_tick)
#
# Step C — clear the interrupt flag:
#   li   t0, (TIMER_BASE + TIMER_EV_PENDING)   # 0xe000203C
#   li   t1, 1
#   sw   t1, 0(t0)
#
# CRITICAL: if you skip Step C, EV_PENDING stays asserted.
# The moment mret executes the CPU sees the line still high,
# jumps back into the ISR, and main never runs again.
```

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
| 0x20 | EN | Write 1 to start |
| 0x3C | EV_PENDING | Write 1 to **clear** the interrupt |
| 0x40 | EV_ENABLE | Write 1 to route timer → CPU line 11 |

All offsets relative to `TIMER_BASE = 0xe0002000` (defined in `cs281.inc`).

## Key Files

| File | Role |
|------|------|
| `main.S` | Your implementation — the three TODO stubs |
| `../lab4a-timers-c/main.c` | C reference — read this for the assembly mapping |
| `../hardware/lib/cs281.inc` | `TIMER_BASE`, `TIMER_LOAD0`–`LOAD3`, `TIMER_FREQ_B0`–`B3`, etc. |
| `../hardware/lib/startup.S` | Boot sequence |
| `../hardware/lib/uart.S` | UART library |
| `../hardware/docs/CS281_TRM.pdf` | TRM Section 6 — timer documentation |

## Running It

```bash
make run          # build and launch Renode
make uart-connect # (second terminal) see interleaved dots and tick messages
```

## Debugging Tips

**Only dots, no tick messages** — `timer_init` or `enable_interrupts` is wrong. The timer is not firing, or the interrupt is not reaching the CPU. Check: did you write to `TIMER_EV_ENABLE` (0x40) before `TIMER_EN` (0x20)? Did you set both `mie` bit 11 and `mstatus` bit 3?

**Only tick messages, no dots** — The ISR body is missing Step C (clear `EV_PENDING`). The timer fires once, the ISR runs, but `EV_PENDING` stays asserted. After `mret`, the CPU immediately re-enters the ISR. `main` never gets a chance to run.

**GDB walkthrough** — `make run-debug`, then F5 in VS Code. Set a breakpoint on `timer_init` and step through it, checking that each register write lands at the correct peripheral address. Then set a breakpoint on `machine_trap_handler` — it should be hit once per second.

## Compared to Lab 4a

| | Lab 4a (`main.c`) | Lab 4b (`main.S`) |
|---|---|---|
| Language | C | RISC-V assembly |
| ISR declaration | `__attribute__((interrupt("machine")))` | Manual save/restore frame + `mret` |
| Timer writes | `timer_write32()` helper | Four explicit `sw` instructions per field |
| Interrupt enable | `__asm__ volatile("csrs mie, ...")` | `csrs` instructions directly |
| Conceptual content | Identical | Identical |
