"""Copy the installed runtime dependencies' license texts into a release."""

from __future__ import annotations

import argparse
import importlib.metadata
import shutil
import sys
from pathlib import Path


def installed_license(distribution_name: str, filename: str) -> tuple[Path, str]:
    distribution = importlib.metadata.distribution(distribution_name)
    matches = [
        distribution.locate_file(entry)
        for entry in distribution.files or ()
        if Path(entry).name.lower() == filename.lower()
        and "licenses" in [part.lower() for part in Path(entry).parts]
    ]
    if len(matches) != 1 or not matches[0].is_file():
        raise RuntimeError(f"Could not locate {distribution_name} {filename} in installed metadata")
    return matches[0], distribution.version


def python_license() -> Path:
    prefix = Path(sys.base_prefix)
    version_dir = f"python{sys.version_info.major}.{sys.version_info.minor}"
    candidates = (
        prefix / "lib" / version_dir / "LICENSE.txt",
        prefix / "Lib" / "LICENSE.txt",
        prefix / "LICENSE.txt",
        prefix / "LICENSE",
    )
    for candidate in candidates:
        if candidate.is_file():
            return candidate
    raise RuntimeError(f"Could not locate the Python license under {prefix}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output_dir", type=Path)
    args = parser.parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=True)

    pillow_license, pillow_version = installed_license("Pillow", "LICENSE")
    pyinstaller_license, pyinstaller_version = installed_license("PyInstaller", "COPYING.txt")
    files = {
        "Python-LICENSE.txt": python_license(),
        "Pillow-LICENSE.txt": pillow_license,
        "PyInstaller-COPYING.txt": pyinstaller_license,
    }
    for name, source in files.items():
        shutil.copyfile(source, args.output_dir / name)

    (args.output_dir / "RUNTIME-NOTICE.txt").write_text(
        "This package bundles CPython "
        f"{sys.version.split()[0]}, Pillow {pillow_version}, and a PyInstaller "
        f"{pyinstaller_version} bootloader. Their license texts are copied "
        "from the installed build dependencies into this directory. "
        "The Cadillac Wallpaper Desktop project license does not replace "
        "these third-party terms.\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
