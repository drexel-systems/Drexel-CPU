//! CS281 Lab 5 — GPIO Input Interrupts (Rust)
//!
//! Functionally identical to `lab5-gpio-input/main.S` — BTN0 and BTN1 trigger
//! rising-edge GPIO interrupts that toggle LED0 and LED1; main loops forever
//! printing dots.
//!
//! This version uses the embedded Rust ecosystem to show what systems
//! programming in Rust actually looks like:
//!
//! - **`riscv-rt`** supplies `_start`, `.data`/`.bss` init, `mtvec` setup, and
//!   a complete register-save/restore trap frame — all in crate-generated
//!   assembly.  None of that infrastructure is visible here.
//!
//! - **`#[entry]`** marks this file's `main` as the application entry point.
//!   The crate calls it after the hardware is ready; we never write `_start`.
//!
//! - **`DefaultHandler`** is the riscv-rt hook for any interrupt that doesn't
//!   have a dedicated handler.  On this board that's cpu line 12 (GPIO).
//!   The crate already saved every register before calling us; we just handle
//!   the event and return — no `mret`, no `sw`/`lw` visible in application code.
//!
//! - **`VolatileCell<T>`** + **`#[repr(C)]` register structs** give every
//!   peripheral a typed API with named fields instead of raw byte offsets.
//!
//! - **`impl fmt::Write for Uart`** enables `write!(uart, "...")` with full
//!   format-string support — no heap, no `printf`.
//!
//! # Build & Run
//!
//! ```
//! cd lab5-gpio-input-rust
//! make run          # cargo build --release, then Renode on :3456 / :1234
//! ```
//!
//! # Simulate buttons (Renode monitor, `make monitor-connect`)
//!
//! ```
//! sysbus.gpio_in OnGPIO 0 True    # BTN0 press → rising edge → ISR fires
//! sysbus.gpio_in OnGPIO 0 False   # BTN0 release
//! sysbus.gpio_in OnGPIO 1 True    # BTN1 press
//! sysbus.gpio_in OnGPIO 1 False   # BTN1 release
//! ```

#![no_std]
#![no_main]

use core::cell::UnsafeCell;
use core::fmt::{self, Write};
use core::panic::PanicInfo;
use riscv_rt::entry;

// ── Board constants ───────────────────────────────────────────────────────────

const UART_BASE:     usize = 0xe000_1800;
const GPIO_OUT_BASE: usize = 0xe001_5000;
const GPIO_IN_BASE:  usize = 0xe001_5400;

const BTN0: u32 = 1 << 0; // GPIO_IN  bit 0
const BTN1: u32 = 1 << 1; // GPIO_IN  bit 1
const LED0: u32 = 1 << 0; // GPIO_OUT bit 0
const LED1: u32 = 1 << 1; // GPIO_OUT bit 1

// ── VolatileCell<T> — safe volatile register access ───────────────────────────
//
// Hardware registers must be read and written with volatile semantics so the
// compiler never caches, elides, or reorders the access.  `UnsafeCell` opts
// the field out of Rust's aliasing rules; `read/write_volatile` supply the
// barrier.  All `unsafe` is confined to this type; callers see a safe API.

#[repr(transparent)]
struct VolatileCell<T>(UnsafeCell<T>);

// SAFETY: on this single-core bare-metal target the ISR runs only while
// mstatus.MIE is set, making main and the ISR mutually exclusive — no
// simultaneous access to any cell is possible.
unsafe impl<T> Sync for VolatileCell<T> {}

impl<T: Copy> VolatileCell<T> {
    #[inline(always)]
    fn read(&self) -> T {
        unsafe { core::ptr::read_volatile(self.0.get()) }
    }

    #[inline(always)]
    fn write(&self, val: T) {
        unsafe { core::ptr::write_volatile(self.0.get(), val) }
    }
}

// ── UART peripheral ───────────────────────────────────────────────────────────

/// LiteX UART register map (base 0xe000_1800).
///
/// `#[repr(C)]` guarantees that field offsets exactly match the hardware layout:
/// `rxtx` at +0x00, `txfull` at +0x04, … — no manual offset arithmetic needed.
#[repr(C)]
struct UartRegs {
    rxtx:       VolatileCell<u32>, // +0x00  W=TX byte  R=RX byte
    txfull:     VolatileCell<u32>, // +0x04  1=TX FIFO full (spin before write)
    rxempty:    VolatileCell<u32>, // +0x08  1=RX FIFO empty
    ev_status:  VolatileCell<u32>, // +0x0C
    ev_pending: VolatileCell<u32>, // +0x10
    ev_enable:  VolatileCell<u32>, // +0x14
}

/// Handle to the LiteX UART.  Cheaply constructible — just a typed pointer.
struct Uart(&'static UartRegs);

impl Uart {
    /// Bind to the UART at `base`.
    ///
    /// # Safety
    /// `base` must be the correct MMIO base address for a LiteX UART peripheral.
    unsafe fn new(base: usize) -> Self {
        Self(&*(base as *const UartRegs))
    }

    fn write_byte(&self, b: u8) {
        // Spin until the TX FIFO has room, then load the byte.
        while self.0.txfull.read() != 0 {}
        self.0.rxtx.write(b as u32);
    }
}

/// `fmt::Write` enables `write!(uart, "…", …)` with full format-string
/// support: integers, strings, padding, precision — all without a heap.
impl fmt::Write for Uart {
    fn write_str(&mut self, s: &str) -> fmt::Result {
        for b in s.bytes() {
            self.write_byte(b);
        }
        Ok(())
    }
}

// ── GPIO Output peripheral (LEDs) ─────────────────────────────────────────────

/// LiteX GPIO Output register map (base 0xe001_5000).
#[repr(C)]
struct GpioOutRegs {
    out: VolatileCell<u32>, // +0x00  bit N drives LED N
}

/// Handle to the GPIO output (LED) peripheral.
struct GpioOut(&'static GpioOutRegs);

impl GpioOut {
    unsafe fn new(base: usize) -> Self {
        Self(&*(base as *const GpioOutRegs))
    }

    /// Flip the output bits selected by `mask`.
    fn toggle(&self, mask: u32) {
        self.0.out.write(self.0.out.read() ^ mask);
    }

    /// Return `true` if all bits in `mask` are currently driven high.
    fn is_set(&self, mask: u32) -> bool {
        self.0.out.read() & mask == mask
    }
}

// ── GPIO Input peripheral (buttons / DIP switches) ───────────────────────────

/// LiteX GPIO Input register map (base 0xe001_5400).
#[repr(C)]
struct GpioInRegs {
    r#in:        VolatileCell<u32>, // +0x00  current pin levels (read-only)
    irq_mode:    VolatileCell<u32>, // +0x04  0=Edge, 1=Change
    irq_edge:    VolatileCell<u32>, // +0x08  0=Rising, 1=Falling
    irq_status:  VolatileCell<u32>, // +0x0C  hardware status (read-only)
    irq_pending: VolatileCell<u32>, // +0x10  read=pending; write 1=clear
    irq_enable:  VolatileCell<u32>, // +0x14  write 1 to arm a pin
}

/// Handle to the GPIO input (button/DIP) peripheral.
struct GpioIn(&'static GpioInRegs);

impl GpioIn {
    unsafe fn new(base: usize) -> Self {
        Self(&*(base as *const GpioInRegs))
    }

    /// Arm rising-edge IRQ detection for each bit set in `mask`.
    ///
    /// The peripheral defaults to Edge + Rising mode, so only the enable
    /// register needs to be written.
    fn enable_irq(&self, mask: u32) {
        self.0.irq_enable.write(mask);
    }

    /// Return the current IRQ pending bitmask.
    fn pending(&self) -> u32 {
        self.0.irq_pending.read()
    }

    /// Clear the pending bits selected by `mask`.
    ///
    /// **Must** be called before returning from the ISR.  Omitting this causes
    /// the peripheral to immediately re-assert the interrupt after `mret`.
    fn clear_pending(&self, mask: u32) {
        self.0.irq_pending.write(mask);
    }
}

// ── Interrupt handler ─────────────────────────────────────────────────────────
//
// `DefaultHandler` is riscv-rt's fallback symbol for any interrupt that does
// not have a dedicated Rust handler.  On the CS281 board the only such
// interrupt is cpu line 12 (GPIO input), since lines 3/7/11 (standard RISC-V
// software/timer/external) are not used in this lab.
//
// riscv-rt already saved every caller-saved register before reaching this
// function and will restore them and execute `mret` after it returns.
// Nothing here is boilerplate — every line does useful work.

#[no_mangle]
unsafe extern "C" fn DefaultHandler() {
    let gpio_in  = GpioIn::new(GPIO_IN_BASE);
    let gpio_out = GpioOut::new(GPIO_OUT_BASE);
    let mut uart = Uart::new(UART_BASE);

    let pending = gpio_in.pending();

    // Toggle the LED and read back the register to report ON/OFF.
    // The hardware register *is* the state — no shadow variable needed.
    if pending & BTN0 != 0 {
        gpio_out.toggle(LED0);
        write!(uart, "\r\n[BTN0] LED0 {}\r\n",
               if gpio_out.is_set(LED0) { "ON" } else { "OFF" }).ok();
    }
    if pending & BTN1 != 0 {
        gpio_out.toggle(LED1);
        write!(uart, "\r\n[BTN1] LED1 {}\r\n",
               if gpio_out.is_set(LED1) { "ON" } else { "OFF" }).ok();
    }

    // Clear pending bits before returning — prevents immediate re-entry.
    gpio_in.clear_pending(BTN0 | BTN1);
}

// ── Enable GPIO interrupt (cpu line 12) ───────────────────────────────────────
//
// Standard RISC-V defines interrupt lines 0–11; line 12 is a platform-defined
// local interrupt used by this board for GPIO input.  The `riscv` crate only
// covers lines 0–11, so one asm line is needed to set the non-standard bit.

unsafe fn enable_gpio_irq() {
    // Set bit 12 in mie (machine interrupt enable).
    core::arch::asm!("csrs mie, {}", in(reg) 1u32 << 12);
    // Open the global interrupt gate (mstatus.MIE).
    riscv::interrupt::enable();
}

// ── Main ──────────────────────────────────────────────────────────────────────

#[entry]
fn main() -> ! {
    // SAFETY: all base addresses are correct for this board.
    let mut uart = unsafe { Uart::new(UART_BASE) };
    let gpio_in  = unsafe { GpioIn::new(GPIO_IN_BASE) };

    write!(uart, "=== CS281 Lab 5: GPIO Input Interrupts (Rust) ===\r\n").ok();
    write!(uart, "Simulate button presses from the Renode monitor:\r\n").ok();
    write!(uart, "  sysbus.gpio_in OnGPIO 0 True   (BTN0 -> toggles LED0)\r\n").ok();
    write!(uart, "  sysbus.gpio_in OnGPIO 1 True   (BTN1 -> toggles LED1)\r\n\r\n").ok();
    write!(uart, "Main loop running...\r\n").ok();

    // Arm rising-edge IRQ for both buttons.
    gpio_in.enable_irq(BTN0 | BTN1);

    // riscv-rt already set up mtvec before calling main().
    // We only need to enable the interrupt source and open the gate.
    unsafe { enable_gpio_irq() };

    // Main loop — prints a dot roughly every 0.08 s at 100 MHz.
    // The ISR fires asynchronously between any two instructions.
    // black_box prevents the optimizer from eliminating the delay loop.
    loop {
        for i in (0..4_000_000u32).rev() {
            core::hint::black_box(i);
        }
        write!(uart, ". ").ok();
    }
}

// ── Panic handler ─────────────────────────────────────────────────────────────

#[panic_handler]
fn panic(_info: &PanicInfo) -> ! {
    loop {}
}
