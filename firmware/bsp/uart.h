#ifndef BSP_UART_H
#define BSP_UART_H

#include <stdbool.h>
#include <stdint.h>

enum uart_rx_result {
    UART_RX_EMPTY,
    UART_RX_OK,
    UART_RX_ERROR
};

// Reset TX/RX and leave UART interrupts disabled.
void uart_init(void);
void uart_putc(uint8_t byte);
void uart_puts(const char *text);
void uart_wait_tx_idle(void);

// Nonblocking receive. Error takes priority over data; a damaged byte is dropped.
// Reading status acknowledges sticky errors, so inspect a single status snapshot.
enum uart_rx_result uart_try_getc(uint8_t *byte);

// Acknowledge status and discard one buffered byte, if present.
bool uart_discard_rx_byte(void);
void uart_clear_status(void);
void uart_disable_interrupts(void);

#endif
