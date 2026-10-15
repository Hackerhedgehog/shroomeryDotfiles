import unittest

import numpy as np

from screencolors import color


class ColorTest(unittest.TestCase):
    def test_srgb_linear_known_value(self):
        self.assertAlmostEqual(float(color.srgb_to_linear(0.5)), 0.21404, places=4)

    def test_srgb_linear_round_trip(self):
        values = np.linspace(0, 1, 101)
        back = color.linear_to_srgb(color.srgb_to_linear(values))
        np.testing.assert_allclose(back, values, atol=1e-9)

    def test_white_and_black_in_oklab(self):
        lab = color.linear_to_oklab(np.array([[1.0, 1.0, 1.0], [0.0, 0.0, 0.0]]))
        np.testing.assert_allclose(lab[0], [1.0, 0.0, 0.0], atol=1e-3)
        np.testing.assert_allclose(lab[1], [0.0, 0.0, 0.0], atol=1e-9)

    def test_oklab_round_trip(self):
        rng = np.random.default_rng(1)
        linear = rng.random((50, 3))
        back = color.oklab_to_linear(color.linear_to_oklab(linear))
        np.testing.assert_allclose(back, linear, atol=1e-6)

    def test_hex_round_trip(self):
        colors = ["#000000", "#ff8000", "#ffffff", "#1a2b3c"]
        self.assertEqual(color.to_hex(color.from_hex(colors)), colors)

    def test_delta_e_scale(self):
        def lab(hex_color):
            return color.linear_to_oklab(color.srgb_to_linear(color.from_hex([hex_color])))[0]
        self.assertAlmostEqual(float(color.delta_e(lab("#000000"), lab("#ffffff"))), 1.0, places=2)
        self.assertGreater(float(color.delta_e(lab("#ff0000"), lab("#00ffff"))), 0.4)


if __name__ == "__main__":
    unittest.main()
