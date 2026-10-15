import subprocess
import unittest
from types import SimpleNamespace

import numpy as np

from screencolors import compose

MON = {"id": 1, "name": "HDMI-A-1", "x": 2560, "y": 0, "width": 3840, "height": 2160, "scale": 1.5,
       "activeWorkspace": {"id": 2}, "specialWorkspace": {"id": 0, "name": ""}}


def win(sid, at, size, ws=2, floating=False, history=5, fullscreen=0, monitor=1):
    return {"stableId": sid, "at": at, "size": size, "workspace": {"id": ws}, "floating": floating,
            "focusHistoryID": history, "fullscreen": fullscreen, "monitor": monitor,
            "mapped": True, "hidden": False}


class LayoutTest(unittest.TestCase):
    def test_picture_size_is_logical_over_eight(self):
        self.assertEqual(compose.picture_size(MON), (320, 180))
        self.assertEqual(compose.picture_size({"width": 2560, "height": 1080, "scale": 1}), (320, 135))

    def test_paint_order_and_rects(self):
        clients = [win("float-new", [2700, 100], [400, 300], floating=True, history=1),
                   win("tiled", [2560, 0], [1280, 1440], history=3),
                   win("float-old", [2600, 100], [400, 300], floating=True, history=7),
                   win("other-monitor", [0, 0], [100, 100], monitor=0),
                   win("other-ws", [2560, 0], [100, 100], ws=5)]
        ws = compose.visible_windows(MON, clients)
        self.assertEqual([w["id"] for w in ws], ["tiled", "float-old", "float-new"])
        self.assertEqual(ws[0]["rect"], (0.0, 0.0, 160.0, 180.0))

    def test_fullscreen_alone(self):
        clients = [win("tiled", [2560, 0], [1280, 1440]), win("video", [2560, 0], [2560, 1440], fullscreen=2)]
        self.assertEqual([w["id"] for w in compose.visible_windows(MON, clients)], ["video"])

    def test_special_workspace_on_top(self):
        mon = dict(MON, specialWorkspace={"id": -98, "name": "special:scratchpad"})
        clients = [win("scratch", [2600, 50], [500, 500], ws=-98), win("tiled", [2560, 0], [1280, 1440])]
        self.assertEqual([w["id"] for w in compose.visible_windows(mon, clients)], ["tiled", "scratch"])


class ChooseTest(unittest.TestCase):
    def test_only_windows_under_a_box(self):
        ws = [{"id": "left", "rect": (0, 0, 100, 180)}, {"id": "right", "rect": (200, 0, 120, 180)}]
        self.assertEqual([w["id"] for w in compose.choose(ws, [(10, 10, 50, 50)])], ["left"])

    def test_topmost_six(self):
        ws = [{"id": str(i), "rect": (0, 0, 10, 10)} for i in range(8)]
        self.assertEqual([w["id"] for w in compose.choose(ws, [(0, 0, 5, 5)])], [str(i) for i in range(2, 8)])

    def test_region_boxes(self):
        ring = {"shape": "ring", "cx": 0.5, "cy": 0.5, "inner": 0.1, "outer": 0.2}
        self.assertEqual(compose.region_boxes(ring, 200, 100), [(80.0, 30.0, 120.0, 70.0)])
        edges = {"shape": "edges", "depth": 0.1}
        self.assertEqual(len(compose.region_boxes(edges, 200, 100)), 4)
        rects = {"shape": "rects", "rects": [(0.5, 0.5, 0.25, 0.5)]}
        self.assertEqual(compose.region_boxes(rects, 200, 100), [(100.0, 50.0, 150.0, 100.0)])


class PasteTest(unittest.TestCase):
    def test_paste_offset_and_clip(self):
        pic = np.zeros((10, 10, 3), np.uint8)
        compose.paste(pic, np.full((4, 4, 3), 200, np.uint8), (8, 8, 4, 4))
        self.assertTrue((pic[8:, 8:] == 200).all())
        self.assertEqual(int(pic[:8].sum()) + int(pic[:, :8].sum()), 0)

    def test_paste_scales_nearest(self):
        pic = np.zeros((4, 4, 3), np.uint8)
        img = np.array([[[10] * 3, [20] * 3], [[30] * 3, [40] * 3]], np.uint8)
        compose.paste(pic, img, (0, 0, 4, 4))
        self.assertEqual(int(pic[0, 0, 0]), 10)
        self.assertEqual(int(pic[0, 3, 0]), 20)
        self.assertEqual(int(pic[3, 0, 0]), 30)
        self.assertEqual(int(pic[3, 3, 0]), 40)

    def test_paste_off_screen_is_ignored(self):
        pic = np.zeros((4, 4, 3), np.uint8)
        compose.paste(pic, np.full((2, 2, 3), 9, np.uint8), (10, 10, 2, 2))
        self.assertEqual(int(pic.sum()), 0)


class WallpaperTest(unittest.TestCase):
    def test_center_crop_command_and_result(self):
        seen = {}

        def run(cmd, **kw):
            seen["cmd"] = cmd
            return SimpleNamespace(returncode=0, stdout=b"P6\n4 2\n255\n" + bytes([7]) * 24)

        img = compose.wallpaper_base("/w.png", (4, 2), run=run)
        self.assertEqual(img.shape, (2, 4, 3))
        self.assertTrue(img.flags.writeable)
        self.assertIn("4x2^", seen["cmd"])
        self.assertIn("-extent", seen["cmd"])

    def test_missing_or_failing_is_black(self):
        def failing(cmd, **kw):
            raise subprocess.TimeoutExpired(cmd, 5)
        self.assertEqual(int(compose.wallpaper_base("", (4, 2)).sum()), 0)
        self.assertEqual(compose.wallpaper_base("/w.png", (4, 2), run=failing).shape, (2, 4, 3))


if __name__ == "__main__":
    unittest.main()


class AlphaTest(unittest.TestCase):
    def test_paste_blends_by_alpha_and_opacity(self):
        pic = np.full((2, 2, 3), 100, np.uint8)
        rgba = np.zeros((2, 2, 4), np.uint8)
        rgba[..., :3] = 200
        rgba[..., 3] = 128                     # about half transparent
        compose.paste(pic, rgba, (0, 0, 2, 2))
        self.assertEqual(int(pic[0, 0, 0]), 150)
        pic2 = np.full((2, 2, 3), 100, np.uint8)
        rgba[..., 3] = 255
        compose.paste(pic2, rgba, (0, 0, 2, 2), opacity=0.5)
        self.assertEqual(int(pic2[0, 0, 0]), 150)

    def test_window_opacity_from_focus_and_fullscreen(self):
        ops = {"active": 1.0, "inactive": 0.9, "fullscreen": 0.8}
        clients = [win("focused", [2560, 0], [100, 100], history=0), win("other", [2700, 0], [100, 100], history=3)]
        got = {w["id"]: w["opacity"] for w in compose.visible_windows(MON, clients, ops)}
        self.assertEqual(got, {"focused": 1.0, "other": 0.9})
        full = [win("video", [2560, 0], [2560, 1440], fullscreen=2)]
        self.assertEqual(compose.visible_windows(MON, full, ops)[0]["opacity"], 0.8)
        self.assertEqual(compose.visible_windows(MON, clients)[1]["opacity"], 1.0)   # default: opaque
