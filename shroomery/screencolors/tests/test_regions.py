import unittest

import numpy as np

from screencolors import regions
from screencolors.color import srgb_to_linear

MONS = ["DP-2", "HDMI-A-1"]


def ring(**kw):
    spec = {"id": "viz", "shape": "ring", "cx": 0.5, "cy": 0.5, "inner": 0.1, "outer": 0.4, "sectors": 8}
    spec.update(kw)
    return spec


def edges(**kw):
    spec = {"id": "tv", "shape": "edges", "top": 4, "right": 2, "bottom": 4, "left": 2, "depth": 0.2}
    spec.update(kw)
    return spec


def sub(*regs, monitor="DP-2", source="screen"):
    return {"v": 2, "type": "subscribe", "monitor": monitor, "source": source, "regions": list(regs)}


def lin(img):
    return srgb_to_linear(img / 255.0)


class ValidateTest(unittest.TestCase):
    def test_valid_subscription(self):
        s = regions.validate_subscription(sub(ring(), edges(), {"id": "lamp", "shape": "rects",
                                                                 "rects": [[0, 0.4, 0.05, 0.2]]}), MONS)
        self.assertEqual((s["monitor"], s["source"], len(s["regions"])), ("DP-2", "screen", 3))
        self.assertEqual(s["regions"][2]["rects"], [(0.0, 0.4, 0.05, 0.2)])
        self.assertEqual(regions.validate_subscription(sub(ring(), source="wallpaper"), MONS)["source"], "wallpaper")

    def test_rejections(self):
        bad = [
            sub(ring(), monitor="DP-9"),
            sub(ring(), source="video"),
            sub(),
            sub(*[ring(id=str(i)) for i in range(9)]),
            sub(ring(), ring()),                                  # duplicate ids
            sub(ring(id="")),
            sub(ring(sectors=3)), sub(ring(sectors=361)), sub(ring(sectors=8.5)),
            sub(ring(inner=0.4, outer=0.4)), sub(ring(outer=2.5)), sub(ring(cx=1.2)),
            sub(ring(cx=True)),
            sub(edges(top=0)), sub(edges(left=201)), sub(edges(depth=0.6)),
            sub({"id": "r", "shape": "rects", "rects": []}),
            sub({"id": "r", "shape": "rects", "rects": [[0.9, 0, 0.2, 0.1]]}),
            sub({"id": "r", "shape": "rects", "rects": [[0, 0, 0, 0.1]]}),
            sub({"id": "r", "shape": "blob"}),
        ]
        for msg in bad:
            with self.assertRaises(regions.SubscriptionError, msg=str(msg)):
                regions.validate_subscription(msg, MONS)

    def test_zone_count(self):
        self.assertEqual(regions.zone_count(ring(sectors=72)), 72)
        self.assertEqual(regions.zone_count(edges()), 12)


class LayoutTest(unittest.TestCase):
    def test_ring_sectors_clockwise_from_twelve(self):
        labels = regions.ring_labels(ring(sectors=4, inner=0, outer=1), 100, 100)
        self.assertEqual(labels[10, 55], 0)    # just right of 12 o'clock
        self.assertEqual(labels[45, 90], 0)    # just above 3 o'clock
        self.assertEqual(labels[55, 90], 1)    # just below 3 o'clock
        self.assertEqual(labels[90, 45], 2)    # just left of 6 o'clock
        self.assertEqual(labels[45, 10], 3)    # just above 9 o'clock

    def test_ring_is_round_on_a_wide_picture(self):
        labels = regions.ring_labels(ring(inner=0.2, outer=0.3), 210, 90)   # short side 90
        self.assertGreaterEqual(labels[45, 105 + 22], 0)   # 0.25 · 90 to the right
        self.assertGreaterEqual(labels[45 - 22, 105], 0)   # same distance up
        self.assertEqual(labels[45, 105 + 32], -1)         # 0.35: outside
        self.assertEqual(labels[45, 105], -1)              # the middle: inside `inner`

    def test_ring_bigger_than_picture(self):
        labels = regions.ring_labels(ring(inner=0, outer=2), 20, 10)
        self.assertTrue((labels >= 0).all())

    def test_edges_order(self):
        labels = regions.edges_labels(edges(), 40, 20)      # depth round(0.2 · 20) = 4
        self.assertEqual(labels[0, 0], 0)       # top band, left end
        self.assertEqual(labels[0, 39], 3)      # top band, right end
        self.assertEqual(labels[5, 39], 4)      # right side, upper half
        self.assertEqual(labels[12, 39], 5)     # right side, lower half
        self.assertEqual(labels[19, 39], 6)     # bottom band starts on the right
        self.assertEqual(labels[19, 0], 9)      # and ends on the left
        self.assertEqual(labels[12, 0], 10)     # left side, lower half first
        self.assertEqual(labels[5, 0], 11)
        self.assertEqual(labels[10, 20], -1)    # the middle

    def test_rect_boxes_at_least_one_pixel(self):
        spec = {"id": "r", "shape": "rects", "rects": [(0.999, 0.999, 0.001, 0.001), (0, 0, 0.5, 1)]}
        self.assertEqual(regions.rect_boxes(spec, 10, 10), [(9, 9, 10, 10), (0, 0, 5, 10)])

    def test_cache_reuses_maps(self):
        cache = regions.LabelCache()
        self.assertIs(cache.labels(ring(), 30, 20), cache.labels(ring(), 30, 20))


class SampleTest(unittest.TestCase):
    def setUp(self):
        self.img = np.zeros((100, 100, 3), dtype=np.uint8)
        self.img[:, :50, 0] = 255     # left red
        self.img[:, 50:, 2] = 255     # right blue
        self.cache = regions.LabelCache()

    def test_ring_colors_by_sector(self):
        z, avg = regions.sample(ring(sectors=4, inner=0.1, outer=0.45), self.img, lin(self.img), self.cache)
        np.testing.assert_allclose(z[0], [0, 0, 1])
        np.testing.assert_allclose(z[1], [0, 0, 1])
        np.testing.assert_allclose(z[2], [1, 0, 0])
        np.testing.assert_allclose(z[3], [1, 0, 0])
        np.testing.assert_allclose(avg, [0.5, 0, 0.5], atol=0.02)

    def test_edges_letterbox_crop_and_black_frame_same_count(self):
        boxed = self.img.copy()
        boxed[:15] = 0
        boxed[85:] = 0
        spec = edges(top=2, right=1, bottom=2, left=1, depth=0.1)
        z, _ = regions.sample(spec, boxed, lin(boxed), self.cache)
        np.testing.assert_allclose(z[0], [1, 0, 0])     # top-left zone: the picture, not the black bar
        np.testing.assert_allclose(z[1], [0, 0, 1])
        black = np.zeros_like(boxed)
        zb, _ = regions.sample(spec, black, lin(black), self.cache)
        self.assertEqual(len(zb), len(z))

    def test_rects_overlap_each_their_own(self):
        spec = {"id": "r", "shape": "rects", "rects": [(0, 0, 1, 1), (0.5, 0, 0.5, 1)]}
        z, avg = regions.sample(spec, self.img, lin(self.img), self.cache)
        np.testing.assert_allclose(z[0], [0.5, 0, 0.5])
        np.testing.assert_allclose(z[1], [0, 0, 1])
        np.testing.assert_allclose(avg, [1 / 3, 0, 2 / 3])   # 100·100 px half/half + 50·100 px blue

    def test_empty_zones_take_a_neighbor(self):
        green = np.zeros((20, 20, 3), dtype=np.uint8)
        green[..., 1] = 255
        z, _ = regions.sample(ring(sectors=360, inner=0.05, outer=0.1), green, lin(green), self.cache)
        self.assertEqual(len(z), 360)
        np.testing.assert_allclose(z, np.tile([0, 1, 0], (360, 1)))

    def test_pattern_picture_directions(self):
        p = regions.pattern_picture(40, 20)
        self.assertEqual(tuple(p[1, 20]), (255, 0, 0))      # up: red
        self.assertEqual(tuple(p[10, 39]), (0, 255, 0))     # right: green
        self.assertEqual(tuple(p[18, 20]), (0, 0, 255))     # down: blue
        self.assertEqual(tuple(p[10, 0]), (255, 255, 0))    # left: yellow


if __name__ == "__main__":
    unittest.main()
