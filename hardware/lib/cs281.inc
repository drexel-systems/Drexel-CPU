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

/* ── Timer  (LiteX_Timer — CSR data width = 8 bits)  ───────────────────────── */
/* The LiteX_Timer peripheral uses 8-bit CSR sub-registers.  32-bit values
 * (LOAD, RELOAD) are written as four consecutive 8-bit words, MSB first:
 *   reg[0] = bits[31:24],  reg[1] = bits[23:16],  ... reg[3] = bits[7:0]
 * Single-bit registers (EN, EV_PENDING, EV_ENABLE) are one word each.       */
.equ TIMER_BASE,        0xe0002000
/* LOAD sub-registers — 4 bytes, MSB first */
.equ TIMER_LOAD0,       0x00    /* bits[31:24] of load value  */
.equ TIMER_LOAD1,       0x04    /* bits[23:16]                */
.equ TIMER_LOAD2,       0x08    /* bits[15:8]                 */
.equ TIMER_LOAD3,       0x0C    /* bits[7:0]  (LSB)           */
/* RELOAD sub-registers — 4 bytes, MSB first */
.equ TIMER_RELOAD0,     0x10    /* bits[31:24] of reload value */
.equ TIMER_RELOAD1,     0x14    /* bits[23:16]                 */
.equ TIMER_RELOAD2,     0x18    /* bits[15:8]                  */
.equ TIMER_RELOAD3,     0x1C    /* bits[7:0]  (LSB)            */
/* Control and event registers */
.equ TIMER_EN,          0x20    /* write 1 to start, 0 to stop           */
.equ TIMER_EV_PENDING,  0x3C    /* write 1 to CLEAR the interrupt        */
.equ TIMER_EV_ENABLE,   0x40    /* write 1 to route timer → cpu line 11  */
/* Pre-computed byte slices of TIMER_FREQ = 100,000,000 = 0x05F5E100 */
.equ TIMER_FREQ_B0,     0x05    /* bits[31:24] */
.equ TIMER_FREQ_B1,     0xF5    /* bits[23:16] */
.equ TIMER_FREQ_B2,     0xE1    /* bits[15:8]  */
.equ TIMER_FREQ_B3,     0x00    /* bits[7:0]   */

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

/* ── GPIO Input  (LiteX_GPIO In, IRQ enabled)  ──────────────────────────────── */
/* IRQ fires on rising edge (button press) by default.
 * Default IRQ_MODE=0 (Edge) and IRQ_EDGE=0 (Rising) require no explicit init —
 * only write to GPIO_IRQ_ENABLE to arm the pins you want.
 *
 * mcause when GPIO fires:  0x8000000C  (interrupt bit | cpu line 12)
 *
 * Register map (offsets from GPIO_IN_BASE):
 *   0x00  GPIO_IN          read current pin state (bit N = pin N)
 *   0x04  GPIO_IRQ_MODE    per-pin: 0=Edge, 1=Change
 *   0x08  GPIO_IRQ_EDGE    per-pin: 0=Rising, 1=Falling  (Edge mode only)
 *   0x0C  GPIO_IRQ_STATUS  read-only status
 *   0x10  GPIO_IRQ_PENDING read pending bits; write 1 to CLEAR
 *   0x14  GPIO_IRQ_ENABLE  write 1 to enable IRQ per pin             */
.equ GPIO_IN_BASE,      0xe0015400
.equ GPIO_IN,           0x00    /* read current pin state                */
.equ GPIO_IRQ_MODE,     0x04    /* 0=Edge, 1=Change per pin              */
.equ GPIO_IRQ_EDGE,     0x08    /* 0=Rising, 1=Falling per pin           */
.equ GPIO_IRQ_STATUS,   0x0C    /* read-only status                      */
.equ GPIO_IRQ_PENDING,  0x10    /* read: which pins pending; write 1=CLR */
.equ GPIO_IRQ_ENABLE,   0x14    /* write 1 to enable IRQ for that pin    */

.equ BTN0,              0x01
.equ BTN1,              0x02
.equ DIP_SW0,           0x04
.equ DIP_SW1,           0x08

/* ── CLINT  ──────────────────────────────────────────────────────────────────── */
.equ CLINT_BASE,        0xe0005000
.equ CLINT_MSIP,        0x0000  /* offset: software interrupt       */
.equ CLINT_MTIMECMP,    0x4000  /* offset: timer compare (low word) */
.equ CLINT_MTIME,       0xBFF8  /* offset: current time (low word)  */

/* Absolute addresses for CLINT registers whose offsets exceed the 12-bit
 * immediate field of lw/sw.  Use these with  li rN, ADDR / lw rD, 0(rN). */
.equ CLINT_MTIME_ADDR,    0xe0010FF8  /* CLINT_BASE + 0xBFF8 — MTIME low word    */
.equ CLINT_MTIMECMP_ADDR, 0xe0009000  /* CLINT_BASE + 0x4000 — MTIMECMP low word */

/* CLINT tick rate — matches frequency: in cs281_board.repl (100 MHz).
 * Use these to convert wall-clock time to tick counts for delay(). */
.equ CLINT_HZ,          100000000   /* ticks per second  */
.equ CLINT_MS,          100000      /* ticks per ms      */
