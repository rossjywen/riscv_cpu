#ifndef UART_PRINTF_H
#define UART_PRINTF_H

#include <stdarg.h>

// Small, blocking formatter: %s %c %d %i %u %x %X %p %%.
// Right-aligned width up to 64; zero padding for numbers, e.g. %08x.
// No precision, length modifiers or floating point. Unsupported formats return -1.
// Returns the number of bytes sent, with no implicit newline conversion.
int uart_vprintf(const char *format, va_list arguments);
int uart_printf(const char *format, ...)
    __attribute__((format(printf, 1, 2)));

#endif
