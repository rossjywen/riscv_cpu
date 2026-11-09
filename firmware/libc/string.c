#include <string.h>

void *memcpy(void *destination, const void *source, size_t count)
{
    unsigned char *output = destination;
    const unsigned char *input = source;

    for (size_t index = 0; index < count; index++) {
        output[index] = input[index];
    }
    return destination;
}

void *memset(void *destination, int value, size_t count)
{
    unsigned char *output = destination;

    for (size_t index = 0; index < count; index++) {
        output[index] = (unsigned char)value;
    }
    return destination;
}

int memcmp(const void *left, const void *right, size_t count)
{
    const unsigned char *left_bytes = left;
    const unsigned char *right_bytes = right;

    for (size_t index = 0; index < count; index++) {
        if (left_bytes[index] != right_bytes[index]) {
            return (int)left_bytes[index] - (int)right_bytes[index];
        }
    }
    return 0;
}

size_t strlen(const char *text)
{
    size_t length = 0;

    while (text[length] != '\0') {
        length++;
    }
    return length;
}
