"""Input and geometry checks for the two-image desktop packaging path."""

from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import cadillac_wallpaper_packager as packager


class NativeImageTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        packager.load_runtime_dependencies()

    def test_native_size_and_opacity_are_required(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "input.png"
            Image.new("RGB", (8920, 1320), (12, 34, 56)).save(path)
            with self.assertRaisesRegex(ValueError, "8960, 1320"):
                packager.load_native_master(path, "light")
            Image.new("RGBA", packager.NATIVE_SIZE, (12, 34, 56, 0)).save(path)
            with self.assertRaisesRegex(ValueError, "fully opaque"):
                packager.load_native_master(path, "light")

    def test_aspect_fit_crops_instead_of_stretching(self):
        source = Image.new("RGB", (200, 100), (0, 0, 0))
        source.paste((255, 0, 0), (50, 0, 150, 100))
        result = packager.fit_without_distortion(source, (100, 100))
        self.assertEqual(result.size, (100, 100))
        self.assertEqual(result.getpixel((0, 50))[:3], (255, 0, 0))
        self.assertEqual(result.getpixel((99, 50))[:3], (255, 0, 0))

    def test_publish_refuses_to_replace_a_different_existing_package(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            candidate = folder / "candidate.zip"
            destination = folder / "output.zip"
            candidate.write_bytes(b"new verified bytes")
            destination.write_bytes(b"existing user bytes")
            with self.assertRaises(FileExistsError):
                packager.publish_verified_zip(candidate, destination)
            self.assertEqual(destination.read_bytes(), b"existing user bytes")
            self.assertEqual(list(folder.glob(".ota-*.tmp")), [])


if __name__ == "__main__":
    unittest.main()
