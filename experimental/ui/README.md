# CS281 Board UI

A terminal TUI that renders a virtual CS281 development board. It connects to a
running Renode session over TCP and lets students interact with LEDs, DIP
switches, and the 7-segment display without touching the Renode monitor prompt.

```
╭─────────────────────────────────────────────────────────────────────╮
│               CS281 Virtual Development Board                        │
│                         ◉  RUNNING                                  │
│─────────────────────────────────────────────────────────────────────│
│  INPUTS          │   7-SEG   │  LEDs         │  STATUS              │
│                  │           │               │                      │
│  [0] BTN0  mom   │   ───     │  ⬤ LED0 ○LED1 │  CPU  ● RUN         │
│  [1] BTN1  mom   │  █   █    │  ○ LED2 ○LED3 │                     │
│  [2] DIP0  ▽off  │   ───     │               │  ╔══════╗            │
│  [3] DIP1  ▽off  │  █   █    │               │  ║ RST  ║            │
│                  │   ───     │               │  ╚══════╝            │
│─────────────────────────────────────────────────────────────────────│
│  UART OUTPUT                                   ↑↓ / j k / scroll    │
│─────────────────────────────────────────────────────────────────────│
│  Main loop running...                                                │
│  . . . . [BTN0] LED0 ON . . . [BTN0] LED0 OFF . . .                │
│─────────────────────────────────────────────────────────────────────│
│  [0] BTN0  [1] BTN1  [2] DIP0  [3] DIP1                            │
│  [R] Reset     [P] Power Down      [Q] Quit                         │
╰─────────────────────────────────────────────────────────────────────╯
```

> **Experimental** — lives in `experimental/` intentionally. Renode must be
> started separately via `make run` inside a lab directory.

---

## Requirements

| Tool | Version |
|------|---------|
| Go | 1.21+ |
| Renode | 1.16+ (running a CS281 lab) |
| Terminal | Truecolor support (iTerm2, Windows Terminal, most modern terminals) |

---

## Quick Start

```bash
# 1. Start Renode with a lab
cd lab5-gpio-input && make run    # opens ports 1234 (monitor) and 3456 (UART)

# 2. In a second terminal, launch the UI
cd experimental/ui
make run          # go mod tidy + go run .
```

Press **P** to power up and connect. The board runs a self-test animation,
then goes live. Press **Esc** at any point during the self-test to skip
straight to live mode.

---

## Build

```bash
make build         # native binary → ./cs281ui
make all           # cross-compile all five platforms → bin/
```

| Target | Output |
|--------|--------|
| `make mac-arm64` | `bin/cs281ui-mac-arm64` |
| `make mac-amd64` | `bin/cs281ui-mac-amd64` |
| `make linux-amd64` | `bin/cs281ui-linux-amd64` |
| `make linux-arm64` | `bin/cs281ui-linux-arm64` |
| `make windows-amd64` | `bin/cs281ui-windows-amd64.exe` |

---

## Flags

| Flag | Default | Description |
|------|---------|-------------|
| `--monitor-port` | `1234` | Renode monitor TCP port |
| `--uart-port` | `3456` | UART output TCP port |

---

## Keyboard Controls

| Key | State | Action |
|-----|-------|--------|
| `P` | Powered Down / Error | Power Up — connect to Renode, run self-test |
| `P` | Running / Self-test | Power Down — disconnect (Renode keeps running) |
| `Esc` | Self-test / POST-OK | Skip self-test and go straight to live mode |
| `R` | Running | Soft-reset — rewinds CPU to `_start`, clears GPIO and UART pane |
| `0` | Running | Press BTN0 (`runMacro $btn0Press`) |
| `1` | Running | Press BTN1 (`runMacro $btn1Press`) |
| `2` | Running | Toggle DIP0 |
| `3` | Running | Toggle DIP1 |
| `↑` / `k` | Any | Scroll UART output up |
| `↓` / `j` | Any | Scroll UART output down |
| `PgUp` | Any | Half-page up |
| `PgDn` | Any | Half-page down |
| Mouse wheel | Any | Scroll UART output |
| `Q` / `Ctrl+C` | Any | Quit |

---

## State Machine

```
POWERED DOWN ──[P]──► CONNECTING ──► STARTUP ──► POST-TEST ──► RUNNING
     ▲                                  │             │             │
     │                               [Esc]         [Esc]           │
     │                                  └─────────────┘            │
     └──────────────────────────────[P]────────────────────────────┘
                                                          │
                                   ERROR ◄── conn lost ───┘
```

| State | Description |
|-------|-------------|
| **POWERED DOWN** | Idle. No connection. |
| **CONNECTING** | TCP dial in progress (3 s timeout). Syncs GPIO_OUT register. |
| **SELF-TEST** | Startup animation plays: LEDs, DIPs, 7-seg 0–9. UART buffered silently. Press Esc to skip. |
| **POST-TEST** | Displays "POST OK" banner for 2 seconds. UART still buffered. Press Esc to skip. |
| **RUNNING** | Live. UART streams, keypresses drive Renode. |
| **ERROR** | Connection lost or failed. Press P to retry. |

---

## Architecture

The UI is written in Go using the [Charm](https://charm.sh) ecosystem and
follows Bubbletea's Elm-style model/update/view architecture.

```
main.go          Entry point — flags, tea.NewProgram
model.go         State machine, Update(), all message types, startup sequence
board.go         View layer — renderFrame(), LED/7-seg/DIP/status rendering, colours
connection.go    TCP dial, monitor sync, UART goroutine, tea.Cmd wrappers
```

### Key design decisions

**Decoupled from Renode** — the UI connects to Renode's existing telnet/TCP
sockets. It does not launch or manage Renode; students start it with `make run`
as they always have.

**Raw UART bytes, not lines** — the UART goroutine calls `net.Conn.Read()`
directly and ships raw chunks to the model. The model splits on `\n` itself.
This means partial output (individual `.` dots from the main loop) appears
immediately instead of waiting for a newline.

**GPIO sync on connect** — on every power-up, the UI issues
`sysbus ReadDoubleWord 0xe0015000` to the Renode monitor and parses the
response to seed LED state. This keeps the UI in sync even when reconnecting
to a board that has been running for a while.

**Startup self-test** — a 23-step animation sequence (defined as a slice of
`startupAction` in `model.go`) drives the hardware widgets via `tea.Tick`.
UART data is collected in the background during the test and rendered only
after the POST-OK banner clears. Press `Esc` during either phase to skip
directly to live mode.

**CPU state detection** — once the board is running, the UI polls `cpu PC`
every second via the Renode monitor. The drain goroutine forwards any line
starting with `0x` to a channel in the model. If the same PC value is observed
6 times in a row (~6 s) the CPU is flagged **HLT** (amber `○ HLT`) in the
STATUS column; any change resets the counter and shows **RUN** (green `● RUN`).
This is a heuristic — programs that use `wfi` in a tight loop may read as
halted if no interrupt fires for 6 seconds, but will recover automatically
when activity resumes.

**Soft reset** — pressing `R` sends a sequence of monitor commands atomically
(via `sendSeq`, which holds the shared writer lock): `pause`, clear all four
GPIO_IN lines to `False`, `cpu PC 0x20000000`, `start`. This rewinds the
program counter to `_start` without using `machine Reset`, which would send
the RISC-V CPU to its default reset vector at `0x1000` (outside our ROM).
The startup code in `startup.S` re-runs on resume, re-initialising `.data`,
zeroing `.bss`, and re-registering peripheral interrupts. The UI clears
LED / DIP / 7-seg state and inserts a separator in the UART pane. No
self-test replay; the board goes straight back to live UART output.

**Hard wrapping** — the viewport receives hard-wrapped content so long UART
lines fold at the viewport boundary instead of truncating or scrolling sideways.

### Board panel layout

The hardware panel has four fixed-width columns separated by `│`:

| Column | Width | Contents |
|--------|-------|----------|
| INPUTS | 26 | Button / DIP key bindings |
| 7-SEG | 13 | 7-segment display (amber segments) |
| LEDs | 18 | Four coloured LED indicators |
| STATUS | remainder | CPU RUN/HLT indicator + RST button visual |

### LED colours

| LED | Colour |
|-----|--------|
| LED0 | Neon green `#39FF14` |
| LED1 | Red `#FF4444` |
| LED2 | Yellow `#FFD700` |
| LED3 | Blue `#4A9EFF` |

### 7-segment bit layout

```
  bit 0 = a  (top)           bit 4 = e  (bottom-left)
  bit 1 = b  (top-right)     bit 5 = f  (top-left)
  bit 2 = c  (bottom-right)  bit 6 = g  (middle)
  bit 3 = d  (bottom)        bit 7 = dp (decimal point)
```

---

## Known Limitations

- LED state is inferred by parsing UART output for `LED0 ON` / `LED0 OFF`
  patterns. If students rename those strings, the LED indicators stop tracking.
  GPIO_OUT is read once on connect to seed initial state, but is not polled
  continuously.

- The 7-segment display shows `0` by default and is not updated from live
  firmware output (no lab drives it via UART yet). Future labs will control it
  directly via the 7-seg peripheral register.

- DIP switch state is tracked locally in the UI. The GPIO_IN register is not
  read back on connect, so if a lab session is rejoined mid-run the DIP
  indicators may not reflect the actual hardware state until the student
  presses the corresponding key.

- The CPU HLT indicator is a heuristic (6 consecutive identical PC readings).
  Programs using `wfi` in a tight main loop may briefly appear halted if no
  interrupt fires for ~6 seconds.
