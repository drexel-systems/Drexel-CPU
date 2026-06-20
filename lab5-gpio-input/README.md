# Lab 5 — GPIO Input Interrupts

Connect button presses to LED toggles using external interrupts. The main loop runs obliviously; pressing BTN0 or BTN1 asynchronously fires the ISR without main knowing anything about it.

## What It Does (when complete)

```
=== CS281 Lab 5: GPIO Input Interrupts ===
Simulate button presses from the Renode monitor:
  sysbus.gpio_in OnGPIO 0 True    (BTN0 -> toggles LED0)
  sysbus.gpio_in OnGPIO 1 True    (BTN1 -> toggles LED1)

Main loop running...
. . . .
[BTN0] LED0 ON
. . . .
[BTN0] LED0 OFF
. . . .
[BTN1] LED1 ON
```

Until the TODOs are filled in, you will see only dots and no LED activity — GPIO interrupts are not wired to the CPU.

## Learning Objectives

**External vs. periodic interrupts** — Lab 4's timer fired on a fixed schedule. Here the interrupt is *event-driven*: it fires when something happens in the world (a pin goes high), not after a fixed number of clock ticks. The CPU handling mechanics are identical; only the trigger differs.

**GPIO_IRQ_PENDING as interrupt source identification** — Multiple buttons share one CPU interrupt line (line 12). The ISR can't know which button caused it by looking at mcause alone; mcause only says "GPIO interrupt." Reading `GPIO_IRQ_PENDING` gives a bitmask of which pins fired. This is the standard pattern for shared interrupt lines.

**Rising-edge mode** — The GPIO peripheral defaults to interrupting on a rising edge (pin goes low→high). `SetGPIO 0 true` (press) fires the ISR; `SetGPIO 0 false` (release) does not. This gives clean one-ISR-per-press behavior without debounce complications.

**Clearing the pending bit** — Writing 1 to `GPIO_IRQ_PENDING` acknowledges the interrupt. Skipping this leaves the line asserted and the CPU re-enters the ISR immediately after `mret` — same "sticky interrupt" bug as forgetting `TIMER_EV_PENDING` in Lab 4b.

**Shared interrupt state** — `led_state` is written by the ISR and implicitly read by the GPIO output register write. It does not need `volatile` in assembly (there's no optimizer to trick), but the concept is the same as Lab 4a's `tick_count`: a variable shared between two execution contexts.

## GPIO Input Register Map

| Offset | Register | Description |
|--------|----------|-------------|
| 0x00 | GPIO_IN | Current pin state (bit N = pin N) |
| 0x04 | GPIO_IRQ_MODE | 0 = Edge, 1 = Change, per pin |
| 0x08 | GPIO_IRQ_EDGE | 0 = Rising, 1 = Falling, per pin |
| 0x0C | GPIO_IRQ_STATUS | Read-only |
| 0x10 | GPIO_IRQ_PENDING | Read: pending bits; write 1 to **clear** |
| 0x14 | GPIO_IRQ_ENABLE | Write 1 to enable IRQ per pin |

All offsets relative to `GPIO_IN_BASE = 0xe0015400`. Defaults are Edge + Rising — you only need to write `GPIO_IRQ_ENABLE`.

**mcause when GPIO fires:** `0x8000000C` (interrupt bit | cpu line 12)

## Your Task

Three stubs in `main.S`:

### 1. `gpio_init` — enable IRQ for BTN0 and BTN1

```asm
li    t0, GPIO_IN_BASE
li    t1, (BTN0 | BTN1)      # 0x03
sw    t1, GPIO_IRQ_ENABLE(t0)
```

### 2. `enable_interrupts` — open the CPU gates

```asm
li    t0, (1 << 12)           # mie bit 12 = cpu line 12 (GPIO)
csrs  mie, t0
li    t0, (1 << 3)            # mstatus bit 3 = global MIE
csrs  mstatus, t0
```

### 3. ISR body — inside `machine_trap_handler`

Five steps (see comments in main.S for the exact instructions):

- **Step A** — Read `GPIO_IRQ_PENDING` to find which button(s) fired
- **Step B** — If BTN0 pending: `xori led_state, LED0` → call `report_btn0`
- **Step C** — If BTN1 pending: `xori led_state, LED1` → call `report_btn1`
- **Step D** — Write `led_state` to `GPIO_OUT_BASE` (updates LEDs)
- **Step E** — Write `(BTN0 | BTN1)` to `GPIO_IRQ_PENDING` to clear

## Key Files

| File | Role |
|------|------|
| `main.S` | Application — three TODO stubs |
| `../hardware/lib/cs281.inc` | `GPIO_IN_BASE`, `GPIO_IRQ_*` offsets, `BTN0/BTN1`, `LED0/LED1` |
| `../hardware/lib/uart.S` | `uart_puts` — used by the provided `report_btn0/1` helpers |
| `../hardware/cs281_board.repl` | `gpio_in` with `enableIrq: true` (required for IRQ registers) |

## Running It

```bash
make run          # build and launch Renode
make uart-connect # (terminal 2) watch the UART output
make monitor-connect  # (terminal 3) trigger buttons from here
```

From the monitor terminal:
```
sysbus.gpio_in OnGPIO 0 True    # BTN0 press  → rising edge → ISR fires → LED0 toggles
sysbus.gpio_in OnGPIO 0 False   # BTN0 release — no IRQ, but resets pin for next press
sysbus.gpio_in OnGPIO 1 True    # BTN1 press  → ISR fires → LED1 toggles
sysbus.gpio_in OnGPIO 1 False   # BTN1 release
```

**Each button press is two commands: `True` then `False`.** The ISR fires on `True` (rising edge Low→High). `False` produces no output — it silently resets the pin to Low so the next `True` creates a fresh rising edge. Without `False` between presses, a second `True` finds the pin already High and no edge is detected.

To toggle LED0 twice:
```
sysbus.gpio_in OnGPIO 0 True    # → [BTN0] LED0 ON
sysbus.gpio_in OnGPIO 0 False   # (silent reset)
sysbus.gpio_in OnGPIO 0 True    # → [BTN0] LED0 OFF
sysbus.gpio_in OnGPIO 0 False   # (silent reset)
```

## Debugging Tips

**Only dots, no LED activity** — `gpio_init` or `enable_interrupts` is wrong. Check: did you write to `GPIO_IRQ_ENABLE` (offset 0x14, not 0x10)? Did you set mie bit **12** (not 11)?

**ISR fires but gets stuck (UART floods)** — Step E is missing. `GPIO_IRQ_PENDING` was never cleared. The CPU sees the line still asserted after `mret` and immediately re-enters the ISR, looping forever.

**GDB walkthrough** — `make run-debug`, then F5 in VS Code. Set a breakpoint on `machine_trap_handler`. Open the monitor terminal (`make monitor-connect`) and type `sysbus.gpio_in OnGPIO 0 True`. The debugger stops in the ISR. Step through: read PENDING, toggle led_state, call report_btn0, clear PENDING, then `mret` jumps back to the dot loop.

To inspect GPIO registers live from the monitor:
```
sysbus ReadDoubleWord 0xe0015410   # GPIO_IRQ_PENDING
sysbus ReadDoubleWord 0xe0015414   # GPIO_IRQ_ENABLE
sysbus ReadDoubleWord 0xe0015000   # GPIO_OUT (LED state)
```

## Compared to Lab 4b

| | Lab 4b (timer) | Lab 5 (GPIO) |
|---|---|---|
| Interrupt source | LiteX Timer, line 11 | GPIO Input, line 12 |
| mcause | `0x8000000B` | `0x8000000C` |
| mie bit | 11 | 12 |
| Init function | `timer_init` (complex) | `gpio_init` (one write) |
| IRQ trigger | Every N ticks (periodic) | Button press (event-driven) |
| Identify source | mcause alone is enough | Must read `GPIO_IRQ_PENDING` |
| Clear interrupt | `TIMER_EV_PENDING = 1` | `GPIO_IRQ_PENDING = 0x03` |

## Extensions

- **Report LED state on DIP_SW0:** after toggling, also read GPIO_IN and print the DIP switch state.
- **DIP_SW0 selects which LED BTN0 drives:** if DIP_SW0 is high, BTN0 controls LED1 instead of LED0.
- **Debounce:** add a short delay in the ISR after clearing PENDING before re-enabling interrupts, to ignore contact bounce.
- **Both LEDs off after 3 presses:** keep a press counter in BSS; after 3 presses set led_state = 0.
