import json
import unittest

from screencolors import protocol


class ProtocolTest(unittest.TestCase):
    def test_frame_shape(self):
        regions = {"viz": {"colors": ["#000000", "#ffffff"], "average": "#808080"}}
        f = protocol.frame("DP-2", "screen", 2, regions, 1760389012345.9)
        self.assertEqual((f["v"], f["type"], f["t"], f["monitor"], f["source"], f["windows"]),
                         (2, "frame", 1760389012345, "DP-2", "screen", 2))
        self.assertEqual(f["regions"], regions)

    def test_error(self):
        self.assertEqual(protocol.error("bad region"), {"v": 2, "type": "error", "message": "bad region"})

    def test_encode_is_one_line(self):
        data = protocol.encode({"a": 1, "b": [1, 2]})
        self.assertTrue(data.endswith(b"\n"))
        self.assertEqual(data.count(b"\n"), 1)
        self.assertEqual(json.loads(data), {"a": 1, "b": [1, 2]})

    def test_parse_line(self):
        self.assertEqual(protocol.parse_line('{"type":"subscribe"}'), {"type": "subscribe"})
        for line in ("", "not json", "[1,2]", "3"):
            self.assertIsNone(protocol.parse_line(line), line)


if __name__ == "__main__":
    unittest.main()
