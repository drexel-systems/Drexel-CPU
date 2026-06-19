/* =============================================================================
 * CS281 Lab 4 — Interrupt-Based Timers
 * File: lab4-timers/main.S
 *
 * Objective
 *   Understand how a hardware timer interrupt works by observing it break into
 *   a running program.  The main loop is busy doing its own work (printing
 *   dots at a steady pace).  Every second, the LiteX Timer fires an interrupt,
 *   the CPU jumps to machine_trap_handler, prints a TICK line, clears the
 *   hardware flag, and returns — main resumes exactly where it was interrupted.
 *
 * Expected UART output (make uart-connect)
 *
 *   === CS281 Lab 4: Interrupt-Based Timers ===
 *   Main loop running — printing a dot every ~500 ms
 *   Timer interrupt will fire every 1 second
 *
 *   . . . . 
 *   [TICK 1]
 *   . . . . 
 *   [TICK 2]
 *   . . . . 
 *   [TICK 3]
 *   ...
 *
 *   The key insight: main never checks for ticks.  The ISR fires
 *   asynchronously, does its work, and hands control back.
 *
 * How it works
 *   ┌───────────────────────────────────────────────────────────────┐
 *   │  main:                    ISR fires here                      │
 *   │  . . . . [jump to ISR] → print "[TICK N]" → mret → . . . .  │
 *   └───────────────────────────────────────────────────────────────┘
 *
 *   The CPU automatically saves its position (mepc CSR) when an interrupt
 *   fires.  mret at the end of the ISR restores execution to that exact point.
 *   main never knows it was interrupted.
 *
 * Timer register map  (TIMER_BASE = 0xe0002000)
 *   The LiteX_Timer uses 8-bit CSR sub-registers.  32-bit values are written
 *   as four consecutive words, MSB first (reg0 = bits[31:24], reg3 = bits[7:0]).
 *
 *   LOAD sub-registers (4 × 8-bit, MSB first):
 *     +0x00 TIMER_LOAD0  bits[31:24]    +0x04 TIMER_LOAD1  bits[23:16]
 *     +0x08 TIMER_LOAD2  bits[15:8]     +0x0C TIMER_LOAD3  bits[7:0]
 *   RELOAD sub-registers (4 × 8-bit, MSB first):
 *     +0x10 TIMER_RELOAD0 bits[31:24]   +0x14 TIMER_RELOAD1 bits[23:16]
 *     +0x18 TIMER_RELOAD2 bits[15:8]    +0x1C TIMER_RELOAD3 bits[7:0]
 *   Single-word registers:
 *     +0x20 TIMER_EN          write 1 to start
 *     +0x3C TIMER_EV_PENDING  write 1 to CLEAR the interrupt  ← critical
 *     +0x40 TIMER_EV_ENABLE   write 1 to route timer → CPU line 11
 *
 * RISC-V CSR cheat sheet
 *   mtvec    set trap vector:   csrw mtvec, t0
 *   mie      per-source enable: csrs mie, t0       (set bits, don't clear others)
 *   mstatus  global enable:     csrs mstatus, t0   (bit 3 = MIE master switch)
 *   mcause   trap cause:        csrr t0, mcause    (bit31=interrupt, bits[30:0]=source)
 *
 * TODO summary
 *   Part 1 — timer_init:        configure and start the LiteX Timer
 *   Part 2 — enable_interrupts: open the CPU interrupt gates (mie + mstatus)
 *   Part 3 — ISR body:          increment tick_count, then clear EV_PENDING
 * =============================================================================*/

    .include "../hardware/lib/cs281.inc"

/* Timer counts down from TIMER_FREQ to 0 at 100 MHz → fires every 1 second */
.equ TIMER_FREQ,  100000000

/* Busy-wait iterations between dots.  The assembly loop is 2 instructions
 * per iteration, so 10,000,000 × 2 = 20M instructions ≈ 0.2 s per dot.
 * Expect ~4–5 dots per 1-second tick. */
.equ DOT_DELAY,   10000000

/* ── BSS: shared state between main and ISR ──────────────────────────────── */
    .section .bss
    .align 2
tick_count: .space 4        /* incremented by ISR each second */


/* =============================================================================
 * machine_trap_handler
 *
 * Entry point for ALL machine-mode traps (interrupts and exceptions).
 * Pointed to by mtvec (set in main before interrupts are enabled).
 *
 * Why we save/restore so many registers:
 *   The interrupt can fire at ANY instruction in main's busy-wait loop.
 *   Every register the ISR uses must be saved first and restored before mret,
 *   otherwise main's computation would be silently corrupted.
 *   We save all caller-saved registers (t0-t6, a0-a7) plus ra so the ISR
 *   can safely call uart_puts / uart_put_uint without clobbering main's state.
 *
 * TODO (Part 3): fill in the ISR body between the two marked lines.
 * =============================================================================*/
    .section .text
    .globl  machine_trap_handler
    .type   machine_trap_handler, @function
    .align  4                       /* mtvec requires 4-byte alignment */
machine_trap_handler:

    /* ── Save all registers the ISR might touch ── */
    addi    sp, sp, -64
    sw      ra,   0(sp)
    sw      t0,   4(sp)
    sw      t1,   8(sp)
    sw      t2,  12(sp)
    sw      a0,  16(sp)
    sw      a1,  20(sp)
    sw      a2,  24(sp)
    sw      a3,  28(sp)
    sw      a4,  32(sp)
    sw      a5,  36(sp)
    sw      a6,  40(sp)
    sw      a7,  44(sp)
    sw      t3,  48(sp)
    sw      t4,  52(sp)
    sw      t5,  56(sp)
    sw      t6,  60(sp)

    /* ── Identify interrupt source ── */
    csrr    t0, mcause
    /* LiteX Timer on CPU line 11:
     * mcause = 0x8000000B  (bit31=1 → interrupt, bits[30:0]=11) */
    li      t1, 0x8000000B
    bne     t0, t1, .Ltrap_done

    /* ══════════════════ TODO Part 3 — ISR body ══════════════════
     *
     * Step A: Increment tick_count
     *
     *   la   t0, tick_count
     *   lw   t1, 0(t0)
     *   addi t1, t1, 1
     *   sw   t1, 0(t0)
     *
     * ──────────────────────────────────────────────────────────── */
    la      t0, tick_count
    lw      t1, 0(t0)
    addi    t1, t1, 1
    sw      t1, 0(t0)

    /* (provided) print the tick number */
    la      a0, str_tick_pre        /* "\r\n[TICK " */
    call    uart_puts
    la      t0, tick_count
    lw      a0, 0(t0)
    call    uart_put_uint
    la      a0, str_tick_post       /* "]\r\n" */
    call    uart_puts

    /* ──────────────────────────────────────────────────────────────
     * Step B: Clear the LiteX Timer interrupt flag
     *
     *   THIS STEP IS CRITICAL.
     *   If you do not write 1 to TIMER_EV_PENDING, the LiteX Timer
     *   keeps its interrupt line asserted.  The moment mret executes,
     *   the CPU sees the line still high, jumps straight back into the
     *   ISR, and is stuck in an infinite interrupt loop — main never
     *   runs again.
     *
     *   li   t0, (TIMER_BASE + TIMER_EV_PENDING)   # 0xe000203C
     *   li   t1, 1
     *   sw   t1, 0(t0)
     *
     * ══════════════════════════════════════════════════════════════ */
    li      t0, (TIMER_BASE + TIMER_EV_PENDING)
    li      t1, 1
    sw      t1, 0(t0)

.Ltrap_done:
    /* ── Restore all saved registers ── */
    lw      ra,   0(sp)
    lw      t0,   4(sp)
    lw      t1,   8(sp)
    lw      t2,  12(sp)
    lw      a0,  16(sp)
    lw      a1,  20(sp)
    lw      a2,  24(sp)
    lw      a3,  28(sp)
    lw      a4,  32(sp)
    lw      a5,  36(sp)
    lw      a6,  40(sp)
    lw      a7,  44(sp)
    lw      t3,  48(sp)
    lw      t4,  52(sp)
    lw      t5,  56(sp)
    lw      t6,  60(sp)
    addi    sp, sp, 64

    mret                            /* resume main exactly where it left off */
    .size   machine_trap_handler, . - machine_trap_handler


/* =============================================================================
 * main — busy-work loop, unaware of the timer
 * =============================================================================*/
    .globl  main
    .type   main, @function
main:
    addi    sp, sp, -4
    sw      ra, 0(sp)

    /* Set trap vector before enabling interrupts */
    la      t0, machine_trap_handler
    csrw    mtvec, t0

    la      a0, str_banner
    call    uart_puts

    /* Part 1: start the timer */
    call    timer_init

    /* Part 2: open the CPU interrupt gates */
    call    enable_interrupts

    la      a0, str_running
    call    uart_puts

    /* ── Busy-work loop ─────────────────────────────────────────────
     * main has no idea a timer exists.  It just prints dots forever.
     * The interrupt fires asynchronously and breaks in when it needs to. */
.Lmain_loop:
    /* burn some cycles (simulates real work) */
    li      t0, DOT_DELAY
.Lbusy:
    addi    t0, t0, -1
    bnez    t0, .Lbusy

    /* print one dot */
    la      a0, str_dot
    call    uart_puts

    j       .Lmain_loop             /* repeat forever */

    .size   main, . - main


/* =============================================================================
 * timer_init — configure LiteX Timer for 1-second interrupts
 *
 * TODO (Part 1)
 *
 * TIMER_FREQ = 100,000,000 = 0x05F5E100.  Written byte-by-byte, MSB first:
 *   byte 0 = 0x05,  byte 1 = 0xF5,  byte 2 = 0xE1,  byte 3 = 0x00
 *
 * Steps:
 *   1. Enable interrupt routing (EV_ENABLE = 1)
 *   2. Write LOAD0–LOAD3   (MSB first) with the four bytes of TIMER_FREQ
 *   3. Write RELOAD0–RELOAD3 (same values — makes the timer auto-repeat)
 *   4. Enable the timer (EN = 1)
 *
 * Template for LOAD (repeat the pattern for RELOAD using TIMER_RELOAD0–3):
 *   li   t0, TIMER_BASE
 *   li   t1, TIMER_FREQ_B0          # 0x05
 *   sw   t1, TIMER_LOAD0(t0)        # offset 0x00 — bits[31:24]
 *   li   t1, TIMER_FREQ_B1          # 0xF5
 *   sw   t1, TIMER_LOAD1(t0)        # offset 0x04 — bits[23:16]
 *   li   t1, TIMER_FREQ_B2          # 0xE1
 *   sw   t1, TIMER_LOAD2(t0)        # offset 0x08 — bits[15:8]
 *   sw   x0, TIMER_LOAD3(t0)        # offset 0x0C — bits[7:0] = 0
 * =============================================================================*/
    .globl  timer_init
    .type   timer_init, @function
timer_init:
    li      t0, TIMER_BASE

    /* Enable interrupt routing first */
    li      t1, 1
    sw      t1, TIMER_EV_ENABLE(t0)     /* offset 0x40 */

    /* Write LOAD: 100,000,000 = 0x05F5E100, MSB first */
    li      t1, TIMER_FREQ_B0           /* 0x05 */
    sw      t1, TIMER_LOAD0(t0)         /* offset 0x00 — bits[31:24] */
    li      t1, TIMER_FREQ_B1           /* 0xF5 */
    sw      t1, TIMER_LOAD1(t0)         /* offset 0x04 — bits[23:16] */
    li      t1, TIMER_FREQ_B2           /* 0xE1 */
    sw      t1, TIMER_LOAD2(t0)         /* offset 0x08 — bits[15:8]  */
    sw      x0, TIMER_LOAD3(t0)         /* offset 0x0C — bits[7:0]   */

    /* Write RELOAD same values — enables auto-repeat every 1 second */
    li      t1, TIMER_FREQ_B0
    sw      t1, TIMER_RELOAD0(t0)       /* offset 0x10 */
    li      t1, TIMER_FREQ_B1
    sw      t1, TIMER_RELOAD1(t0)       /* offset 0x14 */
    li      t1, TIMER_FREQ_B2
    sw      t1, TIMER_RELOAD2(t0)       /* offset 0x18 */
    sw      x0, TIMER_RELOAD3(t0)       /* offset 0x1C */

    /* Start the timer */
    li      t1, 1
    sw      t1, TIMER_EN(t0)            /* offset 0x20 */

    ret
    .size   timer_init, . - timer_init


/* =============================================================================
 * enable_interrupts — unmask CPU interrupt line 11
 *
 * TODO (Part 2)
 *
 * Two CSR gates must both be open for the interrupt to reach the CPU:
 *
 *   mie bit 11  — per-source gate for CPU line 11 (LiteX Timer)
 *     li   t0, (1 << 11)    # 0x800
 *     csrs mie, t0
 *
 *   mstatus bit 3  — global machine interrupt enable (master switch)
 *     li   t0, (1 << 3)     # 0x8
 *     csrs mstatus, t0
 *
 * Call timer_init BEFORE enable_interrupts so the peripheral is fully
 * configured before the first interrupt can fire.
 * =============================================================================*/
    .globl  enable_interrupts
    .type   enable_interrupts, @function
enable_interrupts:
    li      t0, (1 << 11)       /* CPU line 11 = LiteX Timer */
    csrs    mie, t0
    li      t0, (1 << 3)        /* MIE = global machine interrupt enable */
    csrs    mstatus, t0
    ret
    .size   enable_interrupts, . - enable_interrupts


/* =============================================================================
 * uart_put_uint — print unsigned 32-bit integer in decimal (provided)
 * =============================================================================*/
    .globl  uart_put_uint
    .type   uart_put_uint, @function
uart_put_uint:
    addi    sp, sp, -20
    sw      ra,  16(sp)
    sw      s0,  12(sp)
    sw      s1,   8(sp)
    bnez    a0, .Lnot_zero
    li      a0, '0'
    call    uart_putchar
    j       .Lput_done
.Lnot_zero:
    mv      s0, a0
    addi    s1, sp, 8
    li      t0, 10
.Ldigit_loop:
    beqz    s0, .Lprint_digits
    remu    t1, s0, t0
    addi    t1, t1, '0'
    addi    s1, s1, -1
    sb      t1, 0(s1)
    divu    s0, s0, t0
    j       .Ldigit_loop
.Lprint_digits:
    addi    t0, sp, 8
    bge     s1, t0, .Lput_done
    lb      a0, 0(s1)
    call    uart_putchar
    addi    s1, s1, 1
    j       .Lprint_digits
.Lput_done:
    lw      s1,   8(sp)
    lw      s0,  12(sp)
    lw      ra,  16(sp)
    addi    sp, sp, 20
    ret
    .size   uart_put_uint, . - uart_put_uint


/* =============================================================================
 * Read-Only Data
 * =============================================================================*/
    .section .rodata

str_banner:
    .string "=== CS281 Lab 4: Interrupt-Based Timers ===\r\n\r\n"
    .string "Main loop running -- printing a dot every ~500 ms\r\n"
    .string "Timer interrupt fires every 1 second\r\n\r\n"

str_running:
    .string ""          /* nothing extra -- dots start immediately */

str_dot:
    .string ". "

str_tick_pre:
    .string "\r\n[TICK "

str_tick_post:
    .string "]\r\n"
