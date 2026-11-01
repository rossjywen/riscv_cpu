#include <stdint.h>


// AXI UART Lite Register Map

#define UART_BASE       0x10000000u

#define UART_RX         (*(volatile uint32_t *)(UART_BASE + 0x00u))
#define UART_TX         (*(volatile uint32_t *)(UART_BASE + 0x04u))
#define UART_STATUS     (*(volatile uint32_t *)(UART_BASE + 0x08u))
#define UART_CONTROL    (*(volatile uint32_t *)(UART_BASE + 0x0Cu))

#define UART_RX_VALID   (1u << 0)
#define UART_TX_FULL    (1u << 3)
#define UART_RESET_FIFO 0x03u


// UART Driver

static void uart_init(void)
{
	// Clear TX/RX FIFOs. Interrupts remain disabled.
	UART_CONTROL = UART_RESET_FIFO;
}

static char uart_getc(void)
{
	while (!(UART_STATUS & UART_RX_VALID)) {
	}

	return (char)(uint8_t)UART_RX;
}

static void uart_putc(char c)
{
	// Wait until TX FIFO has available space.
	while (UART_STATUS & UART_TX_FULL) {
	}

	// Send one character.
	UART_TX = (uint32_t)(uint8_t)c;
}

static void uart_puts(const char *str)
{
	while (*str) {
		uart_putc(*str++);
	}
}

// ------------------------------------------------------------------
// Main
// ------------------------------------------------------------------

int main(void)
{
	uint8_t i;

	uart_init();

	for (i = 0; i < 10; i++) {
		uart_puts("From Ross RISC-V\r\n");     
	}

	while (1) {
	}

	return 0;
}
