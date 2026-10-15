import io
import json
import os
import socket
import tempfile
import threading
import time
import unittest
from pathlib import Path

import numpy as np

from screencolors import daemon, video
from screencolors.tests.test_daemon import MONS, RING, Fakes


class FakeProc:
    def __init__(self, frames, size):
        w, h = size
        self.stdout = io.BytesIO(b"".join(bytes([v]) * (w * h * 3) for v in frames))
        self.killed = False

    def kill(self):
        self.killed = True

    def wait(self, timeout=None):
        return 0


def wait_for(cond, timeout=2.0):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        if cond():
            return True
        time.sleep(0.01)
    return False


class HelpersTest(unittest.TestCase):
    def test_is_video(self):
        self.assertTrue(video.is_video("/w/Galaxy Eyes.MP4"))
        self.assertTrue(video.is_video("/w/a.gif"))
        self.assertFalse(video.is_video("/w/a.png"))
        self.assertFalse(video.is_video(""))

    def test_ffmpeg_cmd_gpu_seeks_and_fills_size(self):
        cmd = video.ffmpeg_cmd("/v.mp4", (480, 270), 3.5)
        self.assertIn("cuda", cmd)
        self.assertEqual(cmd[cmd.index("-ss") + 1], "3.500")
        vf = cmd[cmd.index("-vf") + 1]
        self.assertIn("scale_cuda", vf)
        self.assertIn("crop=480:270", vf)
        self.assertEqual(cmd[cmd.index("-i") + 1], "/v.mp4")

    def test_ffmpeg_cmd_cpu_decodes_keyframes_only(self):
        cmd = video.ffmpeg_cmd("/v.mp4", (480, 270), 0, gpu=False)
        self.assertNotIn("cuda", " ".join(cmd))
        self.assertIn("nokey", cmd)
        self.assertNotIn("-ss", cmd)

    def test_drift_wraps_around_the_loop(self):
        self.assertAlmostEqual(video.drift(16.9, 0.1, 17.0), 0.2)
        self.assertAlmostEqual(video.drift(5.0, 8.0, 17.0), 3.0)
        self.assertAlmostEqual(video.drift(5.0, 8.0, 0), 3.0)


class MpvTest(unittest.TestCase):
    def test_position_from_the_all_socket(self):
        with tempfile.TemporaryDirectory() as d:
            path = Path(d) / "ALL.sock"
            srv = socket.socket(socket.AF_UNIX)
            srv.bind(str(path))
            srv.listen(1)

            def serve():
                conn, _ = srv.accept()
                with conn:
                    buf = b""
                    while buf.count(b"\n") < 2:
                        buf += conn.recv(4096)
                    for line in buf.splitlines():
                        req = json.loads(line)
                        data = {"time-pos": 4.5, "duration": 17.0}[req["command"][1]]
                        conn.sendall(json.dumps({"event": "noise"}).encode() + b"\n")
                        conn.sendall(json.dumps({"request_id": req["request_id"], "error": "success",
                                                 "data": data}).encode() + b"\n")

            t = threading.Thread(target=serve)
            t.start()
            self.assertEqual(video.mpv_position("DP-2", Path(d)), (4.5, 17.0))
            t.join()
            srv.close()

    def test_no_socket_is_none(self):
        with tempfile.TemporaryDirectory() as d:
            self.assertIsNone(video.mpv_position("DP-2", Path(d)))


class VideoBaseTest(unittest.TestCase):
    def test_frames_arrive_from_mpv_position(self):
        calls = []

        def popen(cmd, **kw):
            calls.append(cmd)
            return FakeProc([10, 20], (4, 2))

        vb = video.VideoBase("/v.mp4", (4, 2), "DP-2", popen=popen, position=lambda m: (2.0, 17.0))
        self.assertTrue(wait_for(lambda: vb.current() is not None and int(vb.current()[0, 0, 0]) == 20))
        vb.close()
        self.assertEqual(vb.current().shape, (2, 4, 3))
        self.assertEqual(calls[0][calls[0].index("-ss") + 1], "2.000")

    def test_falls_back_to_cpu_when_gpu_gives_nothing(self):
        calls = []

        def popen(cmd, **kw):
            calls.append(cmd)
            return FakeProc([] if "cuda" in cmd else [7], (2, 2))

        vb = video.VideoBase("/v.mp4", (2, 2), "DP-2", popen=popen, position=lambda m: None)
        self.assertTrue(wait_for(lambda: vb.current() is not None))
        vb.close()
        self.assertIn("cuda", calls[0])
        self.assertNotIn("cuda", calls[1])


class FakeVideo:
    made = []

    def __init__(self, path, size, monitor):
        self.key, self.closed = (path, size), False
        FakeVideo.made.append(self)

    def current(self):
        return np.full((self.key[1][1], self.key[1][0], 3), 90, np.uint8)

    def close(self):
        self.closed = True


class BuilderVideoTest(unittest.TestCase):
    def setUp(self):
        FakeVideo.made = []
        self.path = "/w/a.mp4"
        f = Fakes()
        self.b = daemon.Builder("DP-2", hypr=f.hypr, grab=f.grab,
                                wallpaper=lambda path, size: np.full((size[1], size[0], 3), 50, np.uint8),
                                wallpaper_path=lambda: self.path,
                                opacities=lambda: {"active": 1.0, "inactive": 1.0, "fullscreen": 1.0},
                                video_base=FakeVideo)

    def test_video_frame_is_the_base(self):
        pic = self.b.build([RING], False)
        self.assertEqual(int(pic.base.max()), 90)
        self.b.build([RING], False)
        self.assertEqual(len(FakeVideo.made), 1)   # one decoder, reused

    def test_switch_to_image_closes_the_decoder(self):
        self.b.build([RING], False)
        self.path = "/w/a.png"
        pic = self.b.build([RING], False)
        self.assertTrue(FakeVideo.made[0].closed)
        self.assertEqual(int(pic.base.max()), 50)


if __name__ == "__main__":
    unittest.main()
