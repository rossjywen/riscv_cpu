#ifndef BSP_PLATFORM_H
#define BSP_PLATFORM_H

// These values describe the current RTL; writing them does not configure it.
#define CPU_CLOCK_HZ       80000000u
#define TIMER_CLOCK_HZ     10000u
#define UART_BAUD_RATE     115200u

#define UART_BASE_ADDRESS  0x10000000u
#define TIMER_BASE_ADDRESS 0x10001000u

#endif
