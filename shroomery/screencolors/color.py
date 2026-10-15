"""Color conversions: sRGB <-> linear light <-> OKLab, hex strings and ΔE.

Arrays are shaped (..., 3) with channels in 0..1 (OKLab: L 0..1, a and b
roughly -0.4..0.4). OKLab is used because equal distances in it look equally
different, so fades between colors don't pass through muddy grey.
"""
import numpy as np

_LMS_FROM_LINEAR = np.array([
    [0.4122214708, 0.5363325363, 0.0514459929],
    [0.2119034982, 0.6806995451, 0.1073969566],
    [0.0883024619, 0.2817188376, 0.6299787005],
])
_OKLAB_FROM_LMS = np.array([
    [0.2104542553, 0.7936177850, -0.0040720468],
    [1.9779984951, -2.4285922050, 0.4505937099],
    [0.0259040371, 0.7827717662, -0.8086757660],
])
_LMS_FROM_OKLAB = np.array([
    [1.0, 0.3963377774, 0.2158037573],
    [1.0, -0.1055613458, -0.0638541728],
    [1.0, -0.0894841775, -1.2914855480],
])
_LINEAR_FROM_LMS = np.array([
    [4.0767416621, -3.3077115913, 0.2309699292],
    [-1.2684380046, 2.6097574011, -0.3413193965],
    [-0.0041960863, -0.7034186147, 1.7076147010],
])


def srgb_to_linear(srgb):
    c = np.asarray(srgb, dtype=np.float64)
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def linear_to_srgb(linear):
    c = np.clip(np.asarray(linear, dtype=np.float64), 0.0, 1.0)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * np.power(c, 1 / 2.4) - 0.055)


def linear_to_oklab(linear):
    lms = np.asarray(linear, dtype=np.float64) @ _LMS_FROM_LINEAR.T
    return np.cbrt(lms) @ _OKLAB_FROM_LMS.T


def oklab_to_linear(lab):
    lms = (np.asarray(lab, dtype=np.float64) @ _LMS_FROM_OKLAB.T) ** 3
    return lms @ _LINEAR_FROM_LMS.T


def to_hex(srgb):
    """(N, 3) sRGB 0..1 -> ["#rrggbb", ...]."""
    values = np.clip(np.rint(np.asarray(srgb, dtype=np.float64) * 255), 0, 255).astype(int)
    return ["#%02x%02x%02x" % tuple(v) for v in values.reshape(-1, 3)]


def from_hex(colors):
    """["#rrggbb", ...] -> (N, 3) sRGB 0..1."""
    return np.array([[int(c[i:i + 2], 16) / 255 for i in (1, 3, 5)] for c in colors],
                    dtype=np.float64)


def delta_e(lab_a, lab_b):
    """OKLab distance per row: about 0.4 between opposite hues, 1.0 black to white."""
    return np.linalg.norm(np.asarray(lab_a) - np.asarray(lab_b), axis=-1)
