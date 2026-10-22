import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("latency", Path(__file__).resolve().parents[1]/"tools/measure_latency.py")
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


class LatencyTests(unittest.TestCase):
    def fixture(self, delay=.007):
        return [(i/100000, 3.3 if i>=300 else 0, .03 if i/100000>=.003+delay else 0) for i in range(3000)]

    def test_known_analog_delay_and_quantization(self):
        r=m.measure(self.fixture())
        self.assertAlmostEqual(r["max_ms"],7,places=5)
        self.assertTrue(r["observed_le_10ms"])
        self.assertFalse(r["observed_le_5ms"])

    def test_missed_onset_never_passes(self):
        r=m.measure([(t,g,0) for t,g,a in self.fixture()])
        self.assertEqual(r["missing_onsets"],1)
        self.assertFalse(r["observed_le_10ms"])

    def test_single_sample_glitch_is_rejected(self):
        rows=self.fixture();rows[400]=(rows[400][0],3.3,.2)
        self.assertAlmostEqual(m.measure(rows)["max_ms"],7,places=5)

    def test_bad_time_and_no_edge(self):
        with self.assertRaises(ValueError):m.measure(list(reversed(self.fixture())))
        with self.assertRaises(ValueError):m.measure([(t,0,a) for t,g,a in self.fixture()])


if __name__=="__main__":unittest.main()
