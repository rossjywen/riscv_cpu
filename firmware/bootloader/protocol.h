#ifndef BOOT_PROTOCOL_H
#define BOOT_PROTOCOL_H

#include <stdint.h>

#define APP_BASE        0x00010000u
#define APP_STACK_BASE  0x0003F000u
#define APP_MAX_SIZE    (APP_STACK_BASE - APP_BASE)
#define BLOCK_SIZE      128u
#define PROTOCOL_VERSION 1u

enum command {
    CMD_INFO = 1,
    CMD_BEGIN = 2,
    CMD_DATA = 3,
    CMD_RUN = 4,
    CMD_ABORT = 5,
    CMD_ERROR = 0x7F
};

enum status {
    STATUS_OK = 0,
    STATUS_READY = 1,
    ERROR_CRC = 2,
    ERROR_RANGE = 3,
    ERROR_SEQUENCE = 4,
    ERROR_TIMEOUT = 5,
    ERROR_UART = 6,
    ERROR_STATE = 7,
    ERROR_VERSION = 8,
    ERROR_FORMAT = 9,
    ERROR_IMAGE_CRC = 10,
    ERROR_COMMAND = 11
};

static inline uint16_t read_le16(const uint8_t *bytes)
{
    return (uint16_t)((uint16_t)bytes[0] | ((uint16_t)bytes[1] << 8));
}

static inline uint32_t read_le32(const uint8_t *bytes)
{
    return (uint32_t)bytes[0] | ((uint32_t)bytes[1] << 8) |
           ((uint32_t)bytes[2] << 16) | ((uint32_t)bytes[3] << 24);
}

static inline void write_le32(uint8_t *bytes, uint32_t value)
{
    for (unsigned i = 0; i < 4; ++i) {
        bytes[i] = (uint8_t)(value >> (8 * i));
    }
}

// CRC-32/ISO-HDLC, matching Python zlib.crc32().
// A 16-entry table keeps the implementation small and easy to inspect.
static inline uint32_t crc32_byte(uint32_t crc, uint8_t byte)
{
    static const uint32_t table[16] = {
        0x00000000u, 0x1DB71064u, 0x3B6E20C8u, 0x26D930ACu,
        0x76DC4190u, 0x6B6B51F4u, 0x4DB26158u, 0x5005713Cu,
        0xEDB88320u, 0xF00F9344u, 0xD6D6A3E8u, 0xCB61B38Cu,
        0x9B64C2B0u, 0x86D3D2D4u, 0xA00AE278u, 0xBDBDF21Cu
    };
    crc ^= byte;
    crc = (crc >> 4) ^ table[crc & 15u];
    return (crc >> 4) ^ table[crc & 15u];
}

static inline uint32_t crc32(const volatile uint8_t *bytes, uint32_t size)
{
    uint32_t crc = 0xFFFFFFFFu;
    for (uint32_t i = 0; i < size; ++i) {
        crc = crc32_byte(crc, bytes[i]);
    }
    return crc ^ 0xFFFFFFFFu;
}

#endif
