#include <stdint.h>
#include "FreeRTOS.h"
#include "task.h"
#include "semphr.h"
#include "uart.h"
#include "uart_printf.h"

// These values let us observe .data loading and .bss initialization.
static volatile uint32_t initialized_value = 0x12345678u;
static volatile uint32_t zero_value;

struct task_settings {
    const char *name;
    uint32_t delay_ms;
};

static const struct task_settings task_a_settings = {"A", 500u};
static const struct task_settings task_b_settings = {"B", 1000u};
static SemaphoreHandle_t uart_mutex;

static void print_task(void *parameters)
{
    const struct task_settings *settings = parameters;
    unsigned count = 0;

    for (;;) {
        // Hold the mutex for the whole line, while leaving timer IRQs enabled.
        BaseType_t result = xSemaphoreTake(uart_mutex, portMAX_DELAY);
        configASSERT(result == pdTRUE);
        count++;
        uart_printf("[task %s] count=%u tick=%u\r\n",
                    settings->name, count, (unsigned)xTaskGetTickCount());
        xSemaphoreGive(uart_mutex);

        // Exercise the official ECALL yield path as well as timer wakeups.
        taskYIELD();
        vTaskDelay(pdMS_TO_TICKS(settings->delay_ms));
    }
}

int main(void)
{
    uart_init();
    uart_puts("Application started at 0x00010000\r\n");
    uart_printf("data=%08x bss=%08x\r\n",
                (unsigned)initialized_value, (unsigned)zero_value);

    uart_printf("FreeRTOS %s: tick=%u Hz, heap=%u bytes\r\n",
                tskKERNEL_VERSION_NUMBER, (unsigned)configTICK_RATE_HZ,
                (unsigned)configTOTAL_HEAP_SIZE);

    uart_mutex = xSemaphoreCreateMutex();
    configASSERT(uart_mutex != NULL);

    // Stack depths are in 32-bit words: each print task receives 2 KiB.
    BaseType_t result = xTaskCreate(print_task, "uart_a", 512u,
                                   (void *)&task_a_settings, 1u, NULL);
    configASSERT(result == pdPASS);
    result = xTaskCreate(print_task, "uart_b", 512u,
                         (void *)&task_b_settings, 1u, NULL);
    configASSERT(result == pdPASS);

    uart_puts("Starting scheduler: task A=500 ms, task B=1000 ms\r\n");
    uart_wait_tx_idle();
    vTaskStartScheduler();

    // The malloc hook normally reports an idle-task allocation failure first.
    configASSERT(0);
    for (;;) {
    }
}
