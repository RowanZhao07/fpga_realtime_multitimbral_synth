"""Send ASCII controls/scores through a Bluetooth SPP COM port or 3.3V USB UART.

--emit needs only Python. Real COM access additionally needs pyserial.
BLE GATT devices do not necessarily expose a COM port; send the emitted lines
through their UART write characteristic with a BLE terminal instead.
"""
import argparse
from pathlib import Path
import re
import sys

SONGS = {
    "twinkle": "K0 K0 K4 K4 K5 K5 K4 K3 K3 K2 K2 K1 K1 K0".split(),
    "scale": "K0 S0 K1 S1 K2 K3 S2 K4 S3 K5 S4 K6 K7".split(),
    "chords": "K0+K2+K4 K0+K3+K5 K1+K4+K6 K0+K2+K4".split(),
}


def score_commands(notes):
    if not 1 <= len(notes) <= 64:
        raise ValueError("A score must contain 1..64 steps")
    commands = ["N"]
    for index, step in enumerate(notes, 1):
        mask = 0
        for note in step.upper().split("+"):
            if not re.fullmatch(r"K[0-7]|S[0-4]", note):
                raise ValueError(f"Step {index}: invalid key {note!r}; use K0..K7 or S0..S4")
            bit = int(note[1]) + (8 if note[0] == "S" else 0)
            if mask & (1 << bit):
                raise ValueError(f"Step {index}: repeated key {note}")
            mask |= 1 << bit
        commands.append(f"A{mask:04X}")
    return commands + ["Z"]


def valid_command(command):
    if command in ("?", "N", "Z", "R"):
        return True
    if re.fullmatch(r"[TDEGH][0-9]", command):
        return int(command[1:]) <= (3 if command[0] == "T" else 1)
    if re.fullmatch(r"V[0-9]{1,4}", command):
        return int(command[1:]) <= 4096
    if re.fullmatch(r"L[0-9]{1,3}", command):
        return int(command[1:]) <= 256
    if re.fullmatch(r"B[0-9]{1,3}", command):
        return 40 <= int(command[1:]) <= 240
    return bool(re.fullmatch(r"A[0-9A-Fa-f]{4}", command)) and 0 < int(command[1:], 16) <= 0x1FFF


def send_commands(device, commands):
    # Never retry A automatically: the board may have appended it before a lost
    # acknowledgement. Abort before Z so an incomplete upload stays inactive.
    for command in commands:
        device.write((command + "\n").encode("ascii"))
        device.flush()
        response = device.read(1)
        if response != b"K":
            detail = "rejected (E)" if response == b"E" else f"missing/invalid reply {response!r}"
            raise RuntimeError(f"{command}: {detail}; stopped without retry. Restart a score upload from N.")


def synchronize(device):
    # A bare LF could commit a stale pending Z. '!' makes every pending line
    # invalid, or is ignored if the FPGA is already discarding after timeout.
    device.write(b"!\n")
    device.flush()
    response = device.read(1)
    if response not in (b"E", b""):
        raise RuntimeError(f"Unexpected resync reply {response!r}; check the serial connection")
    send_commands(device, ["?"])


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", help="e.g. COM7; not the FPGA JTAG download port")
    parser.add_argument("--baud", type=int, default=9600)
    parser.add_argument("--command", action="append", default=[], help="e.g. T2, V2048, ?; repeatable")
    songs = parser.add_mutually_exclusive_group()
    songs.add_argument("--song", choices=SONGS)
    songs.add_argument("--score", type=Path, help="text: space/newline-separated keys; + for chords, # comments")
    parser.add_argument("--bpm", type=int)
    parser.add_argument("--emit", action="store_true", help="print lines for a phone UART terminal; no serial dependency")
    args = parser.parse_args(argv)
    try:
        commands = list(args.command)
        if args.bpm is not None:
            commands.append(f"B{args.bpm}")
        notes = None
        if args.song:
            notes = SONGS[args.song]
        elif args.score:
            notes = " ".join(line.split("#", 1)[0] for line in args.score.read_text(encoding="utf-8-sig").splitlines()).split()
        if notes is not None:
            commands += score_commands(notes) + ["G1"]
        if not commands:
            commands = ["?"]
        for command in commands:
            if not valid_command(command):
                raise ValueError(f"Invalid command: {command!r}")
        if args.emit:
            print("\n".join(commands))
            return 0
        if not args.port:
            raise ValueError("Use --port COMn for a real serial link, or --emit to print commands")
        try:
            import serial
        except ImportError:
            raise RuntimeError("COM sending requires: python -m pip install pyserial") from None
        with serial.Serial(args.port, args.baud, timeout=3, write_timeout=3) as device:
            device.reset_input_buffer()
            synchronize(device)
            send_commands(device, commands)
        print(f"Acknowledged {len(commands)} commands on {args.port}.")
        return 0
    except (ValueError, OSError, RuntimeError) as error:
        print(f"Error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
