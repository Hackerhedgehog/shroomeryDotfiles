import unittest

import numpy as np

from screencolors import smoothing
from screencolors.color import delta_e

A = np.array([[0.0, 0.0, 0.0]])


def lab(l_value):
    return np.array([[l_value, 0.0, 0.0]])


def ms_to_95(smoother, start, end, step_ms=10):
    total = 0
    full = float(delta_e(start, end)[0])
    while float(delta_e(smoother.step(step_ms), end)[0]) > 0.05 * full:
        total += step_ms
        if total > 10000:
            raise AssertionError("never converged")
    return total + step_ms


class SmoothingTest(unittest.TestCase):
    def test_step_before_any_sample_is_none(self):
        self.assertIsNone(smoothing.ZoneSmoother().step(33))

    def test_first_sample_is_taken_immediately(self):
        s = smoothing.ZoneSmoother()
        s.sample(lab(0.5))
        np.testing.assert_allclose(s.step(33), lab(0.5))

    def test_dead_zone_ignores_small_changes(self):
        s = smoothing.ZoneSmoother()
        s.sample(A)
        s.sample(lab(0.01))
        s.sample(lab(0.01))
        np.testing.assert_allclose(s.target, A)

    def test_single_flash_is_ignored(self):
        s = smoothing.ZoneSmoother()
        for sample in (A, A, lab(0.9), A, A):
            s.sample(sample)
        np.testing.assert_allclose(s.target, A)
        np.testing.assert_allclose(s.step(1000), A)

    def test_two_agreeing_samples_become_the_target(self):
        s = smoothing.ZoneSmoother()
        for sample in (A, lab(0.9), lab(0.9)):
            s.sample(sample)
        np.testing.assert_allclose(s.target, lab(0.9))

    def test_big_change_reaches_95_percent_in_about_500_ms(self):
        s = smoothing.ZoneSmoother()
        for sample in (A, lab(0.4), lab(0.4)):
            s.sample(sample)
        self.assertTrue(480 <= ms_to_95(s, A, lab(0.4)) <= 520)

    def test_small_change_reaches_95_percent_in_about_1800_ms(self):
        s = smoothing.ZoneSmoother()
        for sample in (A, lab(0.05), lab(0.05)):
            s.sample(sample)
        # fade = 2000 + (500 - 2000) * (0.05 / 0.4) = 1812.5 ms
        self.assertTrue(1780 <= ms_to_95(s, A, lab(0.05)) <= 1840)

    def test_retarget_does_not_jump(self):
        s = smoothing.ZoneSmoother()
        for sample in (A, lab(0.8), lab(0.8)):
            s.sample(sample)
        before = s.step(100)
        s.sample(lab(0.2))
        s.sample(lab(0.2))
        np.testing.assert_allclose(s.current, before)
        np.testing.assert_allclose(s.target, lab(0.2))

    def test_zone_count_change_resets(self):
        s = smoothing.ZoneSmoother()
        s.sample(np.zeros((3, 3)))
        s.sample(np.full((4, 3), 0.5))
        np.testing.assert_allclose(s.step(1), np.full((4, 3), 0.5))

    def test_fade_ms_bounds(self):
        self.assertEqual(float(smoothing.fade_ms(0.0)), 2000.0)
        self.assertEqual(float(smoothing.fade_ms(0.4)), 500.0)
        self.assertEqual(float(smoothing.fade_ms(1.0)), 500.0)


if __name__ == "__main__":
    unittest.main()
