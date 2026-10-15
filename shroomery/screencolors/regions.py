"""Sampling regions (protocol v2): validating subscriptions, laying zones out
on the rebuilt picture, and their colors.

Zone order: ring sectors clockwise from 12 o'clock; edges clockwise from the
top-left corner (corners belong to the top and bottom bands); rects in the
order given (README.md section 3).
"""
import json

import numpy as np

from screencolors import zones

MAX_REGIONS = 8
SOURCES = ("screen", "wallpaper")


class SubscriptionError(ValueError):
    """A subscription the daemon refuses; the message goes back to the client."""


def _number(value, lo, hi, what):
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not lo <= value <= hi:
        raise SubscriptionError(f"{what} must be a number in {lo}..{hi}")
    return float(value)


def _count(value, lo, hi, what):
    if isinstance(value, bool) or not isinstance(value, int) or not lo <= value <= hi:
        raise SubscriptionError(f"{what} must be a whole number in {lo}..{hi}")
    return value


def _region(raw):
    if not isinstance(raw, dict):
        raise SubscriptionError("each region must be an object")
    rid = raw.get("id")
    if not isinstance(rid, str) or not 1 <= len(rid) <= 32:
        raise SubscriptionError("region id must be a string of 1..32 characters")
    shape = raw.get("shape")
    if shape == "ring":
        inner = _number(raw.get("inner"), 0, 2, f"{rid}.inner")
        outer = _number(raw.get("outer"), 0, 2, f"{rid}.outer")
        if inner >= outer:
            raise SubscriptionError(f"{rid}: inner must be smaller than outer")
        return {"id": rid, "shape": "ring", "cx": _number(raw.get("cx"), 0, 1, f"{rid}.cx"),
                "cy": _number(raw.get("cy"), 0, 1, f"{rid}.cy"), "inner": inner, "outer": outer,
                "sectors": _count(raw.get("sectors"), 4, 360, f"{rid}.sectors")}
    if shape == "edges":
        spec = {"id": rid, "shape": "edges"}
        for side in ("top", "right", "bottom", "left"):
            spec[side] = _count(raw.get(side), 1, 200, f"{rid}.{side}")
        spec["depth"] = _number(raw.get("depth"), 0.01, 0.5, f"{rid}.depth")
        return spec
    if shape == "rects":
        rects = raw.get("rects")
        if not isinstance(rects, list) or not 1 <= len(rects) <= 256:
            raise SubscriptionError(f"{rid}.rects must be a list of 1..256 rectangles")
        out = []
        for i, r in enumerate(rects):
            if not isinstance(r, list) or len(r) != 4:
                raise SubscriptionError(f"{rid}.rects[{i}] must be [x, y, w, h]")
            x, y, w, h = (_number(v, 0, 1, f"{rid}.rects[{i}]") for v in r)
            if w <= 0 or h <= 0 or x + w > 1 + 1e-9 or y + h > 1 + 1e-9:
                raise SubscriptionError(f"{rid}.rects[{i}] must have w, h > 0 and stay inside 0..1")
            out.append((x, y, w, h))
        return {"id": rid, "shape": "rects", "rects": out}
    raise SubscriptionError(f"{rid}: unknown shape {shape!r} (ring, edges or rects)")


def validate_subscription(msg, monitors):
    """A parsed `subscribe` message -> {"monitor", "source", "regions": [spec]}.
    `monitors`: the connected output names. Raises SubscriptionError."""
    monitor = msg.get("monitor")
    if monitor not in monitors:
        raise SubscriptionError(f"unknown monitor {monitor!r}")
    source = msg.get("source", "screen")
    if source not in SOURCES:
        raise SubscriptionError("source must be 'screen' or 'wallpaper'")
    raw = msg.get("regions")
    if not isinstance(raw, list) or not 1 <= len(raw) <= MAX_REGIONS:
        raise SubscriptionError(f"regions must be a list of 1..{MAX_REGIONS}")
    specs = [_region(r) for r in raw]
    if len({s["id"] for s in specs}) != len(specs):
        raise SubscriptionError("region ids must be unique")
    return {"monitor": monitor, "source": source, "regions": specs}


def zone_count(spec):
    if spec["shape"] == "ring":
        return spec["sectors"]
    if spec["shape"] == "edges":
        return spec["top"] + spec["right"] + spec["bottom"] + spec["left"]
    return len(spec["rects"])


def spec_key(spec):
    return json.dumps(spec, sort_keys=True)


def ring_labels(spec, w, h):
    """(h, w) int32: each pixel's sector (clockwise from 12 o'clock), or -1."""
    s = min(w, h)
    ys, xs = np.mgrid[0:h, 0:w]
    dx = xs + 0.5 - spec["cx"] * w
    dy = ys + 0.5 - spec["cy"] * h
    r = np.hypot(dx, dy) / s
    turn = np.mod(np.arctan2(dx, -dy), 2 * np.pi) / (2 * np.pi)
    n = spec["sectors"]
    sector = np.minimum((turn * n).astype(np.int32), n - 1)
    return np.where((r >= spec["inner"]) & (r <= spec["outer"]), sector, -1).astype(np.int32)


def _split(n, length):
    return np.minimum((np.arange(length) * n) // length, n - 1)


def edges_labels(spec, w, h):
    """(h, w) int32 edge zones, clockwise from the top-left corner, or -1."""
    t, r, b, l = spec["top"], spec["right"], spec["bottom"], spec["left"]
    d = max(1, round(spec["depth"] * min(w, h)))
    labels = np.full((h, w), -1, np.int32)
    labels[:, w - d:] = (t + _split(r, h))[:, None]
    labels[:, :d] = (t + r + b + (l - 1 - _split(l, h)))[:, None]
    labels[:d, :] = _split(t, w)[None, :]
    labels[h - d:, :] = (t + r + (b - 1 - _split(b, w)))[None, :]
    return labels


def rect_boxes(spec, w, h):
    """Pixel boxes (x0, y0, x1, y1) of the rectangles, each at least 1 px."""
    out = []
    for x, y, rw, rh in spec["rects"]:
        x0 = min(w - 1, int(np.floor(x * w)))
        y0 = min(h - 1, int(np.floor(y * h)))
        x1 = max(x0 + 1, min(w, int(np.ceil((x + rw) * w))))
        y1 = max(y0 + 1, min(h, int(np.ceil((y + rh) * h))))
        out.append((x0, y0, x1, y1))
    return out


def fill_empty(means, counts, wrap):
    """Zones without pixels take the color of the nearest zone that has some."""
    n = len(counts)
    have = np.nonzero(counts)[0]
    if len(have) == 0:
        return np.zeros((n, 3))
    out = means.copy()
    for i in np.nonzero(counts == 0)[0]:
        dist = np.abs(have - i)
        if wrap:
            dist = np.minimum(dist, n - dist)
        out[i] = means[have[np.argmin(dist)]]
    return out


class LabelCache:
    """Label maps by (region spec, picture size); rebuilt only when either changes."""

    def __init__(self):
        self.maps = {}

    def labels(self, spec, w, h):
        key = (spec_key(spec), w, h)
        if key not in self.maps:
            if len(self.maps) > 64:
                self.maps.clear()
            make = ring_labels if spec["shape"] == "ring" else edges_labels
            self.maps[key] = make(spec, w, h)
        return self.maps[key]


def sample(spec, picture, lin, cache):
    """A region's zone colors and average, in linear light, from the rebuilt
    picture (`picture` uint8 (h, w, 3); `lin` the same in linear light)."""
    n = zone_count(spec)
    if spec["shape"] == "rects":
        h, w = lin.shape[:2]
        means, counts = np.zeros((n, 3)), np.zeros(n)
        for i, (x0, y0, x1, y1) in enumerate(rect_boxes(spec, w, h)):
            box = lin[y0:y1, x0:x1].reshape(-1, 3)
            means[i], counts[i] = box.mean(axis=0), len(box)
        return means, (means * counts[:, None]).sum(axis=0) / counts.sum()
    if spec["shape"] == "edges":
        top, bottom, left, right = zones.letterbox_box(picture)
        lin = lin[top:lin.shape[0] - bottom, left:lin.shape[1] - right]
    h, w = lin.shape[:2]
    labels = cache.labels(spec, w, h).ravel()
    inside = labels >= 0
    idx = labels[inside]
    if len(idx) == 0:
        return np.zeros((n, 3)), np.zeros(3)
    px = lin.reshape(-1, 3)[inside]
    counts = np.bincount(idx, minlength=n)
    sums = np.stack([np.bincount(idx, weights=px[:, c], minlength=n) for c in range(3)], axis=1)
    means = sums / np.maximum(counts, 1)[:, None]
    return fill_empty(means, counts, wrap=True), sums.sum(axis=0) / counts.sum()


def pattern_picture(w, h):
    """The --pattern test picture: each pixel the color of its direction from
    the center (up red, right green, down blue, left yellow)."""
    ys, xs = np.mgrid[0:h, 0:w]
    nx = (xs + 0.5) / w - 0.5
    ny = (ys + 0.5) / h - 0.5
    img = np.zeros((h, w, 3), np.uint8)
    horizontal = np.abs(nx) > np.abs(ny)
    img[horizontal & (nx > 0)] = (0, 255, 0)
    img[horizontal & (nx <= 0)] = (255, 255, 0)
    img[~horizontal & (ny < 0)] = (255, 0, 0)
    img[~horizontal & (ny >= 0)] = (0, 0, 255)
    return img
