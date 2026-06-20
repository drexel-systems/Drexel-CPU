/* =============================================================================
 * CS281 Lab 5 — GPIO Input Interrupts
 * File: lab5-gpio-input/main.S
 *
 * Objective
 *   Learn how external (non-timer) interrupts work by wiring button presses
 *   to LED toggles.  The main loop runs continuously printing dots; pressing
 *   BTN0 or BTN1 asynchronously toggles LED0 or LED1 without main ever
 *   checking the buttons.
 *
 * Expected UART output (make uart-connect)
 *
 *   === CS281 Lab 5: GPIO Input Interrupts ===
 *   Simulate button presses from the Renode monitor:
 *     btn0 PressAndRelease   (BTN0 -> toggles LED0)
 *     btn1 PressAndRelease   (BTN1 -> toggles LED1)
 *
 *   Main loop running...
 *   . . . .
 *   [BTN0] LED0 ON
 *   . . . .
 *   [BTN0] LED0 OFF
 *   . . . .
 *   [BTN1] LED1 ON
 *
 * How it works
 *   ┌──────────────────────────────────────────────────────────────────────┐
 *   │  main: . . . [BTN pressed] → ISR fires → toggle LED → mret → . . . │
 *   └──────────────────────────────────────────────────────────────────────┘
 *
 *   gpio_init()       — enables rising-edge IRQ for BTN0 and BTN1
 *   enable_interrupts() — opens CPU gates (mie bit 12, mstatus.MIE)
 *
 *   When a button is pressed (GPIO pin rises), the peripheral asserts
 *   cpu interrupt line 12.  The CPU saves mepc and jumps to machine_trap_handler.
 *   The ISR reads GPIO_IRQ_PENDING to identify which button fired, toggles the
 *   corresponding LED, prints a message, clears the pending bit, and returns
 *   with mret.  main resumes exactly where it was interrupted.
 *
 * GPIO Input register map  (GPIO_IN_BASE = 0xe0015400)
 *   0x00  GPIO_IN          read current pin state (bit N = pin N)
 *   0x04  GPIO_IRQ_MODE    per-pin: 0=Edge, 1=Change         (default 0)
 *   0x08  GPIO_IRQ_EDGE    per-pin: 0=Rising, 1=Falling      (default 0)
 *   0x0C  GPIO_IRQ_STATUS  read-only
 *   0x10  GPIO_IRQ_PENDING read = pending bits; write 1 to CLEAR
 *   0x14  GPIO_IRQ_ENABLE  write 1 to enable IRQ per pin
 *
 * mcause when GPIO fires:  0x8000000C  (interrupt bit | cpu line 12)
 *
 * Simulating buttons in Renode (from make monitor-connect):
 *   sysbus.gpio_in OnGPIO 0 True    # BTN0 press  → rising edge → ISR fires
 *   sysbus.gpio_in OnGPIO 0 False   # BTN0 release (no IRQ in rising-edge mode)
 *   sysbus.gpio_in OnGPIO 1 True    # BTN1 press  → ISR fires
 *   sysbus.gpio_in OnGPIO 1 False   # BTN1 release
 * =============================================================================*/

    .include "../hardware/lib/cs281.inc"

/* ── Busy-wait delay (main loop dots) ───────────────────────────────────── */
/* ~4M iterations × 2 instructions ≈ 8M cycles ≈ 0.08 s per dot (throttled) */
.equ DOT_DELAY, 4000000


/* ── Read-Only Data ───────────────────────────────────────────────────────── */
    .section .rodata

str_banner:
    .string "=== CS281 Lab 5: GPIO Input Interrupts ===\r\n"
str_hint:
    .ascii "Simulate button presses from the Renode monitor:\r\n"
    .ascii "  sysbus.gpio_in OnGPIO 0 True   (BTN0 -> toggles LED0)\r\n"
    .ascii "  sysbus.gpio_in OnGPIO 1 True   (BTN1 -> toggles LED1)\r\n\r\n"
    .string "Main loop running...\r\n"
str_dot:
    .string ". "
str_btn0_on:
    .string "\r\n[BTN0] LED0 ON\r\n"
str_btn0_off:
    .string "\r\n[BTN0] LED0 OFF\r\n"
str_btn1_on:
    .string "\r\n[BTN1] LED1 ON\r\n"
str_btn1_off:
    .string "\r\n[BTN1] LED1 OFF\r\n"


/* ── Mutable Data ─────────────────────────────────────────────────────────── */
    .section .bss
    .align 2
led_state:
    .space 4    /* current LED output bitmask (bit 0=LED0, bit 1=LED1) */
                /* updated by ISR, read by report_btn0/report_btn1     */


/* ═══════════════════════════════════════════════════════════════════════════
 * machine_trap_handler
 *
 * Handles ALL machine-mode traps.  Frame (save/restore all registers) is
 * provided.  Your job is the three-step body inside the mcause check.
 *
 * mcause = 0x8000000C  → GPIO interrupt (cpu line 12)
 * ═══════════════════════════════════════════════════════════════════════════*/
    .section .text
    .globl  machine_trap_handler
    .type   machine_trap_handler, @function
    .align  2
machine_trap_handler:
    /* ── Save every register the ISR might touch ─────────────────────────── */
    addi    sp, sp, -68
    sw      ra,  0(sp)
    sw      t0,  4(sp)
    sw      t1,  8(sp)
    sw      t2, 12(sp)
    sw      t3, 16(sp)
    sw      t4, 20(sp)
    sw      t5, 24(sp)
    sw      t6, 28(sp)
    sw      a0, 32(sp)
    sw      a1, 36(sp)
    sw      a2, 40(sp)
    sw      a3, 44(sp)
    sw      a4, 48(sp)
    sw      a5, 52(sp)
    sw      a6, 56(sp)
    sw      a7, 60(sp)
    sw      s0, 64(sp)

    /* ── Dispatch on mcause ──────────────────────────────────────────────── */
    csrr    t0, mcause
    li      t1, 0x8000000C          /* interrupt bit | cpu line 12 */
    bne     t0, t1, .Lisr_done

    /* ── Step A: read pending bits ─────────────────────────────────────────── */
    li      t0, GPIO_IN_BASE
    lw      t1, GPIO_IRQ_PENDING(t0)    /* t1 = pending bits (bit0=BTN0, bit1=BTN1) */

    /* ── Step B: BTN0 → toggle LED0 ────────────────────────────────────────── */
    andi    t2, t1, BTN0
    beqz    t2, .Lcheck_btn1

    la      t3, led_state
    lw      t4, 0(t3)
    xori    t4, t4, LED0
    sw      t4, 0(t3)
    call    report_btn0

    /* ── Step C: BTN1 → toggle LED1 ────────────────────────────────────────── */
.Lcheck_btn1:
    andi    t2, t1, BTN1
    beqz    t2, .Lleds_done

    la      t3, led_state
    lw      t4, 0(t3)
    xori    t4, t4, LED1
    sw      t4, 0(t3)
    call    report_btn1

    /* ── Step D: drive GPIO output (physical LEDs) ──────────────────────────── */
.Lleds_done:
    la      t3, led_state
    lw      t4, 0(t3)
    li      t0, GPIO_OUT_BASE
    sw      t4, 0(t0)

    /* ── Step E: clear pending bits (CRITICAL — omitting causes ISR to loop) ── */
    li      t0, GPIO_IN_BASE
    li      t1, (BTN0 | BTN1)
    sw      t1, GPIO_IRQ_PENDING(t0)

.Lisr_done:
    /* ── Restore all registers and return to interrupted code ────────────── */
    lw      ra,  0(sp)
    lw      t0,  4(sp)
    lw      t1,  8(sp)
    lw      t2, 12(sp)
    lw      t3, 16(sp)
    lw      t4, 20(sp)
    lw      t5, 24(sp)
    lw      t6, 28(sp)
    lw      a0, 32(sp)
    lw      a1, 36(sp)
    lw      a2, 40(sp)
    lw      a3, 44(sp)
    lw      a4, 48(sp)
    lw      a5, 52(sp)
    lw      a6, 56(sp)
    lw      a7, 60(sp)
    lw      s0, 64(sp)
    addi    sp, sp, 68
    mret                    /* restore mstatus.MIE from MPIE; jump to mepc */
    .size   machine_trap_handler, . - machine_trap_handler


/* ═══════════════════════════════════════════════════════════════════════════
 * gpio_init — enable rising-edge IRQ for BTN0 and BTN1
 *
 * The GPIO peripheral defaults to Edge + Rising mode (GPIO_IRQ_MODE=0,
 * GPIO_IRQ_EDGE=0).  You do not need to write those registers — just enable
 * the two pins you care about in GPIO_IRQ_ENABLE.
 *
 * TODO: implement this function.
 *
 *   li    t0, GPIO_IN_BASE
 *   li    t1, (BTN0 | BTN1)      # 0x03 — enable IRQ for pin 0 and pin 1
 *   sw    t1, GPIO_IRQ_ENABLE(t0)
 * ═══════════════════════════════════════════════════════════════════════════*/
    .globl  gpio_init
    .type   gpio_init, @function
gpio_init:
    li      t0, GPIO_IN_BASE
    li      t1, (BTN0 | BTN1)
    sw      t1, GPIO_IRQ_ENABLE(t0)
    ret
    .size   gpio_init, . - gpio_init


/* ═══════════════════════════════════════════════════════════════════════════
 * enable_interrupts — open the CPU interrupt gates for GPIO (cpu line 12)
 *
 * Same two-CSR pattern as Lab 4b — only the bit number changes:
 *   mie bit 12   — per-source enable for cpu line 12 (GPIO input)
 *   mstatus bit 3 — global machine interrupt enable (master switch)
 *
 * Both must be set.  Setting mie without mstatus does nothing; the CPU
 * ignores all interrupts until the global gate in mstatus is open.
 *
 * TODO: implement this function.
 *
 *   li    t0, (1 << 12)
 *   csrs  mie, t0
 *   li    t0, (1 << 3)
 *   csrs  mstatus, t0
 * ═══════════════════════════════════════════════════════════════════════════*/
    .globl  enable_interrupts
    .type   enable_interrupts, @function
enable_interrupts:
    li      t0, (1 << 12)
    csrs    mie, t0
    li      t0, (1 << 3)
    csrs    mstatus, t0
    ret
    .size   enable_interrupts, . - enable_interrupts


/* ═══════════════════════════════════════════════════════════════════════════
 * report_btn0 / report_btn1 — provided helpers, called from ISR TODO body
 *
 * Reads led_state and prints the appropriate ON/OFF message over UART.
 * Uses s0 (callee-saved) so uart_puts can't clobber it between calls.
 * ═══════════════════════════════════════════════════════════════════════════*/
    .globl  report_btn0
    .type   report_btn0, @function
report_btn0:
    addi    sp, sp, -8
    sw      ra,  4(sp)
    sw      s0,  0(sp)
    la      t0, led_state
    lw      t1, 0(t0)
    andi    t1, t1, LED0
    beqz    t1, .Lbtn0_off
    la      s0, str_btn0_on
    j       .Lbtn0_print
.Lbtn0_off:
    la      s0, str_btn0_off
.Lbtn0_print:
    mv      a0, s0
    call    uart_puts
    lw      s0,  0(sp)
    lw      ra,  4(sp)
    addi    sp, sp, 8
    ret
    .size   report_btn0, . - report_btn0

    .globl  report_btn1
    .type   report_btn1, @function
report_btn1:
    addi    sp, sp, -8
    sw      ra,  4(sp)
    sw      s0,  0(sp)
    la      t0, led_state
    lw      t1, 0(t0)
    andi    t1, t1, LED1
    beqz    t1, .Lbtn1_off
    la      s0, str_btn1_on
    j       .Lbtn1_print
.Lbtn1_off:
    la      s0, str_btn1_off
.Lbtn1_print:
    mv      a0, s0
    call    uart_puts
    lw      s0,  0(sp)
    lw      ra,  4(sp)
    addi    sp, sp, 8
    ret
    .size   report_btn1, . - report_btn1


/* ═══════════════════════════════════════════════════════════════════════════
 * main — provided
 *
 * Sets mtvec, initializes GPIO interrupt, enables CPU interrupts, then
 * loops forever printing dots.  The ISR fires asynchronously on button press.
 * ═══════════════════════════════════════════════════════════════════════════*/
    .globl  main
    .type   main, @function
main:
    /* Register the trap handler before enabling any interrupt source */
    la      t0, machine_trap_handler
    csrw    mtvec, t0

    la      a0, str_banner
    call    uart_puts
    la      a0, str_hint
    call    uart_puts

    call    gpio_init           /* enable rising-edge IRQ for BTN0/BTN1     */
    call    enable_interrupts   /* open mie bit 12 and mstatus.MIE           */

    /* ── Busy-work loop ─────────────────────────────────────────────────── */
    /* main has no knowledge of buttons.  The ISR fires transparently.       */
.Lmain_loop:
    li      t0, DOT_DELAY
.Lbusy:
    addi    t0, t0, -1
    bnez    t0, .Lbusy

    la      a0, str_dot
    call    uart_puts
    j       .Lmain_loop
    .size   main, . - main
