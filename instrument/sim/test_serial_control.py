"""Host-side validation must fail before any partial score is sent."""
import importlib.util
from pathlib import Path
import subprocess
import sys
import unittest

TOOL = Path(__file__).resolve().parents[1] / "tools" / "serial_control.py"
spec = importlib.util.spec_from_file_location("serial_control", TOOL)
tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool)


class SerialControlTests(unittest.TestCase):
    def test_eight_timbres(self):
        for tone in range(8):
            self.assertTrue(tool.valid_command(f"T{tone}"))
        for command in ("T8", "T9", "T10", "T01", "T-1"):
            self.assertFalse(tool.valid_command(command), command)

    def test_expression_profile_commands(self):
        for command in ("F0", "F1", "F2", "F3", "Y0", "Y1"):
            self.assertTrue(tool.valid_command(command), command)
        for command in ("F4", "F01", "F-1", "Y2", "Y01", "Y-1"):
            self.assertFalse(tool.valid_command(command), command)

    def test_pcb_thirteen_lamp_masks_and_cancel(self):
        for command in ("J0", "J1", "J256", "J4096", "J8191", "J8192"):
            self.assertTrue(tool.valid_command(command), command)
        for command in ("J", "J8193", "J-1", "JFFFF", "J00000"):
            self.assertFalse(tool.valid_command(command), command)

    def test_sustain_commands(self):
        for command in ("H0", "H1"):
            self.assertTrue(tool.valid_command(command))
        for command in ("H", "H2", "H01", "H-1"):
            self.assertFalse(tool.valid_command(command))

    def test_lamp_masks_and_cancel_are_bounded_decimal_commands(self):
        for command in ("L0", "L8", "L16", "L24", "L25", "L255", "L256"):
            self.assertTrue(tool.valid_command(command), command)
        for command in ("L", "L257", "L-1", "LFF", "L0000"):
            self.assertFalse(tool.valid_command(command), command)
        result = subprocess.run([sys.executable, str(TOOL), "--command", "L255", "--emit"],
                                text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "L255\n")

    def test_debug_commands_are_strict_and_can_be_emitted(self):
        for command in ("D0", "D1"):
            self.assertTrue(tool.valid_command(command))
        for command in ("D", "D2", "D01", "D-1", "P0", "P1", "P", "P2", "P01", "P-1"):
            self.assertFalse(tool.valid_command(command))
        result = subprocess.run([sys.executable, str(TOOL), "--command", "D1", "--emit"],
                                text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "D1\n")

    def test_chords_and_sharps_have_physical_key_order(self):
        self.assertEqual(tool.score_commands(["K0+K2+K4", "S0", "K7+S4"]),
                         ["N", "A0015", "A0100", "A1080", "Z"])

    def test_reject_entire_invalid_score_before_transmission(self):
        for notes in ([], ["K8"], ["K0", "S5"], ["K0"] * 513, ["K0+K0"], ["K0+"]):
            with self.subTest(notes=notes):
                with self.assertRaises(ValueError):
                    tool.score_commands(notes)

    def test_absolute_score_rests_and_sharps(self):
        self.assertEqual(tool.score_commands(["C3:2","C#6:1","REST:4"]),
                         ["N","O3","U2","A0001","O6","U1","A0100","O4","U4","A0000","Z"])
        for notes in (["C2:2"],["C4+C6:2"],["C4:0"],["C4:2","K0"],["C4+C4:2"]):
            with self.assertRaises(ValueError):tool.score_commands(notes)
        self.assertEqual(len(tool.score_commands(["C4:2"]*512)),1538)

    def test_emit_works_without_serial_device(self):
        result = subprocess.run([sys.executable, str(TOOL), "--song", "chords", "--bpm", "90", "--emit"],
                                text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines(), ["B90", "N", "A0015", "A0029", "A0052", "A0015", "Z", "G1"])

    def test_negative_reply_aborts_before_commit(self):
        class Device:
            def __init__(self): self.sent = []
            def write(self, payload): self.sent.append(payload)
            def read(self, count): return b"E" if len(self.sent) == 3 else b"K"
            def flush(self): pass
        device = Device()
        with self.assertRaises(RuntimeError):
            tool.send_commands(device, ["N", "A0001", "A0002", "Z"])
        self.assertEqual(device.sent, [b"N\n", b"A0001\n", b"A0002\n"])

    def test_reconnect_invalidates_stale_line_before_ping(self):
        class Device:
            def __init__(self, first): self.sent = []; self.responses = iter([first, b"K"])
            def write(self, payload): self.sent.append(payload)
            def flush(self): pass
            def read(self, count): return next(self.responses)
        for reply in (b"E", b""):
            device = Device(reply)
            tool.synchronize(device)
            self.assertEqual(device.sent, [b"!\n", b"?\n"])


if __name__ == "__main__":
    unittest.main()
