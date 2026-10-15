"""The sampling loop (protocol v2): per monitor, rebuild a small picture of
the screen; per client, sample its regions, smooth them and publish.

Pictures are built on worker threads so a slow grab never stalls the 30 Hz
publishing. Run through scripts/screen-colors.py; see README.md.
"""
import concurrent.futures
import os
import socket
import sys
import time
from pathlib import Path

import numpy as np

from screencolors import capture, color, compose, hypr, protocol, regions, server, smoothing, video

PUBLISH_HZ = 30
FAILURE_LIMIT = 3
SKIP = object()   # Builder.build: nothing to report this tick (hyprctl hiccup before any picture)


def runtime_dir():
    path = Path(os.environ.get("XDG_RUNTIME_DIR", "/tmp")) / "shroomery"
    path.mkdir(parents=True, exist_ok=True)
    return path


def wallpaper_cache():
    return Path.home() / ".cache" / "shroomery" / "current_wallpaper"


def log(message):
    print(f"screen-colors: {message}", file=sys.stderr, flush=True)


def current_wallpaper():
    cache = wallpaper_cache().parent
    return hypr.shown_wallpaper(cache / "displayed_wallpaper", cache / "current_wallpaper")


class Picture:
    """One capture tick of a monitor: the rebuilt screen and the wallpaper
    base, each as uint8 and in linear light."""

    def __init__(self, screen, base, windows):
        self.screen, self.base, self.windows = screen, base, windows
        self.screen_lin = color.srgb_to_linear(screen / 255.0)
        self.base_lin = self.screen_lin if screen is base else color.srgb_to_linear(base / 255.0)

    def for_source(self, source):
        if source == "wallpaper":
            return self.base, self.base_lin
        return self.screen, self.screen_lin


class Builder:
    """Builds Pictures for one monitor. Runs on a worker thread and owns its
    wallpaper cache, the last layout and the per-window failure counts."""

    def __init__(self, monitor, hypr=hypr.hypr_json, grab=capture.capture_window_rgba,
                 grab_opaque=capture.capture_window, wallpaper=compose.wallpaper_base,
                 wallpaper_path=current_wallpaper, opacities=hypr.opacities, video_base=video.VideoBase):
        self.monitor, self.hypr, self.grab, self.grab_opaque = monitor, hypr, grab, grab_opaque
        self.opaque = set()   # windows whose capture had no transparency: cheaper PPM next time
        self.wallpaper, self.wallpaper_path = wallpaper, wallpaper_path
        self.video_base, self.video = video_base, None   # an animated wallpaper's decoder
        self.opacities, self.ops = opacities, None
        self.base_key, self.base = None, None
        self.layout, self.failures = (), {}
        self.last, self.last_clients = None, []

    def build(self, specs, want_screen, pattern=False):
        monitors = self.hypr("monitors")
        if not monitors:
            return self.last or SKIP              # hyprctl hiccup: keep the last picture
        mon = next((m for m in monitors if m.get("name") == self.monitor), None)
        if mon is None:
            return None                           # monitor gone
        size = compose.picture_size(mon)
        if pattern:
            img = regions.pattern_picture(*size)
            self.last = Picture(img, img, 0)
            return self.last
        self.base = self._base(self.wallpaper_path(), size)
        if not want_screen:
            self.last = Picture(self.base, self.base, 0)
            return self.last
        clients = self.hypr("clients") or self.last_clients
        self.last_clients = clients
        if self.ops is None:
            self.ops = self.opacities()   # read once per builder (they rarely change)
        windows = compose.visible_windows(mon, clients, self.ops)
        layout = tuple(w["id"] for w in windows)
        if layout != self.layout:
            self.layout, self.failures = layout, {}
            self.opaque &= set(layout)
        boxes = [box for spec in specs for box in compose.region_boxes(spec, *size)]
        screen, pasted = self.base.copy(), 0
        for win in compose.choose(windows, boxes):
            if self.failures.get(win["id"], 0) >= FAILURE_LIMIT:
                continue
            opaque = win["id"] in self.opaque
            img = (self.grab_opaque if opaque else self.grab)(win["id"])
            if img is not None and not opaque and (img.shape[2] == 3 or (img[..., 3] == 255).all()):
                self.opaque.add(win["id"])
            if img is None:
                self.failures[win["id"]] = self.failures.get(win["id"], 0) + 1
                continue
            self.failures.pop(win["id"], None)
            compose.paste(screen, img, win["rect"], win["opacity"])
            pasted += 1
        self.last = Picture(screen, self.base, pasted)
        return self.last

    def _base(self, path, size):
        """The wallpaper at picture size: an image decoded once, or a video's
        latest frame (black until the first one arrives)."""
        if video.is_video(path):
            if self.video is None or self.video.key != (path, size):
                self.close()
                self.video = self.video_base(path, size, self.monitor)
            self.base_key = None
            frame = self.video.current()
            return frame if frame is not None else np.zeros((size[1], size[0], 3), np.uint8)
        self.close()
        if (path, size) != self.base_key:
            self.base_key, self.base = (path, size), self.wallpaper(path, size)
        return self.base

    def close(self):
        if self.video is not None:
            self.video.close()
            self.video = None


def list_monitors():
    return hypr.hypr_json("monitors")


def subscription_from(msg, monitors=list_monitors):
    """Validate a `subscribe` message against the connected outputs. An empty
    answer means hyprctl failed, not "no monitors": ask the client to retry."""
    found = monitors()
    if not found:
        raise regions.SubscriptionError("can't list monitors right now; try again")
    return regions.validate_subscription(msg, [m["name"] for m in found])


class ClientState:
    """One client's subscription and a smoother per region (kept while the
    region's spec doesn't change)."""

    def __init__(self):
        self.sub = None
        self.smoothers = {}   # region id -> (spec key, ZoneSmoother)

    def subscribe(self, sub):
        keep = {}
        for spec in sub["regions"]:
            key = regions.spec_key(spec)
            old = self.smoothers.get(spec["id"])
            keep[spec["id"]] = old if old and old[0] == key else (key, smoothing.ZoneSmoother())
        self.sub, self.smoothers = sub, keep

    def sample(self, picture, cache):
        img, lin = picture.for_source(self.sub["source"])
        for spec in self.sub["regions"]:
            zone_lin, average_lin = regions.sample(spec, img, lin, cache)
            lab = color.linear_to_oklab(np.vstack([zone_lin, average_lin]))
            self.smoothers[spec["id"]][1].sample(lab)

    def frame(self, dt_ms, windows, t_ms, source_label=None):
        out = {}
        for spec in self.sub["regions"]:
            current = self.smoothers[spec["id"]][1].step(dt_ms)
            if current is None:
                return None
            hexes = color.to_hex(color.linear_to_srgb(color.oklab_to_linear(current)))
            out[spec["id"]] = {"colors": hexes[:-1], "average": hexes[-1]}
        return protocol.frame(self.sub["monitor"], source_label or self.sub["source"], windows, out, t_ms)


def run(rate=5.0, idle_exit=5.0, pattern=False):
    rdir = runtime_dir()
    lock = server.acquire_lock(str(rdir / "screen-colors.lock"))
    if lock is None:
        return 0  # another daemon already serves the socket
    srv = server.Server(str(rdir / "screen-colors.sock"))
    pool = concurrent.futures.ThreadPoolExecutor(max_workers=2)
    states, builders, pending, next_capture, windows = {}, {}, {}, {}, {}
    cache = regions.LabelCache()
    last_tick = last_client = time.monotonic()
    log(f"serving {srv.path}")
    try:
        while True:
            now = time.monotonic()
            for client, line in srv.poll():
                msg = protocol.parse_line(line)
                if not msg or msg.get("type") != "subscribe":
                    continue
                try:
                    sub = subscription_from(msg)
                except regions.SubscriptionError as e:
                    srv.send(client, protocol.encode(protocol.error(e)))
                    continue
                states.setdefault(client, ClientState()).subscribe(sub)
                log(f"subscribe {sub['monitor']} {sub['source']} {[r['id'] for r in sub['regions']]}")
            for client in [c for c in states if c not in srv.clients]:
                del states[client]

            wanted = {}
            for st in states.values():
                if st.sub:
                    want = wanted.setdefault(st.sub["monitor"], {"specs": [], "screen": False})
                    want["specs"] += st.sub["regions"]
                    want["screen"] |= st.sub["source"] == "screen"
            for name, want in wanted.items():
                if name not in pending and now >= next_capture.get(name, 0):
                    b = builders.setdefault(name, Builder(name))
                    pending[name] = pool.submit(b.build, want["specs"], want["screen"], pattern)
                    next_capture[name] = now + 1.0 / rate
            for name in [n for n in builders if n not in wanted and n not in pending]:
                builders.pop(name).close()

            for name, fut in list(pending.items()):
                if not fut.done():
                    continue
                del pending[name]
                try:
                    picture = fut.result()
                except Exception as e:  # a bug in one tick must not stop the daemon
                    log(f"capture failed on {name}: {e!r}")
                    continue
                if picture is SKIP:
                    continue
                if picture is None:
                    for client, st in states.items():
                        if st.sub and st.sub["monitor"] == name:
                            srv.send(client, protocol.encode(protocol.error("monitor gone")))
                            st.sub = None
                    continue
                windows[name] = picture.windows
                for st in states.values():
                    if st.sub and st.sub["monitor"] == name:
                        st.sample(picture, cache)

            dt = (now - last_tick) * 1000.0
            for client, st in list(states.items()):
                if st.sub:
                    f = st.frame(dt, windows.get(st.sub["monitor"], 0), time.time() * 1000,
                                 "pattern" if pattern else None)
                    if f:
                        srv.send(client, protocol.encode(f))
            last_tick = now
            if srv.client_count:
                last_client = now
            elif idle_exit > 0 and now - last_client > idle_exit:
                log("no clients, exiting")
                return 0
            time.sleep(max(0.0, 1.0 / PUBLISH_HZ - (time.monotonic() - now)))
    finally:
        for b in builders.values():
            b.close()
        pool.shutdown(wait=False, cancel_futures=True)
        srv.close()
        os.close(lock)


def default_subscription(monitor):
    """--watch without --subscribe: the screen edges, like protocol v1."""
    return {"v": 2, "type": "subscribe", "monitor": monitor, "source": "screen",
            "regions": [{"id": "edges", "shape": "edges", "top": 16, "right": 9,
                         "bottom": 16, "left": 9, "depth": 0.15}]}


def watch(monitor="", subscription=None):
    """Subscribe and print the running daemon's frames (a debugging client)."""
    path = runtime_dir() / "screen-colors.sock"
    if subscription is None:
        monitor = monitor or hypr.focused_monitor(hypr.hypr_json("monitors"))
        subscription = default_subscription(monitor)
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
            s.connect(str(path))
            s.sendall(protocol.encode(subscription))
            for line in s.makefile("r", encoding="utf-8"):
                print(line, end="", flush=True)
    except (FileNotFoundError, ConnectionRefusedError):
        log(f"no daemon at {path}")
        return 1
    except (KeyboardInterrupt, BrokenPipeError):
        # Piped into `head`: the reader left. Point stdout at /dev/null so
        # the interpreter's final flush doesn't complain again.
        os.dup2(os.open(os.devnull, os.O_WRONLY), sys.__stdout__.fileno())
    return 0
