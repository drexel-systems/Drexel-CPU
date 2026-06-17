/* =============================================================================
 * CS281 Virtual Development Board — Register Map Header (C)
 * File: hardware/lib/cs281.h
 *
 * Use this file in C programs.  For assembly, include cs281.inc instead.
 *
 * All peripheral registers are 32-bit memory-mapped CSRs (LiteX convention).
 * Use volatile pointers so the compiler never caches the read/write.
 * =============================================================================*/

#ifndef CS281_H
#define CS281_H

#include <stdint.h>

/* ── Helper macro ────────────────────────────────────────────────────────── */
#define _MMIO32(addr)   (*(volatile uint32_t *)(addr))

/* ── UART  (LiteX)  0xe0001800 ───────────────────────────────────────────── */
#define UART_BASE       0xe0001800UL
#define UART_RXTX       _MMIO32(UART_BASE + 0x00)   /* W=TX byte, R=RX byte  */
#define UART_TXFULL     _MMIO32(UART_BASE + 0x04)   /* 1 = TX FIFO full      */
#define UART_RXEMPTY    _MMIO32(UART_BASE + 0x08)   /* 1 = RX FIFO empty     */
#define UART_EV_STATUS  _MMIO32(UART_BASE + 0x0C)
#define UART_EV_PENDING _MMIO32(UART_BASE + 0x10)
#define UART_EV_ENABLE  _MMIO32(UART_BASE + 0x14)

/* ── Timer  (LiteX)  0xe0002000 ──────────────────────────────────────────── */
#define TIMER_BASE          0xe0002000UL
#define TIMER_LOAD          _MMIO32(TIMER_BASE + 0x00)  /* reload value      */
#define TIMER_RELOAD        _MMIO32(TIMER_BASE + 0x04)  /* auto-reload value */
#define TIMER_EN            _MMIO32(TIMER_BASE + 0x08)  /* 1=enable          */
#define TIMER_UPDATE_VALUE  _MMIO32(TIMER_BASE + 0x0C)  /* write 1 to latch  */
#define TIMER_VALUE         _MMIO32(TIMER_BASE + 0x10)  /* current count     */
#define TIMER_EV_STATUS     _MMIO32(TIMER_BASE + 0x14)
#define TIMER_EV_PENDING    _MMIO32(TIMER_BASE + 0x18)
#define TIMER_EV_ENABLE     _MMIO32(TIMER_BASE + 0x1C)

/* ── Buzzer  (LiteX_GPIO Out)  0xe0004000 ────────────────────────────────── */
#define BUZZER_BASE     0xe0004000UL
#define BUZZER          _MMIO32(BUZZER_BASE)    /* bit 0: 1=on, 0=off */

/* ── 7-Segment Display  (LiteX_GPIO Out)  0xe0004400 ─────────────────────── */
#define SEG7_BASE       0xe0004400UL
#define SEG7            _MMIO32(SEG7_BASE)      /* bits 0-7 = segments a-g,dp */

#define SEG_A   (1u << 0)   /* top            */
#define SEG_B   (1u << 1)   /* top-right      */
#define SEG_C   (1u << 2)   /* bottom-right   */
#define SEG_D   (1u << 3)   /* bottom         */
#define SEG_E   (1u << 4)   /* bottom-left    */
#define SEG_F   (1u << 5)   /* top-left       */
#define SEG_G   (1u << 6)   /* middle         */
#define SEG_DP  (1u << 7)   /* decimal point  */

/* Common digit patterns */
#define SEG7_0  (SEG_A|SEG_B|SEG_C|SEG_D|SEG_E|SEG_F)         /* 0x3F */
#define SEG7_1  (SEG_B|SEG_C)                                   /* 0x06 */
#define SEG7_2  (SEG_A|SEG_B|SEG_D|SEG_E|SEG_G)                /* 0x5B */
#define SEG7_3  (SEG_A|SEG_B|SEG_C|SEG_D|SEG_G)                /* 0x4F */
#define SEG7_4  (SEG_B|SEG_C|SEG_F|SEG_G)                      /* 0x66 */
#define SEG7_5  (SEG_A|SEG_C|SEG_D|SEG_F|SEG_G)                /* 0x6D */
#define SEG7_6  (SEG_A|SEG_C|SEG_D|SEG_E|SEG_F|SEG_G)          /* 0x7D */
#define SEG7_7  (SEG_A|SEG_B|SEG_C)                             /* 0x07 */
#define SEG7_8  (SEG_A|SEG_B|SEG_C|SEG_D|SEG_E|SEG_F|SEG_G)    /* 0x7F */
#define SEG7_9  (SEG_A|SEG_B|SEG_C|SEG_D|SEG_F|SEG_G)          /* 0x6F */

/* ── GPIO Output  (LiteX_GPIO Out)  0xe0015000 ───────────────────────────── */
#define GPIO_OUT_BASE   0xe0015000UL
#define GPIO_OUT        _MMIO32(GPIO_OUT_BASE)  /* bits 0-3: LED0-LED3 */

#define LED0    (1u << 0)
#define LED1    (1u << 1)
#define LED2    (1u << 2)
#define LED3    (1u << 3)

/* ── GPIO Input  (LiteX_GPIO In)  0xe0015400 ─────────────────────────────── */
#define GPIO_IN_BASE    0xe0015400UL
#define GPIO_IN         _MMIO32(GPIO_IN_BASE)   /* bits 0-3: BTN/DIP inputs */

#define BTN0    (1u << 0)
#define BTN1    (1u << 1)
#define DIP_SW0 (1u << 2)
#define DIP_SW1 (1u << 3)

/* ── CLINT  0xe0005000 ───────────────────────────────────────────────────── */
#define CLINT_BASE      0xe0005000UL
#define CLINT_MSIP      _MMIO32(CLINT_BASE + 0x0000)   /* software IRQ      */
#define CLINT_MTIMECMP  _MMIO32(CLINT_BASE + 0x4000)   /* timer compare low */
#define CLINT_MTIME     _MMIO32(CLINT_BASE + 0xBFF8)   /* current time low  */

/* ── UART helper functions (implemented in uart.S) ───────────────────────── */
#ifndef __ASSEMBLER__
void uart_putchar(char c);
void uart_puts(const char *s);
char uart_getchar(void);
#endif

#endif /* CS281_H */
