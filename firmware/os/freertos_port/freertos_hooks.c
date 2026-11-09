#include "FreeRTOS.h"
#include "task.h"
#include "uart_printf.h"

void vApplicationAssert(const char *file, int line)
{
    portDISABLE_INTERRUPTS();
    uart_printf("FreeRTOS assert: %s:%d\r\n", file, line);
    for (;;) {
    }
}

void vApplicationMallocFailedHook(void)
{
    portDISABLE_INTERRUPTS();
    uart_printf("FreeRTOS heap exhausted\r\n");
    for (;;) {
    }
}

void vApplicationStackOverflowHook(TaskHandle_t task, char *name)
{
    (void)task;
    portDISABLE_INTERRUPTS();
    uart_printf("FreeRTOS stack overflow: %s\r\n", name);
    for (;;) {
    }
}

void vApplicationTaskReturnHook(void)
{
    portDISABLE_INTERRUPTS();
    uart_printf("FreeRTOS task returned unexpectedly\r\n");
    for (;;) {
    }
}
