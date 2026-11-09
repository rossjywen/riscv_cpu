#include "platform.h"
#include "uart.h"

#define UART_RX      (*(volatile uint32_t *)(UART_BASE_ADDRESS + 0x00u))
#define UART_TX      (*(volatile uint32_t *)(UART_BASE_ADDRESS + 0x04u))
#define UART_STATUS  (*(volatile uint32_t *)(UART_BASE_ADDRESS + 0x08u))
#define UART_CONTROL (*(volatile uint32_t *)(UART_BASE_ADDRESS + 0x0Cu))

#define UART_RX_VALID  (1u << 0)
#define UART_TX_BUSY   (1u << 3)
#define UART_RX_ERRORS ((1u << 5) | (1u << 6))

void uart_init(void)
{
    UART_CONTROL = 3u;
}

void uart_putc(uint8_t byte)
{
    while (UART_STATUS & UART_TX_BUSY) {
    }
    UART_TX = byte;
}

void uart_puts(const char *text)
{
    while (*text != '\0') {
        uart_putc((uint8_t)*text++);
    }
}

void uart_wait_tx_idle(void)
{
    while (UART_STATUS & UART_TX_BUSY) {
    }
}

enum uart_rx_result uart_try_getc(uint8_t *byte)
{
    uint32_t status = UART_STATUS;
    if (status & UART_RX_ERRORS) {
        if (status & UART_RX_VALID) {
            (void)UART_RX;
        }
        return UART_RX_ERROR;
    }
    if (status & UART_RX_VALID) {
        *byte = (uint8_t)UART_RX;
        return UART_RX_OK;
    }
    return UART_RX_EMPTY;
}

bool uart_discard_rx_byte(void)
{
    uint32_t status = UART_STATUS;
    if (status & UART_RX_VALID) {
        (void)UART_RX;
        return true;
    }
    return false;
}

void uart_clear_status(void)
{
    (void)UART_STATUS;
}

void uart_disable_interrupts(void)
{
    UART_CONTROL = 0;
}
