import importlib.util
from pathlib import Path
import unittest
import xml.etree.ElementTree as ET

spec = importlib.util.spec_from_file_location("motion_profile", Path(__file__).parents[2] / "scripts/profile-motion.py")
motion = importlib.util.module_from_spec(spec)
spec.loader.exec_module(motion)


class MotionProfileTests(unittest.TestCase):
    def test_references_process_filter_and_half_open_intervals(self):
        xml = ET.ElementTree(ET.fromstring('''<trace><row>
          <start id="1">1000000000</start><duration id="2">8333333</duration>
          <process id="3"><pid id="4">42</pid></process>
        </row><row><start>2000000000</start><duration ref="2"/><process ref="3"/></row>
        <row><start ref="1"/><duration>999000000</duration><process><pid>99</pid></process></row>
        <row><start>-1000000000</start><duration ref="2"/><process><pid ref="4"/></process></row>
        <row><start>99000000000</start><duration ref="2"/><process ref="3"/></row></trace>'''))
        phases = [{"name": "first", "start_epoch": 100, "end_epoch": 102},
                  {"name": "second", "start_epoch": 102, "end_epoch": 103}]
        result = motion.summarize(xml, 42, 100, 3, phases)
        self.assertEqual([r["hitches"] for r in result], [1, 1])
        self.assertAlmostEqual(result[0]["total_hitch_ms"], 8.333333)
        self.assertEqual(result[1]["over_25_ms"], 0)

    def test_incomplete_or_inactive_capture_is_not_a_zero_hitch_success(self):
        empty = ET.ElementTree(ET.fromstring("<trace/>"))
        for phase in [{"start_epoch": 99, "end_epoch": 101},
                      {"start_epoch": 100, "end_epoch": 104},
                      {"start_epoch": 100, "end_epoch": 100},
                      {"start_epoch": 100, "end_epoch": 101, "window_active": False},
                      {"start_epoch": 100, "end_epoch": 101, "window_visible": False}]:
            with self.subTest(phase=phase), self.assertRaises(RuntimeError):
                motion.summarize(empty, 42, 100, 3, [{"name": "invalid", **phase}])


if __name__ == "__main__":
    unittest.main()
