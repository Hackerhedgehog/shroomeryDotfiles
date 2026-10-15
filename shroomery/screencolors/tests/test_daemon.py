import io
import os
import sys
import tempfile
import threading
import unittest
from pathlib import Path
from unittest import mock

import numpy as np

from screencolors import daemon, regions, server

MONS = [{"id": 0, "name": "DP-2", "x": 0, "y": 0, "width": 160, "height": 80, "scale": 1,
         "activeWorkspace": {"id": 1}, "specialWorkspace": {"id": 0, "name": ""}}]
CLIENTS = [{"stableId": "a", "monitor": 0, "workspace": {"id": 1}, "at": [0, 0], "size": [80, 80],
            "floating": False, "fullscreen": 0, "focusHistoryID": 0, "mapped": True, "hidden": False}]
RING = {"id": "viz", "shape": "ring", "cx": 0.5, "cy": 0.5, "inner": 0.1, "outer": 0.45, "sectors": 4}


class Fakes:
    def __init__(self):
        self.monitors, self.clients, self.grabs, self.fail = MONS, CLIENTS, 0, False

    def hypr(self, what):
        return {"monitors": self.monitors, "clients": self.clients}[what]

    def grab(self, sid):
        self.grabs += 1
        return None if self.fail else np.full((8, 8, 3), 200, np.uint8)


def builder(f):
    return daemon.Builder("DP-2", hypr=f.hypr, grab=f.grab,
                          wallpaper=lambda path, size: np.full((size[1], size[0], 3), 50, np.uint8),
                          wallpaper_path=lambda: "/w.png",
                          opacities=lambda: {"active": 1.0, "inactive": 1.0, "fullscreen": 1.0})


class BuilderTest(unittest.TestCase):
    def test_window_pasted_over_wallpaper(self):
        pic = builder(Fakes()).build([RING], True)
        self.assertEqual(pic.screen.shape, (10, 20, 3))          # 160x80 / 8
        self.assertEqual(int(pic.screen[5, 2, 0]), 200)          # the window (left half)
        self.assertEqual(int(pic.screen[5, 15, 0]), 50)          # wallpaper
        self.assertEqual(pic.windows, 1)

    def test_wallpaper_source_skips_windows(self):
        f = Fakes()
        pic = builder(f).build([RING], False)
        self.assertEqual(int(pic.screen.max()), 50)
        self.assertEqual((pic.windows, f.grabs), (0, 0))

    def test_failing_window_is_skipped_after_three(self):
        f = Fakes()
        f.fail = True
        b = builder(f)
        for _ in range(5):
            pic = b.build([RING], True)
        self.assertEqual(f.grabs, 3)
        self.assertEqual(int(pic.screen.max()), 50)

    def test_monitor_gone_returns_none(self):
        f = Fakes()
        b = builder(f)
        f.monitors = [dict(MONS[0], name="HDMI-A-1")]
        self.assertIsNone(b.build([RING], True))

    def test_hyprctl_failure_keeps_last_picture(self):
        f = Fakes()
        b = builder(f)
        first = b.build([RING], True)
        f.monitors = []
        self.assertIs(b.build([RING], True), first)

    def test_inactive_window_drawn_at_its_opacity(self):
        f = Fakes()
        f.clients = [dict(CLIENTS[0], focusHistoryID=3)]
        b = daemon.Builder("DP-2", hypr=f.hypr, grab=f.grab,
                           wallpaper=lambda path, size: np.full((size[1], size[0], 3), 50, np.uint8),
                           wallpaper_path=lambda: "/w.png",
                           opacities=lambda: {"active": 1.0, "inactive": 0.5, "fullscreen": 1.0})
        pic = b.build([RING], True)
        self.assertEqual(int(pic.screen[5, 2, 0]), 125)      # 0.5 · 200 + 0.5 · 50

    def test_opaque_windows_switch_to_the_cheap_capture(self):
        f = Fakes()
        calls = []

        def rgba(sid):
            calls.append("rgba")
            return np.full((8, 8, 3), 200, np.uint8)      # came back without alpha

        def opaque(sid):
            calls.append("ppm")
            return np.full((8, 8, 3), 200, np.uint8)

        b = daemon.Builder("DP-2", hypr=f.hypr, grab=rgba, grab_opaque=opaque,
                           wallpaper=lambda path, size: np.full((size[1], size[0], 3), 50, np.uint8),
                           wallpaper_path=lambda: "/w.png",
                           opacities=lambda: {"active": 1.0, "inactive": 1.0, "fullscreen": 1.0})
        for _ in range(3):
            b.build([RING], True)
        self.assertEqual(calls, ["rgba", "ppm", "ppm"])

    def test_hyprctl_failure_on_first_tick_is_skip_not_gone(self):
        f = Fakes()
        f.monitors = []
        self.assertIs(builder(f).build([RING], True), daemon.SKIP)

    def test_validation_with_hyprctl_down_asks_to_retry(self):
        msg = {"v": 2, "type": "subscribe", "monitor": "DP-2", "source": "screen", "regions": [RING]}
        with self.assertRaises(regions.SubscriptionError) as e:
            daemon.subscription_from(msg, lambda: [])
        self.assertIn("try again", str(e.exception))
        self.assertEqual(daemon.subscription_from(msg, lambda: MONS)["monitor"], "DP-2")

    def test_pattern(self):
        pic = builder(Fakes()).build([RING], True, pattern=True)
        self.assertEqual(tuple(pic.screen[0, 10]), (255, 0, 0))


class ClientStateTest(unittest.TestCase):
    def sub(self, *regs):
        return {"monitor": "DP-2", "source": "screen", "regions": list(regs)}

    def test_resubscribe_keeps_unchanged_smoothers(self):
        st = daemon.ClientState()
        st.subscribe(self.sub(RING))
        first = st.smoothers["viz"][1]
        st.subscribe(self.sub(dict(RING)))
        self.assertIs(st.smoothers["viz"][1], first)
        st.subscribe(self.sub(dict(RING, sectors=8)))
        self.assertIsNot(st.smoothers["viz"][1], first)

    def test_frame_after_a_sample(self):
        st = daemon.ClientState()
        st.subscribe(self.sub(RING))
        self.assertIsNone(st.frame(33, 0, 1000))
        pic = builder(Fakes()).build([RING], True)
        st.sample(pic, regions.LabelCache())
        f = st.frame(33, pic.windows, 1000)
        self.assertEqual((f["v"], f["monitor"], f["source"], f["windows"]), (2, "DP-2", "screen", 1))
        self.assertEqual(len(f["regions"]["viz"]["colors"]), 4)
        self.assertEqual(st.frame(33, 0, 1000, source_label="pattern")["source"], "pattern")


class WatchTest(unittest.TestCase):
    def test_watch_subscribes_and_exits_quietly_when_stdout_closes(self):
        class ClosedPipe(io.StringIO):
            def write(self, s):
                raise BrokenPipeError(32, "Broken pipe")

        with tempfile.TemporaryDirectory() as d:
            srv = server.Server(os.path.join(d, "screen-colors.sock"))
            stop, got = threading.Event(), []

            def serve():
                while not stop.is_set():
                    got.extend(line for _, line in srv.poll())
                    if got:   # reply only once the subscription arrived (no race)
                        srv.broadcast(b'{"type":"frame"}\n')
                    stop.wait(0.01)

            t = threading.Thread(target=serve)
            t.start()
            try:
                with mock.patch.object(daemon, "runtime_dir", return_value=Path(d)), \
                        mock.patch.object(sys, "stdout", ClosedPipe()):
                    self.assertEqual(daemon.watch(monitor="DP-2"), 0)
            finally:
                stop.set()
                t.join()
                srv.close()
            self.assertTrue(any('"type":"subscribe"' in line and '"DP-2"' in line for line in got))


if __name__ == "__main__":
    unittest.main()
