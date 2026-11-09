#ifndef BSP_TIMER_H
#define BSP_TIMER_H

#include <stdint.h>
#include "platform.h"

// Free-running counter at TIMER_CLOCK_HZ. Low-word subtraction handles wrap.
uint32_t timer_read_low(void);
uint64_t timer_read(void);

// Set the machine timer interrupt deadline with safe RV32 register writes.
void timer_set_compare(uint64_t deadline);

#endif
