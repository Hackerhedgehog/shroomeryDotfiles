import os
import tempfile
import unittest

from screencolors import hypr


class HyprTest(unittest.TestCase):
    def test_focused_monitor(self):
        self.assertEqual(hypr.focused_monitor([{"name": "A"}, {"name": "B", "focused": True}]), "B")
        self.assertEqual(hypr.focused_monitor([{"name": "A"}]), "A")
        self.assertEqual(hypr.focused_monitor([]), "")

    def test_read_wallpaper(self):
        with tempfile.TemporaryDirectory() as d:
            image = os.path.join(d, "w.png")
            open(image, "w").close()
            cache = os.path.join(d, "current_wallpaper")
            with open(cache, "w") as f:
                f.write(image + "\n")
            self.assertEqual(hypr.read_wallpaper(cache), image)
            self.assertEqual(hypr.read_wallpaper(os.path.join(d, "missing")), "")
            with open(cache, "w") as f:
                f.write(os.path.join(d, "gone.png"))
            self.assertEqual(hypr.read_wallpaper(cache), "")

    def test_hypr_json_failure_is_empty(self):
        def failing(cmd, **kw):
            raise FileNotFoundError("hyprctl")
        self.assertEqual(hypr.hypr_json("clients", run=failing), [])


if __name__ == "__main__":
    unittest.main()


class OpacityTest(unittest.TestCase):
    def test_opacities_from_getoption(self):
        import json
        from types import SimpleNamespace
        values = {"decoration:active_opacity": 1.0, "decoration:inactive_opacity": 0.9,
                  "decoration:fullscreen_opacity": 0.8}

        def run(cmd, **kw):
            return SimpleNamespace(stdout=json.dumps({"option": cmd[-1], "float": values[cmd[-1]]}).encode())

        self.assertEqual(hypr.opacities(run=run), {"active": 1.0, "inactive": 0.9, "fullscreen": 0.8})

    def test_opacities_default_to_opaque(self):
        def failing(cmd, **kw):
            raise FileNotFoundError("hyprctl")
        self.assertEqual(hypr.opacities(run=failing), {"active": 1.0, "inactive": 1.0, "fullscreen": 1.0})


class DisplayedWallpaperTest(unittest.TestCase):
    def test_displayed_copy_wins_over_the_original(self):
        with tempfile.TemporaryDirectory() as d:
            original, shown = os.path.join(d, "w.png"), os.path.join(d, "negate-w.png")
            for path in (original, shown):
                open(path, "w").close()
            current, displayed = os.path.join(d, "current_wallpaper"), os.path.join(d, "displayed_wallpaper")
            with open(current, "w") as f:
                f.write(original + "\n")
            self.assertEqual(hypr.shown_wallpaper(displayed, current), original)   # no displayed file yet
            with open(displayed, "w") as f:
                f.write(shown + "\n")
            self.assertEqual(hypr.shown_wallpaper(displayed, current), shown)
            os.remove(shown)                                                      # cache cleared
            self.assertEqual(hypr.shown_wallpaper(displayed, current), original)
