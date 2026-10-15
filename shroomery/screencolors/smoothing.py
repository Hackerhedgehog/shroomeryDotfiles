"""Per-zone color smoothing in OKLab (README.md section 4).

1. Dead zone: changes of at most DEADBAND are noise.
2. Flash filter: a new color must show up in two samples in a row (within
   AGREE of each other) before a zone follows it.
3. Fade length: fade_ms(ΔE), from SLOW_MS for similar colors to FAST_MS for
   opposite ones.
4. Motion: exponential approach with tau = fade / 3 (95% at the fade
   length); a new target mid-fade carries on from the current color.
"""
import numpy as np

from screencolors.color import delta_e

DEADBAND = 0.02
AGREE = 0.08
SLOW_MS = 2000.0
FAST_MS = 500.0
FULL_DELTA = 0.4


def fade_ms(delta):
    t = np.clip(np.asarray(delta, dtype=np.float64) / FULL_DELTA, 0.0, 1.0)
    return SLOW_MS + (FAST_MS - SLOW_MS) * t


class ZoneSmoother:
    """sample() at the capture rate, step() at the publish rate."""

    def __init__(self):
        self.current = None
        self.target = None
        self.tau = None
        self.previous = None

    def sample(self, lab):
        lab = np.asarray(lab, dtype=np.float64)
        if self.current is None or self.current.shape != lab.shape:
            self.current = lab.copy()
            self.target = lab.copy()
            self.tau = np.full(len(lab), SLOW_MS / 3)
            self.previous = lab.copy()
            return
        previous, self.previous = self.previous, lab.copy()
        moved = (delta_e(lab, self.target) > DEADBAND) & (delta_e(lab, previous) <= AGREE)
        if not moved.any():
            return
        self.target[moved] = lab[moved]
        self.tau[moved] = fade_ms(delta_e(self.target[moved], self.current[moved])) / 3

    def step(self, dt_ms):
        if self.current is None:
            return None
        k = 1.0 - np.exp(-float(dt_ms) / self.tau)
        self.current += (self.target - self.current) * k[:, None]
        return self.current.copy()
