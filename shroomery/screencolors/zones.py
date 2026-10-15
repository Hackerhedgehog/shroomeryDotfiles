"""Letterbox/pillarbox detection: the near-black bars around a video."""
import numpy as np

DARK_LUMA = 16      # 0..255: rows/columns darker than this are letterbox bars
MAX_CROP = 0.25     # never crop more than this fraction from one side

_LUMA = np.array([0.2126, 0.7152, 0.0722])


def _leading_true(flags, limit):
    n = 0
    while n < limit and n < len(flags) and flags[n]:
        n += 1
    return n


def letterbox_box(img):
    """(top, bottom, left, right) near-black bars to trim from a (H, W, 3) uint8
    frame: rows/columns whose 98th-percentile luma is below DARK_LUMA, at most
    MAX_CROP of each dimension per side; an all-dark frame trims nothing."""
    h, w = img.shape[:2]
    luma = img[..., :3].astype(np.float64) @ _LUMA
    dark_rows = np.percentile(luma, 98, axis=1) < DARK_LUMA
    dark_cols = np.percentile(luma, 98, axis=0) < DARK_LUMA
    if dark_rows.all() or dark_cols.all():
        return 0, 0, 0, 0
    return (_leading_true(dark_rows, int(h * MAX_CROP)), _leading_true(dark_rows[::-1], int(h * MAX_CROP)),
            _leading_true(dark_cols, int(w * MAX_CROP)), _leading_true(dark_cols[::-1], int(w * MAX_CROP)))


def crop_letterbox(img):
    """Trim near-black bars (letterbox/pillarbox) from a (H, W, 3) uint8 frame."""
    h, w = img.shape[:2]
    top, bottom, left, right = letterbox_box(img)
    return img[top:h - bottom, left:w - right]
