# CS281 Lab 5 — GPIO Input Interrupts (Rust)

A bare-metal Rust port of `lab5-gpio-input`. Functionally identical to the
assembly version: BTN0 and BTN1 trigger rising-edge GPIO interrupts that toggle
LED0 and LED1; main loops forever printing dots.

This version uses the **embedded Rust ecosystem** (`riscv-rt` + `riscv` crates)
to show what systems programming in Rust actually looks like — no startup
assembly, no register-save/restore boilerplate, no raw pointer arithmetic.
Cargo downloads and builds the support crates automatically.

## Rust installation requirements

### 1. Install rustup (Rust toolchain manager)

```bash
# macOS / Linux
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
```

On Windows, download and run the installer from <https://rustup.rs/>.

After installation, restart your shell (or run `source ~/.cargo/env`) so that
`rustup`, `cargo`, and `rustc` are on your `PATH`.

Verify:
```bash
rustc --version    # e.g.  rustc 1.81.0
cargo --version    # e.g.  cargo 1.81.0
```

### 2. Add the RISC-V bare-metal target

The CS281 board is `rv32im` (32-bit RISC-V with multiply/divide, no compressed
instructions). Install the matching Rust target:

```bash
rustup target add riscv32im-unknown-none-elf
```

Verify:
```bash
rustup target list --installed | grep riscv
# should print:  riscv32im-unknown-none-elf
```

> **Troubleshooting:** if `rustup target add` reports the target is unavailable,
> update your toolchain first: `rustup update stable`.

### 3. Internet access for crate downloads

The first `make` or `cargo build` downloads two crates from crates.io:

| Crate | Version | Purpose |
|-------|---------|---------|
| `riscv-rt` | 0.13 | Reset vector, `.data`/`.bss` init, trap frame |
| `riscv` | 0.12 | Type-safe CSR access (`mstatus`, `mie`, …) |

After the first build the crates are cached in `~/.cargo/registry` and offline
builds work normally.

### 4. RISC-V GNU toolchain (already needed for other labs)

`make disasm` and `make debug-attach` use `riscv64-elf-objdump` and
`riscv64-elf-gdb`. If you have set up other CS281 labs these are already
installed. If not, see [`docs/setup.md`](../docs/setup.md).

## Quick start

```bash
# 1. Build the firmware (downloads crates on first run)
cd lab5-gpio-input-rust
make                # runs: cargo build --release

# 2. Launch Renode
make run            # UART on telnet :3456 | Monitor on telnet :1234

# 3. (second terminal) Connect to UART output
make uart-connect   # telnet localhost 3456

# 4. (third terminal) Simulate button presses
make monitor-connect
# then at the Renode prompt:
runMacro $btn0Press    # BTN0 → toggle LED0
runMacro $btn1Press    # BTN1 → toggle LED1
```

### Expected UART output

```
=== CS281 Lab 5: GPIO Input Interrupts (Rust) ===
Simulate button presses from the Renode monitor:
  sysbus.gpio_in OnGPIO 0 True   (BTN0 -> toggles LED0)
  sysbus.gpio_in OnGPIO 1 True   (BTN1 -> toggles LED1)

Main loop running...
. . . .
[BTN0] LED0 ON
. . . .
[BTN0] LED0 OFF
. . . .
[BTN1] LED1 ON
```

## Make targets

| Target | Description |
|--------|-------------|
| `make` / `make all` | Build `target/riscv32im-unknown-none-elf/release/lab5r` |
| `make clean` | Remove `target/` |
| `make run` | Build and run in Renode |
| `make run-debug` | Run with GDB stub on `:3333`, CPU halted |
| `make debug-attach` | Attach `riscv64-elf-gdb` to the GDB stub |
| `make uart-connect` | `telnet localhost 3456` — UART output |
| `make monitor-connect` | `telnet localhost 1234` — Renode monitor |
| `make disasm` | Disassemble the ELF to stdout |

## How it compares to the assembly version

| Aspect | Assembly (`lab5-gpio-input`) | Rust (`lab5-gpio-input-rust`) |
|--------|------------------------------|-------------------------------|
| Language | RV32IM assembly | Rust (`#![no_std]`, `#![no_main]`) |
| Reset vector | `hardware/lib/startup.S` | `riscv-rt` crate (invisible) |
| Trap frame (save/restore) | Hand-rolled `sw`/`lw` in `main.S` | `riscv-rt` crate (invisible) |
| ISR logic | Assembly (xori, beqz, …) | Pure Rust, named register fields |
| MMIO access | `lw` / `sw` with explicit registers | `VolatileCell<T>` wrapper, field names |
| UART output | `uart_puts` in `uart.S` | `write!(uart, "{}", value)` |
| Linker script | `hardware/lib/cs281.ld` | `memory.x` → `riscv-rt`'s `link.x` |
| Build | `make` + `riscv64-elf-as` / `ld` | `cargo build --release` |

## Key Rust concepts demonstrated

**`riscv-rt` + `#[entry]`** — The `riscv-rt` crate provides the reset vector,
`.data`/`.bss` initialisation, `mtvec` setup, and a complete register-save/
restore trap frame — all generated from within the crate, invisible to
application code. Marking `main()` with `#[entry]` is the only startup
requirement.

**`DefaultHandler`** — riscv-rt's fallback hook for any interrupt that doesn't
have a dedicated handler.  The crate saves all registers before calling it and
restores them and executes `mret` after it returns.  The function body is pure
Rust, interrupt logic only.

**`#[repr(C)]` — stable memory layout, not "C code"** — By default, Rust is
free to reorder and re-pad struct fields however it likes for optimization.
That is fine for ordinary data, but a peripheral register map is different:
the hardware places `txfull` at byte offset +0x04 regardless of what Rust
prefers. `#[repr(C)]` forces fields to stay in declaration order with standard
C-compatible alignment — not because this code has anything to do with C, but
because C's layout rules are the stable, documented contract that matches what
the hardware manual describes. Without it, Rust could silently rearrange the
struct and every register access would target the wrong address.

**`extern "C"` — stable calling convention, not "C code"** — A calling
convention is the contract between a caller and a callee about which registers
carry arguments, which must be preserved across a call, and where the return
address lives. Rust's native calling convention is intentionally *unstable* —
the compiler can change it between versions and makes no guarantees about it.
`extern "C"` selects the platform's C ABI instead, which is stable and
well-specified for this target. `DefaultHandler` is invoked by riscv-rt's
assembly dispatcher, which was written expecting that stable contract. Using
Rust's own ABI here would corrupt registers and crash. Again, this says nothing
about the C language itself — C's ABI is simply the industry-standard stable
interface that binary components agree on when they need to call each other.

In short: `#[repr(C)]` is a promise about *where data lives in memory*;
`extern "C"` is a promise about *how a function is called*. Both use C's
definitions as a stable reference point, not because C is involved, but because
those definitions are the agreed-upon stable interface across compilers,
assemblers, and hardware descriptions.

**`VolatileCell<T>`** — A thin wrapper around `UnsafeCell<T>` that uses
`read_volatile` / `write_volatile` internally.  All `unsafe` is confined to
this one type; every call site is safe Rust.

**`impl fmt::Write for Uart`** — The standard Rust trait for text output.
Once implemented, `write!(uart, "[BTN0] LED0 {}\r\n", state)` works with full
format-string support (integers, strings, padding, …) — no heap, no `printf`.

**`core::hint::black_box`** — Prevents the optimizer from eliminating the
delay loop while keeping the code in pure Rust, without inline assembly.

## Architecture

```
src/main.rs
├── VolatileCell<T>          safe volatile MMIO wrapper
├── UartRegs / Uart          LiteX UART, impl fmt::Write
├── GpioOutRegs / GpioOut    LED peripheral
├── GpioInRegs  / GpioIn     Button peripheral
├── DefaultHandler()         ISR — GPIO pending → toggle LED → clear → return
└── main()  [#[entry]]       init GPIO, enable IRQ, loop printing dots
```

The `riscv-rt` and `riscv` crates are compiled once and cached; they don't
appear in this source tree.
