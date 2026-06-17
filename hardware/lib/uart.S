/* =============================================================================
 * CS281 Virtual Development Board — UART Driver
 * File: hardware/lib/uart.S
 *
 * LiteX UART peripheral at base address 0xe0001800.
 *
 * Register Map (32-bit word-aligned CSRs)
 * ─────────────────────────────────────────────────────────────────────────────
 *   0xe0001800  +0x00  RXTX      Write = TX data byte, Read = RX data byte
 *   0xe0001804  +0x04  TXFULL    1 = TX FIFO is full  (do not write)
 *   0xe0001808  +0x08  RXEMPTY   1 = RX FIFO is empty (nothing to read)
 *   0xe000180C  +0x0C  EV_STATUS
 *   0xe0001810  +0x10  EV_PENDING
 *   0xe0001814  +0x14  EV_ENABLE
 *
 * Public API
 * ─────────────────────────────────────────────────────────────────────────────
 *   uart_putchar(a0: char)              — send one character (blocking)
 *   uart_puts   (a0: const char*)       — send null-terminated string
 *   uart_getchar(void) -> a0: char      — receive one character (blocking)
 *
 * Calling convention: standard RISC-V ILP32 ABI.
 *   Caller-saved: a0-a7, t0-t6
 *   Callee-saved: s0-s11, sp, ra (must be preserved by functions that use them)
 * =============================================================================*/

.section .text

/* ── UART_PUTCHAR ─────────────────────────────────────────────────────────────
 * void uart_putchar(char c)  —  c passed in a0
 *
 * Waits until the TX FIFO has space, then writes the character.
 * Clobbers: t0, t1  (caller-saved, no save needed)
 * ─────────────────────────────────────────────────────────────────────────── */
    .globl  uart_putchar
    .type   uart_putchar, @function
uart_putchar:
    li      t0, 0xe0001800          /* UART base address */
.Lputchar_wait:
    lw      t1, 4(t0)               /* read TXFULL */
    bnez    t1, .Lputchar_wait      /* spin while TX FIFO full */
    sw      a0, 0(t0)               /* write character to RXTX */
    ret
    .size   uart_putchar, . - uart_putchar


/* ── UART_PUTS ────────────────────────────────────────────────────────────────
 * void uart_puts(const char *s)  —  s passed in a0
 *
 * Sends characters until the null terminator '\0' is reached.
 * Uses the stack to preserve ra and s0 across the inner uart_putchar calls,
 * following proper RISC-V ABI callee-save conventions.
 * ─────────────────────────────────────────────────────────────────────────── */
    .globl  uart_puts
    .type   uart_puts, @function
uart_puts:
    addi    sp, sp, -8
    sw      ra, 4(sp)               /* save return address */
    sw      s0, 0(sp)               /* save callee-saved s0 */
    mv      s0, a0                  /* s0 = string pointer (survives inner call) */

.Lputs_loop:
    lb      a0, 0(s0)               /* load next byte */
    beqz    a0, .Lputs_done         /* null terminator → done */
    call    uart_putchar
    addi    s0, s0, 1               /* advance pointer */
    j       .Lputs_loop

.Lputs_done:
    lw      ra, 4(sp)
    lw      s0, 0(sp)
    addi    sp, sp, 8
    ret
    .size   uart_puts, . - uart_puts


/* ── UART_GETCHAR ─────────────────────────────────────────────────────────────
 * char uart_getchar(void)  —  return value in a0
 *
 * Blocks until a byte arrives in the RX FIFO, then returns it.
 * Clobbers: t0, t1
 * ─────────────────────────────────────────────────────────────────────────── */
    .globl  uart_getchar
    .type   uart_getchar, @function
uart_getchar:
    li      t0, 0xe0001800          /* UART base address */
.Lgetchar_wait:
    lw      t1, 8(t0)               /* read RXEMPTY */
    bnez    t1, .Lgetchar_wait      /* spin while RX FIFO empty */
    lw      a0, 0(t0)               /* read character from RXTX */
    ret
    .size   uart_getchar, . - uart_getchar
