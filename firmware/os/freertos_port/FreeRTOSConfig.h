#ifndef FREERTOS_CONFIG_H
#define FREERTOS_CONFIG_H

#include "platform.h"

#define configCPU_CLOCK_HZ                       CPU_CLOCK_HZ
#define configTICK_RATE_HZ                       1000u
#define configTICK_TYPE_WIDTH_IN_BITS            TICK_TYPE_WIDTH_32_BITS
#define configUSE_PREEMPTION                     1
#define configUSE_TIME_SLICING                   1
#define configUSE_PORT_OPTIMISED_TASK_SELECTION  0
#define configMAX_PRIORITIES                     4
#define configMINIMAL_STACK_SIZE                 256u
#define configMAX_TASK_NAME_LEN                  16

// heap_4 owns this fixed buffer; task stacks and TCBs are allocated from it.
#define configSUPPORT_DYNAMIC_ALLOCATION         1
#define configSUPPORT_STATIC_ALLOCATION          0
#define configTOTAL_HEAP_SIZE                    (32u * 1024u)
#define configUSE_MUTEXES                        1
#define configUSE_RECURSIVE_MUTEXES              0
#define configUSE_COUNTING_SEMAPHORES            0
#define configUSE_TIMERS                         0
#define configUSE_TICKLESS_IDLE                  0
#define configUSE_IDLE_HOOK                      0
#define configUSE_TICK_HOOK                      0
#define configCHECK_FOR_STACK_OVERFLOW           2
#define configUSE_MALLOC_FAILED_HOOK             1
#define configENABLE_FPU                         0
#define configENABLE_VPU                         0

#define INCLUDE_vTaskDelay                       1
#define INCLUDE_vTaskSuspend                     1

// Select our timer hook instead of the upstream CPU-clock-based MTIME path.
// The actual MMIO addresses and 10 kHz clock remain defined in the BSP.
#define configMTIME_BASE_ADDRESS                 0
#define configMTIMECMP_BASE_ADDRESS              0

void vApplicationAssert(const char *file, int line);
void vApplicationTaskReturnHook(void);

#define configASSERT(condition)                 \
    do {                                        \
        if (!(condition)) {                     \
            vApplicationAssert(__FILE__, __LINE__); \
        }                                       \
    } while (0)

#define configTASK_RETURN_ADDRESS vApplicationTaskReturnHook

#endif
