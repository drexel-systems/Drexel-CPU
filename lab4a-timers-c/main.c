/* =============================================================================
 * CS281 Lab 4a — Interrupt-Based Timers  (C reference implementation)
 * File: lab4a-timers-c/main.c
 *
 * Purpose
 *   This lab shows interrupt-driven timing in C before you implement the same
 *   thing in RISC-V assembly in lab4b.  Read this file carefully — every
 *   concept here has a direct assembly equivalent you will write next.
 *
 * What you will see on UART (make uart-connect)
 *
 *   === CS281 Lab 4a: Interrupt-Based Timers (C) ===
 *
 *   Main loop running -- printing a dot every ~500 ms
 *   Timer interrupt fires every 1 second
 *
 *   . . 
 *   [TICK 1]
 *   . . 
 *   [TICK 2]
 *   . . 
 *   [TICK 3]
 *   ...
 *
 * How it works
 *   main() burns cycles in a busy loop and prints a dot periodically.
 *   It has no idea a timer exists.  Every 1 second the LiteX Timer fires
 *   CPU interrupt line 11, the CPU jumps to machine_trap_handler(), the
 *   ISR prints "[TICK N]" and clears the hardware flag, then mret returns
 *   the CPU to exactly the instruction in main where it was interrupted.
 *
 * C → Assembly mapping (preview of lab4b)
 *   Every construct in this file compiles to a small sequence of RISC-V
 *   instructions.  Comments throughout show what the compiler generates.
 * =============================================================================*/

#include <stdint.h>

/* ── Timer peripheral register map ─────────────────────────────────────────
 * The LiteX_Timer uses 8-bit CSR sub-registers.  The 32-bit LOAD and RELOAD
 * values are each split across FOUR 8-bit registers at consecutive 4-byte
 * addresses, written MSB first (reg[0] = bits 31:24, reg[3] = bits 7:0).
 *
 * Single-bit registers (EN, EV_PENDING, EV_ENABLE) are one word each.
 *
 * Full register map (offsets from 0xe0002000):
 *   0x00  LOAD[31:24]    0x04  LOAD[23:16]    0x08  LOAD[15:8]    0x0C  LOAD[7:0]
 *   0x10  RELOAD[31:24]  0x14  RELOAD[23:16]  0x18  RELOAD[15:8]  0x1C  RELOAD[7:0]
 *   0x20  EN             0x3C  EV_PENDING      0x40  EV_ENABLE
 *
 * In assembly (lab4b) writing 100,000,000 = 0x05F5E100 to LOAD looks like:
 *   li   t0, 0xe0002000      # TIMER_BASE
 *   li   t1, 0x05
 *   sw   t1, 0x00(t0)        # LOAD[31:24]
 *   li   t1, 0xF5
 *   sw   t1, 0x04(t0)        # LOAD[23:16]
 *   li   t1, 0xE1
 *   sw   t1, 0x08(t0)        # LOAD[15:8]
 *   sw   x0, 0x0C(t0)        # LOAD[7:0] = 0
 */
#define TIMER_BASE          0xe0002000UL

/* Sub-register arrays for LOAD and RELOAD (each has 4 elements at +0,+4,+8,+C) */
#define TIMER_LOAD_REGS     ((volatile uint32_t *)(TIMER_BASE + 0x00))
#define TIMER_RELOAD_REGS   ((volatile uint32_t *)(TIMER_BASE + 0x10))

/* Single-word control/event registers */
#define TIMER_EN            (*(volatile uint32_t *)(TIMER_BASE + 0x20))
#define TIMER_EV_PENDING    (*(volatile uint32_t *)(TIMER_BASE + 0x3C))
#define TIMER_EV_ENABLE     (*(volatile uint32_t *)(TIMER_BASE + 0x40))

/* 100 MHz timer clock → 100,000,000 ticks = 1 second */
#define TIMER_FREQ          100000000UL

/* Iterations of busy work between dots.  The volatile C loop runs ~5
 * instructions per iteration, so 4,000,000 × 5 ≈ 20M instructions ≈ 0.2 s.
 * Expect ~4–5 dots per 1-second tick. */
#define DOT_DELAY           4000000UL

/* ── UART driver (implemented in hardware/lib/uart.S) ──────────────────── */
extern void uart_putchar(char c);
extern void uart_puts(const char *s);

/* ── Shared state: written by ISR, read by main ─────────────────────────
 * 'volatile' is required here too — without it the compiler might cache
 * tick_count in a register and never re-read it after the ISR updates it.
 *
 * In assembly (lab4b):
 *   .section .bss
 *   tick_count: .space 4
 */
static volatile uint32_t tick_count = 0;


/* ── Helper: write a 32-bit value to a split 8-bit CSR register ─────────────
 * 'regs' points to the MSB sub-register; four consecutive writes fill the
 * full 32-bit value MSB first.  regs[0]=bits[31:24] ... regs[3]=bits[7:0].
 *
 * In assembly (lab4b) you do this manually with four 'sw' instructions.
 */
static void timer_write32(volatile uint32_t *regs, uint32_t val)
{
    regs[0] = (val >> 24) & 0xFF;
    regs[1] = (val >> 16) & 0xFF;
    regs[2] = (val >>  8) & 0xFF;
    regs[3] = (val >>  0) & 0xFF;
}


/* ── Helper: print an unsigned integer over UART ────────────────────────── */
static void uart_put_uint(uint32_t n)
{
    if (n == 0) { uart_putchar('0'); return; }
    char buf[10];
    int  i = 0;
    while (n > 0) {
        buf[i++] = '0' + (int)(n % 10);
        n /= 10;
    }
    /* digits are in reverse order — print back to front */
    while (i > 0) uart_putchar(buf[--i]);
}


/* ── Interrupt Service Routine ──────────────────────────────────────────────
 *
 * __attribute__((interrupt("machine"))) tells GCC:
 *   1. Save ALL general-purpose registers on entry (not just caller-saved ones,
 *      since we don't know what main was doing when the interrupt fired).
 *   2. Use 'mret' instead of 'ret' to return — mret restores mstatus.MIE and
 *      jumps to mepc (the instruction that was interrupted in main).
 *
 * In assembly (lab4b) you write this prologue and epilogue yourself:
 *   addi  sp, sp, -64
 *   sw    ra,  0(sp)
 *   sw    t0,  4(sp)
 *   ... (save all registers)
 *   mret
 *
 * mcause layout:
 *   bit 31    = 1 → interrupt (not an exception)
 *   bits[30:0] = source number
 *   LiteX Timer on CPU line 11 → mcause = 0x8000000B
 */
__attribute__((interrupt("machine")))
void machine_trap_handler(void)
{
    uint32_t mcause;
    /* csrr = "CSR Read" — reads a control/status register into a variable.
     * In assembly:  csrr t0, mcause */
    __asm__ volatile("csrr %0, mcause" : "=r"(mcause));

    if (mcause == 0x8000000Bu) {

        /* ── Step A: count the tick ───────────────────────────────── */
        tick_count++;
        /* In assembly (lab4b):
         *   la   t0, tick_count
         *   lw   t1, 0(t0)
         *   addi t1, t1, 1
         *   sw   t1, 0(t0)                                           */

        /* ── Step B: print the tick (runs while main is frozen) ───── */
        uart_puts("\r\n[TICK ");
        uart_put_uint(tick_count);
        uart_puts("]\r\n");

        /* ── Step C: clear the hardware interrupt flag ────────────────
         * Writing 1 to TIMER_EV_PENDING tells the LiteX Timer peripheral
         * "acknowledged."  If you skip this, the timer keeps its interrupt
         * line asserted.  The moment mret executes the CPU sees the line
         * still high, jumps back into the ISR, and is stuck in an infinite
         * interrupt loop — main never runs again.
         *
         * In assembly (lab4b):
         *   li   t0, (TIMER_BASE + TIMER_EV_PENDING)  # 0xe000203C
         *   li   t1, 1
         *   sw   t1, 0(t0)                                           */
        TIMER_EV_PENDING = 1;
    }
}


/* ── timer_init: configure the LiteX Timer ─────────────────────────────────
 *
 * The timer counts DOWN from LOAD to 0, fires an interrupt, reloads from
 * RELOAD, and repeats.  Setting RELOAD = 0 makes the timer one-shot; we
 * set RELOAD = TIMER_FREQ so it keeps firing every second.
 *
 * LOAD and RELOAD are each written via timer_write32 (four 8-bit sub-regs).
 *
 * In assembly (lab4b) you will implement this function as a TODO.
 */
static void timer_init(void)
{
    TIMER_EV_ENABLE = 1;                          /* route → CPU line 11  */
    timer_write32(TIMER_LOAD_REGS,   TIMER_FREQ); /* set 1-second interval */
    timer_write32(TIMER_RELOAD_REGS, TIMER_FREQ); /* auto-reload each tick */
    TIMER_EN        = 1;                          /* start counting        */
}


/* ── enable_interrupts: open the RISC-V CPU interrupt gates ─────────────────
 *
 * Two CSR gates must both be open before an interrupt reaches the CPU:
 *
 *   mie bit 11  — per-source gate for CPU line 11 (LiteX Timer)
 *   mstatus bit 3 — global machine interrupt enable (master switch)
 *
 * 'csrs' = "CSR Set bits" — sets the specified bits without clearing others.
 *
 * In assembly (lab4b) you will implement this function as a TODO.
 */
static void enable_interrupts(void)
{
    /* Enable CPU line 11 in mie */
    __asm__ volatile("csrs mie, %0" :: "r"(1u << 11));

    /* Set global MIE bit in mstatus — interrupts are now live */
    __asm__ volatile("csrs mstatus, %0" :: "r"(1u << 3));
}


/* ── main ───────────────────────────────────────────────────────────────────
 *
 * Main has no knowledge of the timer.  It just does its own work forever.
 * The interrupt fires asynchronously and is completely transparent to main.
 */
int main(void)
{
    /* Point mtvec at our trap handler before enabling anything.
     * Direct mode: bits[1:0] = 00, so mtvec holds the raw function address.
     * In assembly:
     *   la   t0, machine_trap_handler
     *   csrw mtvec, t0                                               */
    __asm__ volatile("csrw mtvec, %0" :: "r"(machine_trap_handler));

    uart_puts("=== CS281 Lab 4a: Interrupt-Based Timers (C) ===\r\n\r\n");
    uart_puts("Main loop running -- printing a dot every ~500 ms\r\n");
    uart_puts("Timer interrupt fires every 1 second\r\n\r\n");

    timer_init();
    enable_interrupts();

    /* ── Busy-work loop ─────────────────────────────────────────────
     * main is completely unaware of the timer.  The 'volatile' on the
     * loop counter prevents the compiler from optimizing the loop away.
     *
     * In assembly (lab4b):
     *   li   t0, DOT_DELAY
     * .Lbusy:
     *   addi t0, t0, -1
     *   bnez t0, .Lbusy
     *   la   a0, str_dot
     *   call uart_puts
     *   j    .Lmain_loop                                             */
    while (1) {
        for (volatile uint32_t i = DOT_DELAY; i > 0; i--);
        uart_puts(". ");
    }

    return 0;
}
