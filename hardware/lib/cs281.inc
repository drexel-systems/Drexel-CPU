/* =============================================================================
 * CS281 Virtual Development Board — Register Map Include (Assembly)
 * File: hardware/lib/cs281.inc
 *
 * Usage in assembly source:
 *   .include "../hardware/lib/cs281.inc"
 *
 * All values are byte addresses of the first (32-bit) register in each block.
 * Use lw/sw with word offsets to access registers within a peripheral.
 * =============================================================================*/

/* ── UART  (LiteX)  ────────────────────────────────────────────────────────── */
.equ UART_BASE,         0xe0001800
.equ UART_RXTX,         0x00    /* offset: W=TX byte, R=RX byte  */
.equ UART_TXFULL,       0x04    /* offset: 1 = TX FIFO full      */
.equ UART_RXEMPTY,      0x08    /* offset: 1 = RX FIFO empty     */
.equ UART_EV_STATUS,    0x0C
.equ UART_EV_PENDING,   0x10
.equ UART_EV_ENABLE,    0x14

/* ── Timer  (LiteX)  ────────────────────────────────────────────────────────── */
.equ TIMER_BASE,        0xe0002000
.equ TIMER_LOAD,        0x00    /* offset: reload value          */
.equ TIMER_RELOAD,      0x04    /* offset: auto-reload           */
.equ TIMER_EN,          0x08    /* offset: 1=enable              */
.equ TIMER_UPDATE,      0x0C    /* offset: write 1 to latch      */
.equ TIMER_VALUE,       0x10    /* offset: current count         */
.equ TIMER_EV_STATUS,   0x14
.equ TIMER_EV_PENDING,  0x18
.equ TIMER_EV_ENABLE,   0x1C

/* ── Buzzer  (LiteX_GPIO Out)  ──────────────────────────────────────────────── */
.equ BUZZER_BASE,       0xe0004000  /* bit 0: 1=on, 0=off */

/* ── 7-Segment Display  (LiteX_GPIO Out)  ───────────────────────────────────── */
.equ SEG7_BASE,         0xe0004400  /* bits 0-7: segments a-g, dp */

.equ SEG_A,             0x01    /* top            */
.equ SEG_B,             0x02    /* top-right      */
.equ SEG_C,             0x04    /* bottom-right   */
.equ SEG_D,             0x08    /* bottom         */
.equ SEG_E,             0x10    /* bottom-left    */
.equ SEG_F,             0x20    /* top-left       */
.equ SEG_G,             0x40    /* middle         */
.equ SEG_DP,            0x80    /* decimal point  */

/* Common digit patterns (OR of segment bits) */
.equ SEG7_DIGIT_0,      0x3F    /* a+b+c+d+e+f       */
.equ SEG7_DIGIT_1,      0x06    /* b+c               */
.equ SEG7_DIGIT_2,      0x5B    /* a+b+d+e+g         */
.equ SEG7_DIGIT_3,      0x4F    /* a+b+c+d+g         */
.equ SEG7_DIGIT_4,      0x66    /* b+c+f+g           */
.equ SEG7_DIGIT_5,      0x6D    /* a+c+d+f+g         */
.equ SEG7_DIGIT_6,      0x7D    /* a+c+d+e+f+g       */
.equ SEG7_DIGIT_7,      0x07    /* a+b+c             */
.equ SEG7_DIGIT_8,      0x7F    /* a+b+c+d+e+f+g     */
.equ SEG7_DIGIT_9,      0x6F    /* a+b+c+d+f+g       */

/* ── GPIO Output  (LiteX_GPIO Out)  ─────────────────────────────────────────── */
.equ GPIO_OUT_BASE,     0xe0015000  /* bits 0-3: LED0-LED3  */

.equ LED0,              0x01
.equ LED1,              0x02
.equ LED2,              0x04
.equ LED3,              0x08

/* ── GPIO Input  (LiteX_GPIO In)  ───────────────────────────────────────────── */
.equ GPIO_IN_BASE,      0xe0015400  /* bits 0-3: buttons, DIP switches */

.equ BTN0,              0x01
.equ BTN1,              0x02
.equ DIP_SW0,           0x04
.equ DIP_SW1,           0x08

/* ── CLINT  ──────────────────────────────────────────────────────────────────── */
.equ CLINT_BASE,        0xe0005000
.equ CLINT_MSIP,        0x0000  /* offset: software interrupt       */
.equ CLINT_MTIMECMP,    0x4000  /* offset: timer compare (low word) */
.equ CLINT_MTIME,       0xBFF8  /* offset: current time (low word)  */

/* Absolute address of MTIME low word (CLINT_BASE + CLINT_MTIME).
 * Use this with li + lw 0(rN) — the offset 0xBFF8 is too large for
 * a 12-bit lw offset field, so we precompute the full address here. */
.equ CLINT_MTIME_ADDR,  0xe0010FF8

/* CLINT tick rate — matches frequency: in cs281_board.repl (100 MHz).
 * Use these to convert wall-clock time to tick counts for delay(). */
.equ CLINT_HZ,          100000000   /* ticks per second  */
.equ CLINT_MS,          100000      /* ticks per ms      */
