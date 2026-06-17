/* =============================================================================
 * CS281 Lab 1 — LED Blinky
 * File: lab1-blinky/main.S
 *
 * Objective
 *   Blink LED0 on the CS281 board and report status over UART.
 *   Demonstrates: GPIO output writes, UART output, software delay loop.
 *
 * Expected UART output (telnet localhost 3456 / make uart-connect)
 *   === CS281 Lab 1: Blinky ===
 *   LED0 ON
 *   LED0 OFF
 *   LED0 ON
 *   ...
 *
 * Watch in Renode
 *   After running, open the Renode monitor and type:
 *     sysbus.gpio_led0 State     → shows LED0 state (True/False)
 *     sysbus.gpio_out  State     → shows all LED bits
 *
 * Extensions to try
 *   - Chase LEDs (LED0→1→2→3→0…) instead of plain on/off
 *   - Display count on the 7-segment display
 *   - Read BTN0 to pause/resume blinking
 *   - Use the hardware timer instead of a software delay loop
 * =============================================================================*/

    .include "../hardware/lib/cs281.inc"

/* ── Constants ────────────────────────────────────────────────────────────── */

/* Busy-wait loop count for ~0.5 s blink half-period.
 * Renode simulation speed varies by host, so this value controls the
 * VISUAL blink rate rather than exact wall-clock time.
 * Each loop iteration is 2 instructions (addi + bnez).
 * Tune: too fast → increase; too slow → decrease. */
.equ BLINK_DELAY, 20000000

/* ── Read-Only Data ───────────────────────────────────────────────────────── */
    .section .rodata
str_hello:  .string "=== CS281 Lab 1: Blinky ===\r\n"
str_on:     .string "LED0 ON\r\n"
str_off:    .string "LED0 OFF\r\n"

/* ── Code ─────────────────────────────────────────────────────────────────── */
    .section .text
    .globl  main
    .type   main, @function

main:
    /* ── Print startup banner ─────────────────────────────────────────────── */
    la      a0, str_hello
    call    uart_puts

    /* ── Blink loop ───────────────────────────────────────────────────────── */
blink_loop:

    /* Turn LED0 ON  (write 1 to bit 0 of GPIO_OUT) */
    la      a0, str_on
    call    uart_puts
    li      t0, GPIO_OUT_BASE
    li      t1, LED0
    sw      t1, 0(t0)

    /* Delay */
    li      a0, BLINK_DELAY
    call    delay

    /* Turn LED0 OFF (write 0 — all LEDs off) */
    la      a0, str_off
    call    uart_puts
    li      t0, GPIO_OUT_BASE
    sw      zero, 0(t0)

    /* Delay */
    li      a0, BLINK_DELAY
    call    delay

    j       blink_loop

    .size   main, . - main


/* ── delay ────────────────────────────────────────────────────────────────────
 * void delay(uint32_t count)   —  count in a0
 *
 * Busy-wait countdown.  Each iteration is 2 instructions (addi + bnez),
 * so the actual time depends on Renode simulation speed.  Use BLINK_DELAY
 * to tune the blink rate for a comfortable visual result.
 *
 * Note: MMIO polling (e.g. reading CLINT MTIME in a tight loop) is
 * expensive in Renode — each peripheral register read goes through the
 * device model.  A pure register countdown like this is much faster.
 *
 * Clobbers: a0
 * ─────────────────────────────────────────────────────────────────────────── */
    .globl  delay
    .type   delay, @function
delay:
.Ldelay_loop:
    addi    a0, a0, -1
    bnez    a0, .Ldelay_loop
    ret
    .size   delay, . - delay
