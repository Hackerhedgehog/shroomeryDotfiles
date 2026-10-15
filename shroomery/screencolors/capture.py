"""Frames as small uint8 arrays: one window through grim, or an image file.

grim -T captures a single toplevel's own buffer, so layer-shell surfaces
(the visualizer overlay, the status bar) are never in the frame. Frames go
through a pipe; nothing is written to disk. Don't use grim -s: it scales on
the CPU and is slower than a full-size capture (README.md section 2.1).
"""
import re
import struct
import subprocess
import zlib

import numpy as np

LONG_SIDE = 256
TIMEOUT_S = 2.0
_PPM_HEADER = re.compile(rb"P6\s+(\d+)\s+(\d+)\s+(\d+)\s")


def parse_ppm(data):
    m = _PPM_HEADER.match(data)
    if not m:
        return None
    w, h, maxval = (int(g) for g in m.groups())
    if maxval != 255:
        return None
    body = data[m.end():m.end() + w * h * 3]
    if len(body) != w * h * 3:
        return None
    return np.frombuffer(body, dtype=np.uint8).reshape(h, w, 3)


def downsample(img, long_side=LONG_SIDE):
    step = max(1, -(-max(img.shape[:2]) // long_side))
    return img[::step, ::step]


def _run_ppm(cmd, run):
    try:
        result = run(cmd, capture_output=True, timeout=TIMEOUT_S)
    except (OSError, subprocess.SubprocessError):
        return None
    if result.returncode != 0:
        return None
    img = parse_ppm(result.stdout)
    return None if img is None else downsample(img)


def capture_window(stable_id, run=subprocess.run):
    return _run_ppm(["grim", "-T", stable_id, "-t", "ppm", "-"], run)


def load_image(path, run=subprocess.run):
    return _run_ppm(["magick", path + "[0]", "-resize", f"{LONG_SIDE}x{LONG_SIDE}>",
                     "-depth", "8", "ppm:-"], run)


def parse_png_rgba(data):
    """An 8-bit RGBA or RGB PNG whose rows all use filter 0 (what `grim -l 0`
    writes: RGBA for translucent windows, RGB for opaque ones) -> uint8
    (H, W, 4 or 3); None for anything else (the caller falls back to PPM)."""
    if not data.startswith(b"\x89PNG\r\n\x1a\n"):
        return None
    pos, ihdr, chunks = 8, None, []
    try:
        while pos + 8 <= len(data):
            length, kind = struct.unpack(">I4s", data[pos:pos + 8])
            body = data[pos + 8:pos + 8 + length]
            if kind == b"IHDR":
                ihdr = struct.unpack(">IIBBBBB", body)
            elif kind == b"IDAT":
                chunks.append(body)
            elif kind == b"IEND":
                break
            pos += 12 + length
        if ihdr is None:
            return None
        w, h, depth, ctype, _, _, interlace = ihdr
        if depth != 8 or ctype not in (2, 6) or interlace != 0:
            return None
        raw = zlib.decompress(b"".join(chunks))
    except (struct.error, zlib.error):
        return None
    channels = 4 if ctype == 6 else 3
    if len(raw) != h * (w * channels + 1):
        return None
    rows = np.frombuffer(raw, dtype=np.uint8).reshape(h, w * channels + 1)
    if rows[:, 0].any():
        return None
    return rows[:, 1:].reshape(h, w, channels)


def capture_window_rgba(stable_id, run=subprocess.run):
    """One window with its alpha (translucent terminals show what's behind
    them): grim's uncompressed PNG, about as fast as PPM. Falls back to the
    opaque PPM capture if the PNG can't be read."""
    try:
        result = run(["grim", "-T", stable_id, "-t", "png", "-l", "0", "-"],
                     capture_output=True, timeout=TIMEOUT_S)
    except (OSError, subprocess.SubprocessError):
        return None
    if result.returncode != 0:
        return None
    img = parse_png_rgba(result.stdout)
    if img is None:
        return capture_window(stable_id, run)
    return downsample(img)

