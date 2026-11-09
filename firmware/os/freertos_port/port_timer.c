#include <stdint.h>
#include "FreeRTOS.h"
#include "task.h"
#include "timer.h"
#include "uart_printf.h"

#if (configTICK_RATE_HZ == 0) || (TIMER_CLOCK_HZ % configTICK_RATE_HZ != 0)
#error "The timer frequency must be an exact multiple of the FreeRTOS tick rate"
#endif

#define TIMER_COUNTS_PER_TICK (TIMER_CLOCK_HZ / configTICK_RATE_HZ)
#define MACHINE_TIMER_INTERRUPT 0x80000007u
#define MIE_MTIE                0x80u

extern void freertos_risc_v_trap_handler(void);

static uint64_t next_tick_deadline;

// Called by the official port, with global interrupts still disabled.
void vPortSetupTimerInterrupt(void)
{
    uintptr_t trap_address = (uintptr_t)freertos_risc_v_trap_handler;

    // The startup trap remains in place until task contexts have been created.
    __asm__ volatile ("csrw mtvec, %0" : : "r"(trap_address) : "memory");
    next_tick_deadline = timer_read() + TIMER_COUNTS_PER_TICK;
    timer_set_compare(next_tick_deadline);

    // UART stays in polling mode. The first task enables global interrupts.
    __asm__ volatile ("csrw mie, %0" : : "r"(MIE_MTIE) : "memory");
}

// The official assembly handler saves task context and switches to the ISR
// stack before calling us. Its a0 argument contains mcause.
void freertos_risc_v_application_interrupt_handler(uintptr_t cause)
{
    configASSERT(cause == MACHINE_TIMER_INTERRUPT);

    // Advance from the previous deadline to avoid accumulating ISR latency.
    // If interrupts were masked for several ticks, subsequent IRQs catch up.
    next_tick_deadline += TIMER_COUNTS_PER_TICK;
    timer_set_compare(next_tick_deadline);
    portYIELD_FROM_ISR(xTaskIncrementTick());
}

void freertos_risc_v_application_exception_handler(uintptr_t cause)
{
    uintptr_t pc;
    uintptr_t value;

    __asm__ volatile ("csrr %0, mepc" : "=r"(pc));
    __asm__ volatile ("csrr %0, mtval" : "=r"(value));
    uart_printf("Exception: cause=%08x pc=%08x value=%08x\r\n",
                (unsigned)cause, (unsigned)pc, (unsigned)value);
    for (;;) {
    }
}
