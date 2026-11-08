#include <stdint.h>
#include "protocol.h"
#include "uart.h"
#include "uart_printf.h"

#define MTIME_LOW     (*(volatile uint32_t *)0x10001000u)
#define MTIMECMP_LOW  (*(volatile uint32_t *)0x10001008u)
#define MTIMECMP_HIGH (*(volatile uint32_t *)0x1000100Cu)
#define RX_TIMEOUT_TICKS 10000u // 1 second at the timer's 10 kHz rate.
#define QUIET_TICKS      20u   // 2 ms without a byte restores packet framing.

static const uint8_t magic[4] = {'R', 'V', 'B', 'L'};

struct packet {
	uint8_t command;
	uint16_t sequence;
	uint16_t length;
	uint8_t payload[BLOCK_SIZE];
	uint32_t checksum;
};

struct download {
	uint32_t size;
	uint32_t checksum;
	uint32_t received;
	uint16_t next_sequence;
	uint16_t last_length;
	uint32_t last_packet_crc;
	unsigned active;
	unsigned ready;
};

static struct download image;

// UART_STATUS clears sticky errors when read: inspect that same snapshot.
// Unsigned subtraction also handles the low timer word wrapping around.
static enum status receive_byte(uint8_t *byte)
{
	uint32_t start = MTIME_LOW;
	for (;;) {
		uint32_t status = UART_STATUS;
		if (status & UART_RX_ERRORS) {
			if (status & UART_RX_VALID) {
				(void)UART_RX;
			}
			return ERROR_UART;
		}
		if (status & UART_RX_VALID) {
			*byte = (uint8_t)UART_RX;
			return STATUS_OK;
		}
		if ((uint32_t)(MTIME_LOW - start) >= RX_TIMEOUT_TICKS) {
			return ERROR_TIMEOUT;
		}
	}
}

// After a damaged/partial packet, drain the sender's remaining bytes before NAK.
// The sender waits for a reply, so the next packet cannot overlap this drain.
static void discard_until_quiet(void)
{
	uint32_t start = MTIME_LOW;
	uint32_t last_byte = start;
	for (;;) {
		uint32_t status = UART_STATUS;
		uint32_t now = MTIME_LOW;
		if (status & UART_RX_VALID) {
			(void)UART_RX;
			last_byte = now;
		}
		if ((uint32_t)(now - last_byte) >= QUIET_TICKS ||
			(uint32_t)(now - start) >= RX_TIMEOUT_TICKS) {
			return;
		}
	}
}

// Returns 0 for an idle timeout, 1 for a packet, and -1 for a damaged packet.
static int receive_packet(struct packet *packet, enum status *error)
{
	uint8_t body[6 + BLOCK_SIZE];
	uint8_t trailer[4];
	unsigned matched = 0;

	while (matched != sizeof(magic)) {
		uint8_t byte;
		*error = receive_byte(&byte);
		if (*error != STATUS_OK) {
			return (*error == ERROR_TIMEOUT && matched == 0) ? 0 : -1;
		}
		if (byte == magic[matched]) {
			++matched;
		} else {
			matched = (byte == magic[0]) ? 1u : 0u;
		}
	}

	for (unsigned i = 0; i < 6; ++i) {
		*error = receive_byte(&body[i]);
		if (*error != STATUS_OK) {
			return -1;
		}
	}
	packet->command = body[1];
	packet->sequence = read_le16(&body[2]);
	packet->length = read_le16(&body[4]);
	if (packet->length > BLOCK_SIZE) {
		*error = ERROR_FORMAT;
		return -1;
	}
	for (unsigned i = 0; i < packet->length; ++i) {
		*error = receive_byte(&body[6 + i]);
		if (*error != STATUS_OK) {
			return -1;
		}
	}
	for (unsigned i = 0; i < sizeof(trailer); ++i) {
		*error = receive_byte(&trailer[i]);
		if (*error != STATUS_OK) {
			return -1;
		}
	}
	packet->checksum = read_le32(trailer);
	if (crc32(body, 6u + packet->length) != packet->checksum) {
		*error = ERROR_CRC;
		return -1;
	}
	if (body[0] != PROTOCOL_VERSION) {
		*error = ERROR_VERSION;
		return -1;
	}
	for (unsigned i = 0; i < packet->length; ++i) {
		packet->payload[i] = body[6 + i];
	}
	return 1;
}

// Replies use the same frame format. Payload = status byte + LE32 detail.
static void reply(uint8_t command, uint16_t sequence,
				  enum status status, uint32_t detail)
{
	// Log before the binary ACK. The host must wait for that ACK before sending
	// another packet, so polling RX never competes with debug printing.
	if (status >= ERROR_CRC) {
		uart_printf("[boot] Error cmd=%u seq=%u status=%u detail=%08x\r\n",
					(unsigned)command, (unsigned)sequence, (unsigned)status, (unsigned)detail);
	}
	uint8_t body[11] = {
		PROTOCOL_VERSION, (uint8_t)(command | 0x80u),
		(uint8_t)sequence, (uint8_t)(sequence >> 8), 5, 0,
		(uint8_t)status, 0, 0, 0, 0
	};
	write_le32(&body[7], detail);
	uint32_t checksum = crc32(body, sizeof(body));
	for (unsigned i = 0; i < sizeof(magic); ++i) {
		uart_putc(magic[i]);
	}
	for (unsigned i = 0; i < sizeof(body); ++i) {
		uart_putc(body[i]);
	}
	for (unsigned i = 0; i < 4; ++i) {
		uart_putc((uint8_t)(checksum >> (8 * i)));
	}
}

static void reset_download(void)
{
	image.size = 0;
	image.checksum = 0;
	image.received = 0;
	image.next_sequence = 0;
	image.last_length = 0;
	image.last_packet_crc = 0;
	image.active = 0;
	image.ready = 0;
}

static void begin_download(const struct packet *packet)
{
	// The packet CRC/version have already passed. Any BEGIN starts a new
	// attempt, so even invalid parameters cancel the previous image/transfer.
	reset_download();
	if (packet->length != 8 || packet->sequence != 0) {
		reply(CMD_BEGIN, packet->sequence, ERROR_FORMAT, 0);
		return;
	}
	uint32_t size = read_le32(packet->payload);
	if (size < 4 || size > APP_MAX_SIZE) {
		reply(CMD_BEGIN, 0, ERROR_RANGE, APP_MAX_SIZE);
		return;
	}
	image.size = size;
	image.checksum = read_le32(&packet->payload[4]);
	image.active = 1;
	uart_printf("[boot] BEGIN size=%u CRC32=%08x addr=%08x\r\n",
				(unsigned)image.size, (unsigned)image.checksum, APP_BASE);
	reply(CMD_BEGIN, 0, STATUS_OK, 0);
}

static void receive_data(const struct packet *packet)
{
	// A lost ACK can cause a byte-for-byte repeat of the previous packet.
	// A repeat of the final block must also retain the READY response.
	if (image.next_sequence != 0 &&
		packet->sequence == image.next_sequence - 1u &&
		packet->length == image.last_length &&
		packet->checksum == image.last_packet_crc &&
		(image.active || image.ready)) {
		uart_printf("[boot] Retry seq=%u offset=%u\r\n",
					(unsigned)packet->sequence, (unsigned)image.received);
		reply(CMD_DATA, packet->sequence,
			  image.ready ? STATUS_READY : STATUS_OK, image.received);
		return;
	}
	if (!image.active) {
		reply(CMD_DATA, packet->sequence, ERROR_STATE, image.received);
		return;
	}
	if (packet->sequence != image.next_sequence) {
		reply(CMD_DATA, packet->sequence, ERROR_SEQUENCE, image.next_sequence);
		return;
	}
	if (packet->length == 0 || packet->length > image.size - image.received) {
		reply(CMD_DATA, packet->sequence, ERROR_RANGE, image.size - image.received);
		return;
	}

	volatile uint8_t *destination = (volatile uint8_t *)(APP_BASE + image.received);
	for (unsigned i = 0; i < packet->length; ++i) {
		destination[i] = packet->payload[i];
	}
	image.received += packet->length;
	image.last_length = packet->length;
	image.last_packet_crc = packet->checksum;
	++image.next_sequence;
	if (image.next_sequence == 1 || image.received % 4096u == 0 ||
		image.received == image.size) {
		uart_printf("[boot] Received %u/%u bytes\r\n",
					(unsigned)image.received, (unsigned)image.size);
	}

	if (image.received == image.size) {
		image.active = 0;
		uart_printf("[boot] Verifying %u bytes\r\n", (unsigned)image.size);
		// Read back BRAM rather than trusting the receive buffer's checksum.
		uint32_t checksum = crc32((const volatile uint8_t *)APP_BASE, image.size);
		uart_printf("[boot] CRC32 BRAM=%08x expected=%08x %s\r\n",
					(unsigned)checksum, (unsigned)image.checksum,
					checksum == image.checksum ? "OK" : "FAIL");
		if (checksum != image.checksum) {
			reply(CMD_DATA, packet->sequence, ERROR_IMAGE_CRC, checksum);
			return;
		}
		image.ready = 1;
	}
	reply(CMD_DATA, packet->sequence,
		  image.ready ? STATUS_READY : STATUS_OK, image.received);
}

static __attribute__((noreturn)) void run_application(void)
{
	// Finish the RUN acknowledgement before application uart_init() resets TX.
	uart_wait_tx_idle();
	__asm__ volatile ("csrci mstatus, 8\n\tcsrw mie, zero" ::: "memory");
	UART_CONTROL = 0;
	MTIMECMP_LOW = 0xFFFFFFFFu;
	MTIMECMP_HIGH = 0xFFFFFFFFu;
	(void)UART_STATUS;

	// The application starts at _start, sets its own stack and clears its BSS.
	// This multi-cycle CPU has no instruction cache/prefetch or FENCE.I support.
	__asm__ volatile ("jr %0" :: "r" (APP_BASE) : "memory");
	__builtin_unreachable();
}

int main(void)
{
	uart_init();
	uart_puts("BOOT READY\r\n");

	for (;;) {
		struct packet packet;
		enum status error;
		int result = receive_packet(&packet, &error);
		if (result == 0) {
			continue;
		}
		if (result < 0) {
			discard_until_quiet();
			reply(CMD_ERROR, 0, error, 0);
			continue;
		}

		switch (packet.command) {
		case CMD_INFO:
			reply(CMD_INFO, packet.sequence,
				  packet.length == 0 ? STATUS_OK : ERROR_FORMAT, APP_MAX_SIZE);
			break;
		case CMD_BEGIN:
			begin_download(&packet);
			break;
		case CMD_DATA:
			receive_data(&packet);
			break;
		case CMD_RUN:
			if (packet.length != 0) {
				reply(CMD_RUN, packet.sequence, ERROR_FORMAT, 0);
			} else if (!image.ready) {
				reply(CMD_RUN, packet.sequence, ERROR_STATE, image.received);
			} else {
				uart_printf("[boot] RUN addr=%08x\r\n", APP_BASE);
				reply(CMD_RUN, packet.sequence, STATUS_OK, APP_BASE);
				run_application();
			}
			break;
		case CMD_ABORT:
			if (packet.length != 0) {
				reply(CMD_ABORT, packet.sequence, ERROR_FORMAT, 0);
				break;
			}
			reset_download();
			uart_printf("[boot] Download aborted\r\n");
			reply(CMD_ABORT, packet.sequence, STATUS_OK, 0);
			break;
		default:
			reply(packet.command, packet.sequence, ERROR_COMMAND, 0);
			break;
		}
	}
}
