#!/usr/bin/env python3
"""Upload an RV32IM application linked at 0x10000 to the native UART bootloader."""

import argparse
from dataclasses import dataclass
from pathlib import Path
import struct
import sys
import time
import zlib

MAGIC = b"RVBL"
DEBUG_PREFIX = b"[boot] "
VERSION = 1
BLOCK_SIZE = 128
APP_BASE = 0x10000
APP_MAX_SIZE = 0x2F000  # 192 KiB application RAM minus 4 KiB stack.
INFO, BEGIN, DATA, RUN, ABORT, ERROR = 1, 2, 3, 4, 5, 0x7F
OK, READY = 0, 1
RETRYABLE = {2, 4, 5, 6}  # CRC, sequence, timeout, UART receive error.
STATUS_NAMES = {
    0: "OK", 1: "READY", 2: "packet CRC error", 3: "image/packet out of range",
    4: "unexpected sequence", 5: "receive timeout", 6: "UART receive error",
    7: "invalid state", 8: "unsupported version", 9: "invalid packet format",
    10: "BRAM image CRC mismatch", 11: "unknown command",
}


class ProtocolError(Exception):
    pass


@dataclass(frozen=True)
class Reply:
    command: int
    sequence: int
    status: int
    detail: int


def encode_packet(command, sequence=0, payload=b""):
    if not 0 <= len(payload) <= BLOCK_SIZE:
        raise ValueError("Packet payload exceeds 128 bytes")
    body = struct.pack("<BBHH", VERSION, command, sequence, len(payload)) + payload
    return MAGIC + body + struct.pack("<I", zlib.crc32(body))


def read_exact(port, length, deadline):
    result = bytearray()
    while len(result) != length:
        if time.monotonic() >= deadline:
            raise TimeoutError("Timed out waiting for bootloader response")
        result.extend(port.read(length - len(result)))
    return bytes(result)


def read_reply(port, timeout, debug=None):
    deadline = time.monotonic() + timeout
    window = bytearray()
    text = bytearray()

    def emit_text(byte):
        if debug is not None:
            text.append(byte)
            if byte == ord("\n") or len(text) == 256:
                debug(text.decode("utf-8", errors="replace"))
                text.clear()

    while bytes(window) != MAGIC:
        window.extend(read_exact(port, 1, deadline))
        # Retain a possible packet/log prefix; other bytes are ordinary text.
        while window and not (MAGIC.startswith(window) or DEBUG_PREFIX.startswith(window)):
            emit_text(window.pop(0))
        if bytes(window) == DEBUG_PREFIX:
            for byte in window:
                emit_text(byte)
            window.clear()
            # A marked debug line may itself contain the packet magic as text.
            while True:
                byte = read_exact(port, 1, deadline)[0]
                emit_text(byte)
                if byte == ord("\n"):
                    break
    if text and debug is not None:
        debug(text.decode("utf-8", errors="replace"))
    header = read_exact(port, 6, deadline)
    version, command, sequence, length = struct.unpack("<BBHH", header)
    if version != VERSION or not command & 0x80 or length != 5:
        raise ProtocolError("Invalid response header")
    payload = read_exact(port, length, deadline)
    checksum, = struct.unpack("<I", read_exact(port, 4, deadline))
    if zlib.crc32(header + payload) != checksum:
        raise ProtocolError("Response CRC mismatch")
    status, detail = struct.unpack("<BI", payload)
    return Reply(command, sequence, status, detail)


def exchange(port, command, sequence=0, payload=b"", *, timeout=10.0, retries=3, debug=None):
    packet = encode_packet(command, sequence, payload)
    last_error = None
    for attempt in range(retries + 1):
        if attempt:
            # Let the target finish its inter-byte timeout and framing recovery.
            # Discard a late reply before resending this same command/sequence.
            time.sleep(1.1)
            port.reset_input_buffer()
        try:
            written = port.write(packet)
            if written != len(packet):
                raise ProtocolError("Incomplete serial write")
            port.flush()
            deadline = time.monotonic() + timeout
            while True:
                reply = read_reply(port, max(0.0, deadline - time.monotonic()), debug)
                if reply.command == (ERROR | 0x80):
                    break
                if reply.command == (command | 0x80) and reply.sequence == sequence:
                    break
                # Ignore an old ACK, but never extend the original deadline.
            if reply.status in (OK, READY):
                if reply.command != (command | 0x80):
                    raise ProtocolError("Unexpected generic success response")
                return reply
            message = STATUS_NAMES.get(reply.status, f"status {reply.status}")
            if reply.status not in RETRYABLE:
                raise ValueError(f"Bootloader rejected command: {message} (detail={reply.detail:#x})")
            last_error = ProtocolError(message)
        except (TimeoutError, ProtocolError) as error:
            last_error = error
    raise ProtocolError(f"Command {command:#x}, sequence {sequence} failed: {last_error}")


def run_application(port, sequence=0, *, timeout=10.0, debug=None):
    # RUN changes ownership of the UART. Do not retry it after execution.
    reply = exchange(port, RUN, sequence, timeout=timeout, retries=0, debug=debug)
    if reply.status != OK or reply.detail != APP_BASE:
        raise ProtocolError("Unexpected RUN acknowledgement")


def upload(port, image, *, timeout=10.0, retries=3, run=True, progress=None, debug=None):
    if not 4 <= len(image) <= APP_MAX_SIZE:
        raise ValueError(f"Image size must be 4..{APP_MAX_SIZE} bytes")
    options = {"timeout": timeout, "retries": retries, "debug": debug}
    info = exchange(port, INFO, **options)
    if info.detail != APP_MAX_SIZE:
        raise ProtocolError("Target memory layout differs from this uploader")
    checksum = zlib.crc32(image)
    reply = exchange(port, BEGIN, payload=struct.pack("<II", len(image), checksum), **options)
    if reply.status != OK or reply.detail != 0:
        raise ProtocolError("Unexpected BEGIN acknowledgement")
    sequence = 0
    for offset in range(0, len(image), BLOCK_SIZE):
        block = image[offset:offset + BLOCK_SIZE]
        end = offset + len(block)
        reply = exchange(port, DATA, sequence, block, **options)
        expected_status = READY if end == len(image) else OK
        if reply.status != expected_status or reply.detail != end:
            raise ProtocolError("Target acknowledgement has an incorrect image offset/state")
        if progress:
            progress(end, len(image))
        sequence += 1
    if run:
        run_application(port, sequence, timeout=timeout, debug=debug)
    return checksum


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("port", help="Serial port, e.g. /dev/ttyUSB1")
    parser.add_argument("image", nargs="?", type=Path,
                        help="Raw .bin linked at 0x10000; omit with --run-only")
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--timeout", type=float, default=10.0, help="Reply timeout in seconds")
    parser.add_argument("--retries", type=int, default=3)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--no-run", action="store_true", help="Download and verify without executing")
    mode.add_argument("--run-only", action="store_true", help="Run the already verified image without uploading")
    monitor = parser.add_mutually_exclusive_group()
    monitor.add_argument("--monitor", action="store_true", default=True,
                         help="Print application UART output until Ctrl-C (default)")
    monitor.add_argument("--no-monitor", action="store_false", dest="monitor",
                         help="Exit after RUN without monitoring UART output")
    args = parser.parse_args(argv)
    if args.timeout <= 0 or args.retries < 0:
        parser.error("timeout must be positive and retries must be nonnegative")
    if args.run_only:
        if args.image is not None:
            parser.error("--run-only does not take an image file")
    else:
        if args.image is None:
            parser.error("image file is required unless --run-only is specified")
        try:
            image = args.image.read_bytes()
        except OSError as error:
            parser.error(str(error))
        if not 4 <= len(image) <= APP_MAX_SIZE:
            parser.error(f"Image must contain 4..{APP_MAX_SIZE} bytes")
    try:
        import serial
    except ImportError:
        parser.exit(1, "Install pyserial first: python3 -m pip install pyserial\n")
    try:
        with serial.Serial(args.port, args.baud, timeout=0.1, write_timeout=5) as port:
            debug = lambda text: print(text, end="", flush=True)
            if args.run_only:
                run_application(port, timeout=args.timeout, debug=debug)
            else:
                checksum = upload(
                    port, image, timeout=args.timeout, retries=args.retries, run=not args.no_run,
                    debug=debug,
                )
                print(f"BRAM image verified: CRC32={checksum:08x}")
            print("Ready; application was not started." if args.no_run else "Application started.")
            if args.monitor and not args.no_run:
                sys.stdout.flush()
                while True:
                    chunk = port.read(256)
                    if chunk:
                        sys.stdout.buffer.write(chunk)
                        sys.stdout.buffer.flush()
    except (OSError, ValueError, ProtocolError, serial.SerialException) as error:
        parser.exit(1, f"Upload failed: {error}\n")
    except KeyboardInterrupt:
        print()


if __name__ == "__main__":
    main()
