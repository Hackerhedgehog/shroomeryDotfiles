"""An animated wallpaper as the wallpaper base: ffmpeg decodes the video (on
the GPU when it can) to the picture size, FPS frames a second, kept in step
with the mpvpaper that plays it (scripts/animated-wallpaper.sh) through mpv's
IPC socket. Frames go through a pipe; nothing is written to disk.
"""
import json
import os
import socket
import subprocess
import threading
import time
from pathlib import Path

import numpy as np

EXTENSIONS = (".mp4", ".webm", ".mkv", ".mov", ".m4v", ".avi", ".gif")   # lib.sh is_animated
FPS = 5
RESYNC_S = 5        # how often to compare with mpv's position
MAX_DRIFT_S = 1.0   # restart ffmpeg at mpv's position past this
RETRY_S = 5.0       # wait after ffmpeg failed on both GPU and CPU


def is_video(path):
    return bool(path) and path.lower().endswith(EXTENSIONS)


def mpv_dir():
    return Path(os.environ.get("XDG_RUNTIME_DIR", "/tmp")) / "shroomery" / "mpvpaper"


def mpv_get(sock_path, props, timeout=1.0):
    """Read properties from an mpv IPC socket: {name: value}, None on failure."""
    try:
        with socket.socket(socket.AF_UNIX) as s:
            s.settimeout(timeout)
            s.connect(str(sock_path))
            for i, name in enumerate(props):
                s.sendall(json.dumps({"command": ["get_property", name], "request_id": i}).encode() + b"\n")
            out, buf = {}, b""
            while len(out) < len(props):
                chunk = s.recv(65536)
                if not chunk:
                    return None
                buf += chunk
                while b"\n" in buf:
                    line, buf = buf.split(b"\n", 1)
                    reply = json.loads(line)
                    if "request_id" in reply and reply.get("error") == "success":
                        out[props[reply["request_id"]]] = reply.get("data")
                    elif "request_id" in reply:
                        return None
            return out
    except (OSError, ValueError, IndexError):
        return None


def mpv_position(monitor, base=None):
    """(time-pos, duration) of the mpvpaper on `monitor` (or on ALL), else None."""
    base = base or mpv_dir()
    for name in (monitor, "ALL"):
        sock = base / f"{name}.sock"
        if sock.exists():
            got = mpv_get(sock, ["time-pos", "duration"])
            if got and isinstance(got.get("time-pos"), (int, float)):
                return float(got["time-pos"]), float(got.get("duration") or 0)
    return None


def ffmpeg_cmd(path, size, start=0.0, gpu=True):
    """Decode `path` looping from `start` s as raw RGB frames center-cropped to
    fill `size` (w, h), FPS a second. On the GPU the 4K frames are shrunk
    before they are copied to memory; on the CPU only keyframes are decoded."""
    w, h = size
    fit = f"scale={w}:{h}:force_original_aspect_ratio=increase,crop={w}:{h},format=rgb24"
    cmd = ["ffmpeg", "-v", "error", "-nostdin"]
    if gpu:
        cmd += ["-hwaccel", "cuda", "-hwaccel_output_format", "cuda"]
        vf = f"fps={FPS},scale_cuda=trunc(iw/8)*2:trunc(ih/8)*2,hwdownload,format=nv12,{fit}"
    else:
        cmd += ["-skip_frame", "nokey"]
        vf = f"fps={FPS},{fit}"
    if start > 0:
        cmd += ["-ss", f"{start:.3f}"]
    return cmd + ["-stream_loop", "-1", "-i", path, "-an", "-vf", vf, "-f", "rawvideo", "-"]


def drift(ours, theirs, duration):
    """Seconds between two positions in a video that loops every `duration`."""
    if duration <= 0:
        return abs(ours - theirs)
    d = (ours - theirs) % duration
    return min(d, duration - d)


def read_exact(stream, n):
    data = b""
    while len(data) < n:
        chunk = stream.read(n - len(data))
        if not chunk:
            return None
        data += chunk
    return data


class VideoBase:
    """The latest frame of a video wallpaper for one monitor, decoded on its
    own thread at real-time pace. `current()` is None until the first frame."""

    def __init__(self, path, size, monitor, popen=subprocess.Popen, position=mpv_position,
                 clock=time.monotonic):
        self.path, self.size, self.monitor = path, size, monitor
        self.popen, self.position, self.clock = popen, position, clock
        self.key = (path, size)
        self._frame, self._proc = None, None
        self._stop = threading.Event()
        self._thread = threading.Thread(target=self._run, name=f"video-{monitor}", daemon=True)
        self._thread.start()

    def current(self):
        return self._frame

    def close(self):
        self._stop.set()
        self._kill()

    def _kill(self):
        proc, self._proc = self._proc, None
        if proc is not None:
            try:
                proc.kill()
                proc.wait(timeout=2)
            except (OSError, subprocess.SubprocessError):
                pass

    def _run(self):
        w, h = self.size
        gpu = True
        while not self._stop.is_set():
            pos = self.position(self.monitor)
            start, duration = pos if pos else (0.0, 0.0)
            try:
                self._proc = self.popen(ffmpeg_cmd(self.path, self.size, start, gpu),
                                        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
            except OSError:
                return
            t0, n = self.clock(), 0
            while not self._stop.is_set():
                proc = self._proc
                data = read_exact(proc.stdout, w * h * 3) if proc else None
                if data is None:
                    break
                self._frame = np.frombuffer(data, np.uint8).reshape(h, w, 3).copy()
                n += 1
                wait = t0 + n / FPS - self.clock()
                if wait > 0:
                    self._stop.wait(wait)
                if n % (FPS * RESYNC_S) == 0:
                    pos = self.position(self.monitor)
                    if pos and drift(start + n / FPS, pos[0], pos[1] or duration) > MAX_DRIFT_S:
                        break   # mpv paused (fullscreen) or seeked: start again where it is
            self._kill()
            if self._stop.is_set():
                break
            if n == 0 and gpu:
                gpu = False   # no CUDA: keyframes on the CPU
            elif n == 0:
                self._stop.wait(RETRY_S)
            else:
                self._stop.wait(0.2)   # never respawn in a tight loop
