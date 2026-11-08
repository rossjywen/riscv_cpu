#ifndef NATIVE_UART_H
#define NATIVE_UART_H

#include <stdint.h>

#define UART_RX      (*(volatile uint32_t *)0x10000000u)
#define UART_TX      (*(volatile uint32_t *)0x10000004u)
#define UART_STATUS  (*(volatile uint32_t *)0x10000008u)
#define UART_CONTROL (*(volatile uint32_t *)0x1000000Cu)
#define UART_RX_VALID (1u << 0)
#define UART_TX_BUSY  (1u << 3)
#define UART_RX_ERRORS ((1u << 5) | (1u << 6))

static inline void uart_init(void)
{
    UART_CONTROL = 3u; // Reset TX/RX; keep interrupts disabled.
}

static inline void uart_putc(uint8_t byte)
{
    while (UART_STATUS & UART_TX_BUSY) {
    }
    UART_TX = byte;
}

static inline void uart_puts(const char *text)
{
    while (*text) {
        uart_putc((uint8_t)*text++);
    }
}

static inline void uart_wait_tx_idle(void)
{
    while (UART_STATUS & UART_TX_BUSY) {
    }
}

#endif
