#include <stdint.h>
#include "uart.h"
#include "uart_printf.h"

static int print_padding(unsigned count, char byte)
{
    for (unsigned i = 0; i < count; ++i) {
        uart_putc((uint8_t)byte);
    }
    return (int)count;
}

static int print_string(const char *text, unsigned width)
{
    if (text == 0) {
        text = "(null)";
    }
    unsigned length = 0;
    while (text[length] != '\0') {
        ++length;
    }
    int count = 0;
    if (width > length) {
        count += print_padding(width - length, ' ');
    }
    for (unsigned i = 0; i < length; ++i) {
        uart_putc((uint8_t)text[i]);
    }
    return count + (int)length;
}

static int print_number(uintptr_t value, unsigned base, const char *alphabet,
                        const char *prefix, unsigned width, int zero_padding)
{
    // Three decimal digits per byte is enough for any uintptr_t value.
    char digits[sizeof(uintptr_t) * 3];
    unsigned length = 0;
    do {
        digits[length++] = alphabet[value % base];
        value /= base;
    } while (value != 0);

    unsigned prefix_length = 0;
    while (prefix[prefix_length] != '\0') {
        ++prefix_length;
    }
    unsigned padding = 0;
    if (width > length + prefix_length) {
        padding = width - length - prefix_length;
    }
    if (!zero_padding) {
        print_padding(padding, ' ');
    }
    for (unsigned i = 0; i < prefix_length; ++i) {
        uart_putc((uint8_t)prefix[i]);
    }
    if (zero_padding) {
        print_padding(padding, '0');
    }
    for (unsigned i = length; i != 0; --i) {
        uart_putc((uint8_t)digits[i - 1]);
    }
    return (int)(padding + prefix_length + length);
}

int uart_vprintf(const char *format, va_list arguments)
{
    int count = 0;
    while (*format != '\0') {
        if (*format != '%') {
            uart_putc((uint8_t)*format++);
            ++count;
            continue;
        }
        ++format;
        if (*format == '%') {
            uart_putc('%');
            ++format;
            ++count;
            continue;
        }

        int zero_padding = (*format == '0');
        if (zero_padding) {
            ++format;
        }
        unsigned width = 0;
        while (*format >= '0' && *format <= '9') {
            width = width * 10 + (unsigned)(*format++ - '0');
            if (width > 64) {
                return -1;
            }
        }

        const char *alphabet = "0123456789abcdef";
        switch (*format) {
        case 's':
            count += print_string(va_arg(arguments, const char *), width);
            break;
        case 'c':
            if (width > 1) {
                count += print_padding(width - 1, ' ');
            }
            uart_putc((uint8_t)va_arg(arguments, int));
            ++count;
            break;
        case 'd':
        case 'i': {
            int value = va_arg(arguments, int);
            unsigned magnitude = (unsigned)value;
            const char *prefix = "";
            if (value < 0) {
                // Unsigned subtraction also handles INT_MIN without overflow.
                magnitude = 0u - magnitude;
                prefix = "-";
            }
            count += print_number(magnitude, 10, alphabet, prefix, width, zero_padding);
            break;
        }
        case 'u':
            count += print_number(va_arg(arguments, unsigned), 10, alphabet,
                                  "", width, zero_padding);
            break;
        case 'X':
        case 'x':
            if (*format == 'X') {
                alphabet = "0123456789ABCDEF";
            }
            count += print_number(va_arg(arguments, unsigned), 16, alphabet,
                                  "", width, zero_padding);
            break;
        case 'p':
            count += print_number((uintptr_t)va_arg(arguments, void *), 16, alphabet,
                                  "0x", width, zero_padding);
            break;
        default:
            return -1;
        }
        ++format;
    }
    return count;
}

int uart_printf(const char *format, ...)
{
    va_list arguments;
    va_start(arguments, format);
    int count = uart_vprintf(format, arguments);
    va_end(arguments);
    return count;
}
