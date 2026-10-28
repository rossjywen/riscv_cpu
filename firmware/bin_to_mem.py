#!/usr/bin/env python3
"""Convert a little-endian RV32 firmware binary to a Verilog $readmemh image.

Usage:
    python3 bin_to_mem.py build/firmware.bin program.mem

Each output line contains one 32-bit word, printed as eight hexadecimal digits.
The firmware is linked to RAM byte address 0 and the BRAM is word-addressed.
"""

import argparse
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("binary", type=Path, help="Input raw firmware binary")
    parser.add_argument("mem", type=Path, help="Output $readmemh text file")
    parser.add_argument(
        "--ram-size",
        type=int,
        default=256 * 1024,
        metavar="BYTES",
        help="RAM capacity in bytes (default: 262144 = 256 KiB)",
    )
    args = parser.parse_args()

    binary = args.binary.read_bytes()
    if len(binary) > args.ram_size:
        parser.error(
            f"firmware image is {len(binary)} bytes, "
            f"larger than RAM capacity {args.ram_size} bytes"
        )

    # A word-addressed, 32-bit BRAM consumes one 8-digit hex value per line.
    # The final incomplete word (if any) is padded with zero bytes.
    padding = (-len(binary)) % 4
    binary += b"\x00" * padding
    words = [
        f"{int.from_bytes(binary[offset:offset + 4], 'little'):08x}"
        for offset in range(0, len(binary), 4)
    ]

    args.mem.parent.mkdir(parents=True, exist_ok=True)
    args.mem.write_text("\n".join(words) + "\n", encoding="ascii")
    print(f"Generated {args.mem}: {len(words)} words ({len(binary)} bytes)")


if __name__ == "__main__":
    main()
