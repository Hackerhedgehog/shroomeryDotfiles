"""The rebuilt screen: the wallpaper with the visible windows that matter
pasted at their positions, at 1/SCALE of the monitor's logical size. Windows
are captured with grim -T, so no layer surface (the bar, the visualizer
overlay) is ever in the picture.
"""
import subprocess

import numpy as np

from screencolors import capture

SCALE = 8
MAX_WINDOWS = 6


def picture_size(mon):
    scale = mon.get("scale") or 1
    return (max(1, round(mon["width"] / scale / SCALE)), max(1, round(mon["height"] / scale / SCALE)))


def visible_windows(mon, clients, opacities=None):
    """The windows on the monitor's visible workspace(s), in paint order
    (bottom first): tiled, then floating oldest-focus first; an open special
    workspace above that. A fullscreen window is returned alone. Each is
    {"id": stableId, "rect": (x, y, w, h) in picture px, "opacity"}, the
    opacity Hyprland draws it with (`opacities`: active / inactive /
    fullscreen from decoration:*_opacity; default opaque)."""
    ops = opacities or {"active": 1.0, "inactive": 1.0, "fullscreen": 1.0}
    ox, oy = mon.get("x", 0), mon.get("y", 0)
    special = (mon.get("specialWorkspace") or {}).get("id", 0)

    def on(ws):
        return [c for c in clients
                if c.get("mapped", True) and not c.get("hidden", False)
                and c.get("monitor") == mon.get("id") and c["workspace"]["id"] == ws]

    def ordered(cs):
        tiled = [c for c in cs if not c.get("floating")]
        floating = sorted((c for c in cs if c.get("floating")), key=lambda c: -c.get("focusHistoryID", 0))
        return tiled + floating

    layers = ordered(on(mon["activeWorkspace"]["id"])) + (ordered(on(special)) if special else [])
    full = [c for c in layers if c.get("fullscreen", 0)]
    if full:
        layers = [min(full, key=lambda c: c.get("focusHistoryID", 1 << 30))]
    def opacity(c):
        if c.get("fullscreen", 0):
            return ops["fullscreen"]
        return ops["active"] if c.get("focusHistoryID", 1) == 0 else ops["inactive"]

    return [{"id": c["stableId"],
             "rect": ((c["at"][0] - ox) / SCALE, (c["at"][1] - oy) / SCALE,
                      c["size"][0] / SCALE, c["size"][1] / SCALE),
             "opacity": opacity(c)}
            for c in layers]


def region_boxes(spec, w, h):
    """Bounding boxes (x0, y0, x1, y1, picture px) of what a region samples."""
    s = min(w, h)
    if spec["shape"] == "ring":
        r = spec["outer"] * s
        return [(spec["cx"] * w - r, spec["cy"] * h - r, spec["cx"] * w + r, spec["cy"] * h + r)]
    if spec["shape"] == "edges":
        d = spec["depth"] * s
        return [(0, 0, w, d), (w - d, 0, w, h), (0, h - d, w, h), (0, 0, d, h)]
    return [(x * w, y * h, (x + rw) * w, (y + rh) * h) for x, y, rw, rh in spec["rects"]]


def choose(windows, boxes, limit=MAX_WINDOWS):
    """The windows (paint order kept) overlapping any box; the topmost `limit`."""
    def hits(rect):
        x, y, rw, rh = rect
        return any(x < bx1 and x + rw > bx0 and y < by1 and y + rh > by0
                   for bx0, by0, bx1, by1 in boxes)
    return [win for win in windows if hits(win["rect"])][-limit:]


def resize_nearest(img, w, h):
    ys = np.minimum(((np.arange(h) + 0.5) * img.shape[0] / h).astype(int), img.shape[0] - 1)
    xs = np.minimum(((np.arange(w) + 0.5) * img.shape[1] / w).astype(int), img.shape[1] - 1)
    return img[ys][:, xs]


def paste(picture, img, rect, opacity=1.0):
    """Paste `img` (RGB, or RGBA blended by its alpha) scaled to rect (x, y, w,
    h in picture px) at `opacity`, clipped to the picture. Hyprland's blur
    behind translucent windows is not modelled."""
    x, y, rw, rh = (int(round(v)) for v in rect)
    if rw <= 0 or rh <= 0:
        return
    H, W = picture.shape[:2]
    x0, y0, x1, y1 = max(0, x), max(0, y), min(W, x + rw), min(H, y + rh)
    if x0 >= x1 or y0 >= y1:
        return
    tile = resize_nearest(img, rw, rh)[y0 - y:y1 - y, x0 - x:x1 - x]
    alpha = tile[..., 3:4] / 255.0 * opacity if tile.shape[2] == 4 else np.full(tile.shape[:2] + (1,), opacity)
    if (alpha >= 1.0).all():
        picture[y0:y1, x0:x1] = tile[..., :3]
        return
    under = picture[y0:y1, x0:x1].astype(np.float64)
    picture[y0:y1, x0:x1] = np.rint(alpha * tile[..., :3] + (1 - alpha) * under).astype(np.uint8)


def wallpaper_base(path, size, run=subprocess.run):
    """The wallpaper center-cropped to fill `size` (w, h) as uint8 (awww's
    default framing); black when there is none or it can't be decoded."""
    w, h = size
    if path:
        try:
            result = run(["magick", path + "[0]", "-resize", f"{w}x{h}^", "-gravity", "center",
                          "-extent", f"{w}x{h}", "-depth", "8", "ppm:-"],
                         capture_output=True, timeout=5)
            img = capture.parse_ppm(result.stdout) if result.returncode == 0 else None
            if img is not None and img.shape[:2] == (h, w):
                return img.copy()
        except (OSError, subprocess.SubprocessError):
            pass
    return np.zeros((h, w, 3), np.uint8)
