/* =============================================================================
 * CS281 Lab 2 — Blinky with Timer Interrupt
 * File: lab2-blinky2/main.S
 *
 * Objective
 *   Blink LED0 forever using a hardware timer interrupt instead of a
 *   busy-wait loop.
 *
 * Concepts introduced
 *   mtvec    — machine trap-vector: where the CPU jumps on any trap
 *   CLINT    — Core-Level Interruptor: MTIME (free-running 64-bit counter
 *              at 100 MHz) and MTIMECMP (fires IRQ when MTIME >= MTIMECMP)
 *   mie      — machine interrupt enable register (bit 7 = MTIE)
 *   mstatus  — machine status register (bit 3 = MIE, global interrupt gate)
 *   WFI      — Wait For Interrupt: idles the core until an interrupt fires
 *   mret     — return from trap, restores mstatus.MIE from mstatus.MPIE
 *
 * Execution flow
 *   1. main() sets mtvec → trap_handler
 *   2. MTIMECMP = MTIME + HALF_PERIOD  (first deadline)
 *   3. MTIE and MIE are enabled
 *   4. main() enters WFI loop — CPU does zero work while waiting
 *   5. When MTIME reaches MTIMECMP the CPU wakes and jumps to trap_handler
 *   6. trap_handler toggles LED, prints UART, advances MTIMECMP, mret
 *   7. Repeat forever
 *
 * Compare with Lab 1
 *   Lab 1 burned CPU cycles counting down a register.  Lab 2 idles with WFI
 *   between interrupts — the CPU does no work while waiting.  On real hardware
 *   this translates directly to lower power consumption.  In Renode, WFI also
 *   lets the simulator advance virtual time without tight polling loops.
 *
 * UART output (make uart-connect)
 *   === CS281 Lab 2: Blinky with Timer Interrupt ===
 *   [IRQ] LED0 ON
 *   [IRQ] LED0 OFF
 *   [IRQ] LED0 ON
 *   ...
 * =============================================================================*/

    .include "../hardware/lib/cs281.inc"

/* ── Constants ────────────────────────────────────────────────────────────── */

/* Timer half-period in CLINT ticks (CLINT runs at 100 MHz simulated).
 * 50,000,000 ticks ON + 50,000,000 ticks OFF = 1 s per blink cycle.
 * Adjust if the blink rate looks wrong on your Renode version.            */
.equ HALF_PERIOD,   50000000

/* mie bit 7 = MTIE (machine timer interrupt enable)                       */
.equ MTIE_BIT,      (1 << 7)

/* ── Read-Only Data ───────────────────────────────────────────────────────── */
    .section .rodata
str_hello:  .string "=== CS281 Lab 2: Blinky with Timer Interrupt ===\r\n"
str_on:     .string "[IRQ] LED0 ON\r\n"
str_off:    .string "[IRQ] LED0 OFF\r\n"

/* ── Trap Handler ─────────────────────────────────────────────────────────── */
/*
 * Entered on every machine-mode trap because mtvec points here.
 * In this lab only MTIE is enabled, so the only trap we expect is the
 * machine timer interrupt (mcause = 0x80000007).
 *
 * Key rule: save every register you touch, including caller-saved ones,
 * because we are interrupting arbitrary code that may rely on them.
 *
 * Clearing the interrupt: writing a future value to MTIMECMP is all that
 * is needed — the hardware clears the pending bit automatically.
 * There is no separate acknowledge register.
 *
 * mret re-enables interrupts by copying mstatus.MPIE → mstatus.MIE.
 */
    .section .text
    .align  2                   /* mtvec bits 1:0 must be 00 (direct mode)  */
    .globl  trap_handler
    .type   trap_handler, @function

trap_handler:
    /* ── Save registers ──────────────────────────────────────────────────── */
    addi    sp, sp, -24
    sw      ra,  20(sp)
    sw      a0,  16(sp)
    sw      t0,  12(sp)
    sw      t1,   8(sp)
    sw      t2,   4(sp)

    /* ── Toggle LED0 ─────────────────────────────────────────────────────── */
    li      t0, GPIO_OUT_BASE
    lw      t1, 0(t0)           /* read current LED state                   */
    xori    t1, t1, LED0        /* flip LED0 bit                            */
    sw      t1, 0(t0)           /* write back                               */

    /* ── Print ON or OFF ─────────────────────────────────────────────────── */
    andi    t2, t1, LED0
    bnez    t2, .Lis_on
    la      a0, str_off
    j       .Lprint
.Lis_on:
    la      a0, str_on
.Lprint:
    call    uart_puts

    /* ── Advance MTIMECMP by HALF_PERIOD ─────────────────────────────────── */
    /* Read current MTIMECMP (not MTIME) and add HALF_PERIOD.  This avoids
     * drift from interrupt latency — each deadline is exactly HALF_PERIOD
     * after the previous one regardless of how long the handler took.      */
    li      t0, CLINT_MTIMECMP_ADDR
    lw      t1, 0(t0)           /* current MTIMECMP low word               */
    li      t2, HALF_PERIOD
    add     t1, t1, t2          /* next deadline                            */
    sw      t1, 0(t0)           /* writing MTIMECMP clears the pending IRQ  */

    /* ── Restore registers and return from trap ──────────────────────────── */
    lw      t2,   4(sp)
    lw      t1,   8(sp)
    lw      t0,  12(sp)
    lw      a0,  16(sp)
    lw      ra,  20(sp)
    addi    sp, sp, 24
    mret                        /* re-enables MIE from MPIE, returns to WFI */

    .size   trap_handler, . - trap_handler


/* ── main ─────────────────────────────────────────────────────────────────── */
    .globl  main
    .type   main, @function

main:
    /* ── Print startup banner ─────────────────────────────────────────────── */
    la      a0, str_hello
    call    uart_puts

    /* ── 1. Register trap handler (direct mode) ───────────────────────────── */
    la      t0, trap_handler
    csrw    mtvec, t0

    /* ── 2. Set first MTIMECMP deadline ──────────────────────────────────── */
    /* Safe 64-bit write sequence: set MTIMECMPH = 0xFFFFFFFF first so the
     * 64-bit compare can't fire while we update the low word.              */
    li      t0, CLINT_MTIMECMP_ADDR
    li      t1, 0xFFFFFFFF
    sw      t1, 4(t0)           /* MTIMECMPH = max → no spurious IRQ       */

    li      t0, CLINT_MTIME_ADDR
    lw      t2, 0(t0)           /* t2 = current MTIME low word             */
    li      t1, HALF_PERIOD
    add     t2, t2, t1

    li      t0, CLINT_MTIMECMP_ADDR
    sw      t2, 0(t0)           /* MTIMECMPL = MTIME + HALF_PERIOD         */
    sw      zero, 4(t0)         /* MTIMECMPH = 0                            */

    /* ── 3. Enable machine timer interrupt ───────────────────────────────── */
    li      t0, MTIE_BIT
    csrs    mie, t0             /* set MTIE (bit 7), leave other bits alone */

    /* ── 4. Enable global interrupts ─────────────────────────────────────── */
    csrsi   mstatus, 8          /* set mstatus.MIE (bit 3)                 */

    /* ── 5. Idle — the timer interrupt does all the work ─────────────────── */
.Lwfi_loop:
    wfi                         /* sleep until next interrupt               */
    j       .Lwfi_loop          /* loop back in case of spurious wake-up    */

    .size   main, . - main
