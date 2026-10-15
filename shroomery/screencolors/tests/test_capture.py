import subprocess
import unittest
from types import SimpleNamespace

import numpy as np

from screencolors import capture


def ppm(w, h, value=7):
    return b"P6\n%d %d\n255\n" % (w, h) + bytes([value]) * (w * h * 3)


class CaptureTest(unittest.TestCase):
    def test_parse_ppm(self):
        img = capture.parse_ppm(ppm(4, 2))
        self.assertEqual(img.shape, (2, 4, 3))
        self.assertEqual(int(img[1, 3, 2]), 7)

    def test_parse_ppm_rejects_bad_data(self):
        self.assertIsNone(capture.parse_ppm(b"P3\n1 1\n255\n000"))
        self.assertIsNone(capture.parse_ppm(ppm(4, 2)[:-1]))
        self.assertIsNone(capture.parse_ppm(b"P6\n1 1\n65535\n" + b"\0" * 6))

    def test_downsample_long_side(self):
        img = np.zeros((1000, 2000, 3), dtype=np.uint8)
        self.assertLessEqual(max(capture.downsample(img).shape[:2]), 256)
        small = np.zeros((10, 20, 3), dtype=np.uint8)
        self.assertEqual(capture.downsample(small).shape, small.shape)

    def test_capture_window_runs_grim_on_the_toplevel(self):
        seen = {}

        def run(cmd, **kwargs):
            seen["cmd"] = cmd
            return SimpleNamespace(returncode=0, stdout=ppm(8, 8))

        img = capture.capture_window("1800001b", run=run)
        self.assertEqual(img.shape, (8, 8, 3))
        self.assertEqual(seen["cmd"][:3], ["grim", "-T", "1800001b"])
        self.assertIn("ppm", seen["cmd"])

    def test_failures_return_none(self):
        def failing(cmd, **kwargs):
            return SimpleNamespace(returncode=1, stdout=b"")

        def timing_out(cmd, **kwargs):
            raise subprocess.TimeoutExpired(cmd, 2)

        def missing(cmd, **kwargs):
            raise FileNotFoundError(cmd[0])

        for run in (failing, timing_out, missing):
            self.assertIsNone(capture.capture_window("x", run=run))
            self.assertIsNone(capture.load_image("/nope.png", run=run))


if __name__ == "__main__":
    unittest.main()


def png_rgba(w, h, rgba, filter_byte=0):
    import struct
    import zlib
    ctype = 6 if len(rgba) == 4 else 2
    rows = b"".join(bytes([filter_byte]) + bytes(rgba) * w for _ in range(h))
    def chunk(t, body):
        return struct.pack(">I", len(body)) + t + body + struct.pack(">I", zlib.crc32(t + body))
    ihdr = struct.pack(">IIBBBBB", w, h, 8, ctype, 0, 0, 0)
    data = zlib.compress(rows, 0)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr)
            + chunk(b"IDAT", data[:7]) + chunk(b"IDAT", data[7:]) + chunk(b"IEND", b""))


class PngTest(unittest.TestCase):
    def test_parse_png_rgba(self):
        img = capture.parse_png_rgba(png_rgba(3, 2, (10, 20, 30, 128)))
        self.assertEqual(img.shape, (2, 3, 4))
        self.assertEqual(tuple(int(v) for v in img[1, 2]), (10, 20, 30, 128))

    def test_parse_png_rgb_for_opaque_windows(self):
        img = capture.parse_png_rgba(png_rgba(3, 2, (10, 20, 30)))
        self.assertEqual(img.shape, (2, 3, 3))
        self.assertEqual(tuple(int(v) for v in img[0, 0]), (10, 20, 30))

    def test_parse_png_rejects_what_it_cannot_read(self):
        self.assertIsNone(capture.parse_png_rgba(b"not a png"))
        self.assertIsNone(capture.parse_png_rgba(png_rgba(3, 2, (1, 2, 3, 4), filter_byte=1)))

    def test_capture_window_rgba_runs_uncompressed_png(self):
        seen = {}

        def run(cmd, **kwargs):
            seen["cmd"] = cmd
            return SimpleNamespace(returncode=0, stdout=png_rgba(4, 4, (1, 2, 3, 255)))

        img = capture.capture_window_rgba("1800001b", run=run)
        self.assertEqual(img.shape, (4, 4, 4))
        self.assertEqual(seen["cmd"][:3], ["grim", "-T", "1800001b"])
        self.assertIn("-l", seen["cmd"])
        self.assertIn("png", seen["cmd"])
