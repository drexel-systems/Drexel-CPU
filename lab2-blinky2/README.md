# Lab 2 — Blinky with Timer Interrupt

The same blink-and-print program as Lab 1, but rebuilt around a hardware timer interrupt. The LED still toggles at the same rate — what changes is everything the CPU does (or doesn't do) between toggles.

## What It Does

`main()` configures the CLINT timer, enables interrupts, and then enters a `wfi` (Wait For Interrupt) loop where it does nothing. The actual LED toggling and UART printing happen entirely inside `trap_handler`, which the CPU jumps to automatically each time the hardware timer fires. The program runs forever.

## Learning Objectives

**Interrupt-driven vs. polling** — Lab 1 wasted CPU cycles counting down a register. Lab 2 idles with `wfi` between interrupts. On real hardware this difference maps directly to power consumption — a processor sleeping in `wfi` draws a fraction of the current of one executing a tight loop. In Renode it also allows the simulator to advance virtual time efficiently.

**mtvec and the trap vector** — Before any interrupt can be handled, `mtvec` must point at the handler. Students see how a single CSR write (`csrw mtvec, t0`) registers the entire trap handler with the hardware. In direct mode (the default, bits 1:0 = 00) every trap — interrupts and exceptions alike — jumps to the same address.

**Interrupt enable hierarchy** — Two gates must both be open before a timer interrupt can reach the CPU. `mie` (machine interrupt enable) has a per-source bit: bit 7 is MTIE, the machine timer interrupt enable. `mstatus` has the global gate: bit 3 is MIE. Both must be set. This two-level design lets a handler temporarily mask all interrupts (clear `mstatus.MIE`) without disturbing which sources are individually enabled in `mie`.

**CLINT and MTIMECMP** — The CLINT provides `MTIME`, a 64-bit counter incrementing at 100 MHz, and `MTIMECMP`, a deadline register. When `MTIME >= MTIMECMP` the CPU receives a machine timer interrupt. The handler advances `MTIMECMP` by `HALF_PERIOD` after each interrupt — this is both how the next deadline is scheduled and how the current interrupt is cleared (there is no separate acknowledge register).

**Trap handler discipline** — A trap handler can interrupt any instruction in the main program. It must therefore save every register it touches — not just callee-saved registers, but caller-saved ones too — and restore them before returning. Students see the full save/restore frame and understand why it is necessary. `mret` (not `ret`) is used to return, because it also restores `mstatus.MIE` from `mstatus.MPIE`.

**The safe 64-bit MTIMECMP write sequence** — MTIMECMP is a 64-bit register accessed as two 32-bit words. Writing only the low word first could momentarily produce a value smaller than `MTIME` and trigger a spurious interrupt. The correct sequence sets the high word to `0xFFFFFFFF` first (making the 64-bit value impossibly large), then writes the low word, then sets the high word to 0. Students see this pattern in `main()`.

## Key Files

| File | Role |
|------|------|
| `main.S` | Trap handler and main: timer setup, interrupt enable, WFI loop |
| `../hardware/lib/startup.S` | Boot sequence (same as Lab 1) |
| `../hardware/lib/uart.S` | UART library (same as Lab 1) |
| `../hardware/lib/exit.S` | Halt function: disable interrupts, print message, WFI forever |
| `../hardware/lib/cs281.inc` | Register map including `CLINT_MTIME_ADDR`, `CLINT_MTIMECMP_ADDR` |

## Running It

```bash
make run          # build and launch Renode
make uart-connect # (second terminal) watch [IRQ] LED0 ON / OFF at ~1 s intervals
```

To confirm the CPU is actually idling between interrupts, connect to the Renode monitor (`make monitor-connect`) and type `pause`. The PC will be inside the `wfi` instruction in `.Lwfi_loop` — not inside the delay countdown of Lab 1.

## What to Notice

- Set a breakpoint on `trap_handler` in GDB (F5 in VS Code after `make run-debug`). Each time the timer fires the debugger will stop there. Step through the handler and observe the register save frame, the LED toggle, the MTIMECMP update, and the `mret`.
- Comment out `csrsi mstatus, 8` in `main()` and rebuild. The CPU will spin in `wfi` forever with no interrupts — nothing will print. This demonstrates that the global interrupt gate in `mstatus` is required even when `mie` is configured correctly.
- Change `HALF_PERIOD` to `25000000` (0.25 s) and observe the blink rate double. Because the delay is driven by the hardware timer rather than a CPU cycle count, the rate is independent of simulation speed.

## Compared to Lab 1

| | Lab 1 | Lab 2 |
|---|---|---|
| Timing mechanism | Software countdown loop | CLINT hardware timer |
| CPU activity while waiting | 100% (busy loop) | ~0% (WFI) |
| Timing accuracy | Depends on simulation speed | Tied to simulated clock |
| Interrupt handler | None | `trap_handler` with save/restore frame |
| `mtvec` / `mie` / `mstatus` | Not used | Required |
