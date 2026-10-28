#include <stdint.h>

// -----------------------------------------------------------------------------
// Test variables: inspect these symbols and RAM contents in the Vivado waveform.
// -----------------------------------------------------------------------------
volatile uint32_t numbers[4] = {10, 20, 30, 40};  // .data: must be preloaded
volatile uint32_t result;                        // .bss: must start at zero
volatile uint32_t result_xor;                    // .bss
volatile uint32_t status;                        // .bss

// Prevent inlining, so the program also exercises a function call and stack.
__attribute__((noinline))
static uint32_t sum_array(const volatile uint32_t *array, uint32_t length)
{
    uint32_t sum = 0;

    for (uint32_t i = 0; i < length; ++i) {
        sum += array[i];
    }

    return sum;
}

int main(void)
{
    // Check that crt.s correctly cleared the .bss section.
    uint32_t bss_ok = (result == 0u && result_xor == 0u && status == 0u);

    result = sum_array(numbers, 4u);
    result_xor = result ^ 0x5a5a5a5au;

    // Observe the status word to determine whether the firmware passed.
    if (bss_ok && result == 100u && result_xor == 0x5a5a5a3eu) {
        status = 0x600d600du;    // PASS
    } else {
        status = 0xbad0bad0u;    // FAIL
    }

    // No ECALL/EBREAK, OS, UART, or exit() is required.
    while (1) {
    }
}
