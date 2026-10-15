import unittest

import numpy as np

from screencolors import zones

GRAY = 120


def frame(h, w, value=GRAY):
    return np.full((h, w, 3), value, dtype=np.uint8)


class CropTest(unittest.TestCase):
    def test_letterbox_rows_are_cropped(self):
        img = frame(90, 160)
        img[:15] = 0
        img[75:] = 0
        self.assertEqual(zones.crop_letterbox(img).shape[:2], (60, 160))

    def test_pillarbox_columns_are_cropped(self):
        img = frame(90, 160)
        img[:, :20] = 0
        img[:, 140:] = 0
        self.assertEqual(zones.crop_letterbox(img).shape[:2], (90, 120))

    def test_all_black_frame_is_kept(self):
        img = frame(90, 160, 0)
        self.assertEqual(zones.crop_letterbox(img).shape[:2], (90, 160))

    def test_crop_is_capped_per_side(self):
        img = frame(90, 160, 0)
        img[40:50] = GRAY
        # int(90 * 0.25) = 22 rows at most from each side
        self.assertEqual(zones.crop_letterbox(img).shape[:2], (46, 160))


if __name__ == "__main__":
    unittest.main()
