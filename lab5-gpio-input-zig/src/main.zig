//! CS281 Lab 5 — GPIO Input Interrupts (Zig)
//!
//! Demonstrates Zig's bare-metal capabilities on the CS281 board.
//! Functionally identical to the assembly and Rust versions.
//!
//! Key concepts:
//!
//! `extern struct` — stable C-compatible layout declared at the type level.
//!   "extern" here means the struct has a stable, externally-defined layout;
//!   it has nothing to do with C as a language.  Compare to Rust where the
//!   same promise is expressed as a separate #[repr(C)] attribute.
//!
//! `*volatile T`  — volatile is a property of the *pointer*, not of individual
//!   fields.  One cast makes every access through that pointer volatile.
//!   No wrapper type needed; no unsafe block.
//!
//! `export fn`    — single keyword for what Rust needs two annotations to say:
//!   #[no_mangle] (keep the exact symbol name) + extern "C" (use the stable
//!   C calling convention).  The C ABI is chosen because it is the stable,
//!   well-specified contract — not because C is involved.
//!
//! `callconv(.{ .riscv32_interrupt = .{} })` — Zig 0.14+'s equivalent of C's
//!   __attribute__((interrupt("machine"))).  The compiler generates the full
//!   register save/restore frame and emits `mret` instead of `ret`.
//!   mtvec points directly at this function — no naked wrapper required.
//!   This is something Rust cannot express without an external crate (riscv-rt).
//!
//! `comptime fmt` — format strings are validated at compile time, like Rust's
//!   write! macro, with no runtime parsing and no heap allocation.
//!
//! The only assembly in this file is the ~15-line _start function that sets up
//! the stack and initialises .data/.bss.  The ecosystem does not yet provide a
//! bare-metal startup crate for custom boards the way riscv-rt does for Rust.

const std = @import("std");

// ── Board constants ───────────────────────────────────────────────────────────

const UART_BASE:     usize = 0xe000_1800;
const GPIO_OUT_BASE: usize = 0xe001_5000;
const GPIO_IN_BASE:  usize = 0xe001_5400;

const BTN0: u32 = 1 << 0;
const BTN1: u32 = 1 << 1;
const LED0: u32 = 1 << 0;
const LED1: u32 = 1 << 1;

// ── Peripheral register maps ──────────────────────────────────────────────────

const UartRegs = extern struct {
    rxtx:       u32,  // +0x00  W=TX byte  R=RX byte
    txfull:     u32,  // +0x04  1=TX FIFO full
    rxempty:    u32,  // +0x08
    ev_status:  u32,  // +0x0C
    ev_pending: u32,  // +0x10
    ev_enable:  u32,  // +0x14
};

const GpioOutRegs = extern struct {
    out: u32,         // +0x00  bit N drives LED N
};

const GpioInRegs = extern struct {
    in:          u32, // +0x00  current pin levels
    irq_mode:    u32, // +0x04  0=Edge
    irq_edge:    u32, // +0x08  0=Rising
    irq_status:  u32, // +0x0C
    irq_pending: u32, // +0x10  write 1 to clear
    irq_enable:  u32, // +0x14  write 1 to arm
};

// Volatile on the pointer — all field accesses below are volatile.
const uart     = @as(*volatile UartRegs,    @ptrFromInt(UART_BASE));
const gpio_out = @as(*volatile GpioOutRegs, @ptrFromInt(GPIO_OUT_BASE));
const gpio_in  = @as(*volatile GpioInRegs,  @ptrFromInt(GPIO_IN_BASE));

// ── UART output ───────────────────────────────────────────────────────────────

fn writeByte(b: u8) void {
    while (uart.txfull != 0) {}
    uart.rxtx = b;
}

fn writeStr(s: []const u8) void {
    for (s) |c| writeByte(c);
}

fn print(comptime fmt: []const u8, args: anytype) void {
    var buf: [128]u8 = undefined;
    const s = std.fmt.bufPrint(&buf, fmt, args) catch return;
    writeStr(s);
}

// ── Interrupt handler ─────────────────────────────────────────────────────────
//
// callconv(.{ .riscv32_interrupt = .{} }) tells the compiler this is a
// machine-mode interrupt handler.  It generates:
//
//   - a prologue that saves every register the function modifies
//   - the handler body (pure Zig, no assembly)
//   - an epilogue that restores those registers
//   - `mret` as the return instruction
//
// mtvec is pointed at this function directly in main().
// No naked wrapper, no manual sw/lw frame — the compiler does it all.
// This is Zig's equivalent of C's __attribute__((interrupt("machine"))).

export fn trap_handler() callconv(.{ .riscv32_interrupt = .{ .mode = .machine } }) void {
    const pending = gpio_in.irq_pending;

    if (pending & BTN0 != 0) {
        gpio_out.out ^= LED0;
        const state = if (gpio_out.out & LED0 != 0) "ON" else "OFF";
        print("\r\n[BTN0] LED0 {s}\r\n", .{state});
    }
    if (pending & BTN1 != 0) {
        gpio_out.out ^= LED1;
        const state = if (gpio_out.out & LED1 != 0) "ON" else "OFF";
        print("\r\n[BTN1] LED1 {s}\r\n", .{state});
    }

    // Must clear before returning — otherwise the peripheral re-asserts
    // the interrupt the moment mret re-enables it.
    gpio_in.irq_pending = BTN0 | BTN1;
}

// ── Entry point and startup ───────────────────────────────────────────────────
//
// _start is the only assembly in this file.  It sets up the stack pointer,
// copies .data from ROM to RAM, zeroes .bss, then calls main().
// This is what riscv-rt provides automatically for Rust; the Zig ecosystem
// does not yet have an equivalent for custom bare-metal boards.

export fn _start() callconv(.Naked) noreturn {
    asm volatile (
        \\la   sp, _stack_top
        \\
        \\la   t0, _sidata
        \\la   t1, _sdata
        \\la   t2, _edata
        \\.Lcopy:
        \\beq  t1, t2, .Lzero
        \\lw   t3, 0(t0)
        \\sw   t3, 0(t1)
        \\addi t0, t0, 4
        \\addi t1, t1, 4
        \\j    .Lcopy
        \\.Lzero:
        \\la   t0, _sbss
        \\la   t1, _ebss
        \\.Lzero_loop:
        \\beq  t0, t1, .Lmain
        \\sw   zero, 0(t0)
        \\addi t0, t0, 4
        \\j    .Lzero_loop
        \\.Lmain:
        \\call main
        \\.Lhalt:
        \\j    .Lhalt
    );
}

export fn main() void {
    writeStr("=== CS281 Lab 5: GPIO Input Interrupts (Zig) ===\r\n");
    writeStr("Simulate button presses from the Renode monitor:\r\n");
    writeStr("  sysbus.gpio_in OnGPIO 0 True   (BTN0 -> toggles LED0)\r\n");
    writeStr("  sysbus.gpio_in OnGPIO 1 True   (BTN1 -> toggles LED1)\r\n\r\n");
    writeStr("Main loop running...\r\n");

    gpio_in.irq_enable = BTN0 | BTN1;

    // Point mtvec directly at trap_handler.  The compiler has already
    // arranged for it to save registers and return with mret.
    asm volatile ("csrw mtvec, %[addr]"
        : : [addr] "r" (@intFromPtr(&trap_handler)));

    // Enable cpu line 12 (GPIO — non-standard, above the defined RISC-V
    // interrupt codes) then open the global interrupt gate.
    asm volatile ("csrs mie, %[mask]"
        : : [mask] "r" (@as(u32, 1 << 12)));
    asm volatile ("csrs mstatus, %[mask]"
        : : [mask] "r" (@as(u32, 1 << 3)));

    while (true) {
        // Delay loop.  We read and write through a *volatile pointer so the
        // compiler must execute every iteration — no asm required.
        var i: u32 = 4_000_000;
        const countdown: *volatile u32 = &i;
        while (countdown.* > 0) : (countdown.* -= 1) {}
        writeStr(". ");
    }
}

pub fn panic(_: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    while (true) {}
}
