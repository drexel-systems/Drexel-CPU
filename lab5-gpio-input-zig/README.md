# CS281 Lab 5 — GPIO Input Interrupts (Zig)

A bare-metal Zig port of `lab5-gpio-input`. Functionally identical to the
assembly, C, and Rust versions. Requires **Zig 0.14.0+**.

## What this demonstrates

This version sits at the end of a three-language arc:

| | C | Rust | Zig |
|--|--|--|--|
| Layout contract | `volatile T*` cast + `__attribute__((packed/aligned))` | `#[repr(C)]` attribute | `extern struct` — in the type name |
| Volatile access | Per-field `volatile` cast | `VolatileCell<T>` wrapper | `*volatile T` pointer — one cast covers all fields |
| Stable ABI | `__attribute__((noinline))` / default | `#[no_mangle] extern "C"` — two annotations | `export fn` — one keyword |
| Interrupt frame | `__attribute__((interrupt("machine")))` | riscv-rt crate | `callconv(.{ .riscv32_interrupt = .{ .mode = .machine } })` |
| Format output | hand-written `uart_puts` | `write!(uart, "{}", val)` | `print("{s}", .{val})` with `comptime` fmt |
| Startup boilerplate | `startup.S` | riscv-rt crate (invisible) | `_start` naked fn (15 lines) |

### `extern struct` vs `#[repr(C)]`

In Rust, the stable-layout promise is a separate attribute bolted on top of a
normal struct declaration. In Zig, `extern struct` encodes that promise in the
type itself — the word "extern" in the type declaration means "this struct has
a stable, externally-defined layout." The contract is part of the type, not an
annotation.

### `*volatile T` vs `VolatileCell<T>`

In Rust, volatile access requires a wrapper type (`VolatileCell`) because
volatile is not a pointer qualifier. In Zig, casting to `*volatile T` makes
every field access through that pointer volatile — no wrapper needed. The
volatile contract lives on the pointer, where it belongs.

### `callconv(.{ .riscv32_interrupt = .{ .mode = .machine } })`

This is Zig 0.14+'s equivalent of C's `__attribute__((interrupt("machine")))`.
The compiler generates the register save/restore frame and emits `mret` instead
of `ret`. `mtvec` points directly at `trap_handler` — no naked wrapper, no
manual assembly frame. Rust does not have this as a built-in language feature;
the Rust version achieves the same result through the `riscv-rt` crate.

## Installation

### 1. Install Zig 0.14.0+

Download from <https://ziglang.org/download/>, or use the version bundled with
the VS Code Zig extension.  Verify:
```bash
zig version   # must be 0.14.0 or later
```

> **macOS + Xcode 26 note:** `zig build` fails on Xcode 26 with Zig 0.14.x
> (macOS SDK linker issue in the build runner).  The Makefile uses
> `zig build-exe` directly to bypass the build runner — no workaround needed.

### 2. RISC-V GNU toolchain (for `make disasm` and `make debug-attach`)

Already installed if you have set up other CS281 labs.

## Quick start

```bash
cd lab5-gpio-input-zig
make              # zig build-exe → zig-out/bin/lab5z

make run          # launch Renode (UART :3456, monitor :1234)
make uart-connect # second terminal — see output
make monitor-connect
# then:
runMacro $btn0Press   # BTN0 → toggle LED0
runMacro $btn1Press   # BTN1 → toggle LED1
```

## Make targets

| Target | Description |
|--------|-------------|
| `make` / `make all` | `zig build-exe` → `zig-out/bin/lab5z` |
| `make clean` | Remove `zig-out/` and `.zig-cache/` |
| `make run` | Build and launch in Renode |
| `make run-debug` | Run with GDB stub on `:3333`, CPU halted |
| `make debug-attach` | Attach `riscv64-elf-gdb` |
| `make uart-connect` | `telnet localhost 3456` |
| `make monitor-connect` | `telnet localhost 1234` |
| `make disasm` | Disassemble the ELF |

## Architecture

```
src/main.zig
├── extern struct UartRegs / GpioOutRegs / GpioInRegs   register maps
├── *volatile pointers                                   MMIO handles
├── writeByte / writeStr / print(comptime fmt)           UART output
├── trap_handler()  [callconv(.riscv32_interrupt)]       ISR — no asm frame
├── _start()        [callconv(.Naked)]                   startup — only asm
└── main()                                               init, enable IRQ, loop

cs281.ld     board memory map (ROM @ 0x20000000, RAM @ 0x40000000)
build.zig    target: riscv32-freestanding-none +m extension
```

## Note on `callconv` syntax

The `callconv(.{ .riscv32_interrupt = .{ .mode = .machine } })` syntax was
introduced in Zig 0.14 when `CallingConvention` was reworked into a tagged
union.  The `mode` field is required — `.{}` alone will fail.  If you see a
compile error on that line, run `zig version` to confirm your Zig version is
0.14.0 or later.
