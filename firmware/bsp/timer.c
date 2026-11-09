#include "timer.h"

#define MTIME_LOW     (*(volatile uint32_t *)(TIMER_BASE_ADDRESS + 0x00u))
#define MTIME_HIGH    (*(volatile uint32_t *)(TIMER_BASE_ADDRESS + 0x04u))
#define MTIMECMP_LOW  (*(volatile uint32_t *)(TIMER_BASE_ADDRESS + 0x08u))
#define MTIMECMP_HIGH (*(volatile uint32_t *)(TIMER_BASE_ADDRESS + 0x0Cu))

uint32_t timer_read_low(void)
{
    return MTIME_LOW;
}

uint64_t timer_read(void)
{
    uint32_t high, low;
    do {
        high = MTIME_HIGH;
        low = MTIME_LOW;
    } while (high != MTIME_HIGH);
    return ((uint64_t)high << 32) | low;
}

void timer_set_compare(uint64_t deadline)
{
    // Avoid a temporary, smaller compare value between the two RV32 word writes.
    MTIMECMP_LOW = UINT32_MAX;
    MTIMECMP_HIGH = (uint32_t)(deadline >> 32);
    MTIMECMP_LOW = (uint32_t)deadline;
}
