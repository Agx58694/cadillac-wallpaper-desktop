#!/usr/bin/env python3
"""Exercise the actual packaged Windows CLI with crop and native inputs."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import zipfile

from PIL import Image, ImageOps


def sha256(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", required=True, type=Path)
    parser.add_argument("--work", required=True, type=Path)
    args = parser.parse_args()
    work = args.work.resolve()
    work.mkdir(parents=True, exist_ok=False)
    extracted = work / "extracted"
    with zipfile.ZipFile(args.archive) as archive:
        if archive.testzip() is not None:
            raise ValueError("Release archive CRC check failed")
        archive.extractall(extracted)
    cli = extracted / "packager_runtime/cadillac_wallpaper_packager.exe"
    resources = extracted / "data/flutter_assets/packager"
    sizes = {"light": (4096, 2048), "dark": (10000, 1000)}
    for label, size in sizes.items():
        gradient = Image.linear_gradient("L")
        if label == "dark":
            gradient = gradient.transpose(Image.Transpose.ROTATE_90)
        ImageOps.colorize(gradient.resize(size), "#132d40", "#b3ced3").save(work / f"{label}.png")

    reports = {}
    for mode in ("crop", "native"):
        output = work / f"{mode}.zip"
        report_path = work / f"{mode}-report.json"
        if mode == "crop":
            masters = [work / f"{label}.png" for label in ("light", "dark")]
        else:
            masters = [work / "crop-work" / f"cropped_{label}_8960x1320.png" for label in ("light", "dark")]
        subprocess.run([
            str(cli), "--light-image", str(masters[0]), "--dark-image", str(masters[1]),
            "--source-mode", mode, "--light-crop-x", "0.25", "--light-crop-y", "0.75",
            "--dark-crop-x", "0.8", "--dark-crop-y", "0.2",
            "--input-zip", str(resources / "templates/BFA3A0F4596C4C57A6BCDC1EB3348932.zip"),
            "--astcenc", str(resources / "tools/windows/astcenc.exe"),
            "--light-dim-mask", str(resources / "masks/light_dim_alpha_fixed_smoothed_used.png"),
            "--dark-dim-mask", str(resources / "masks/dark_dim_alpha_fixed_smoothed_used.png"),
            "--output-zip", str(output), "--work-dir", str(work / f"{mode}-work"),
            "--report", str(report_path), "--theme-key", f"release_{mode}_check",
        ], check=True)
        report = json.loads(report_path.read_text(encoding="utf-8"))
        assert report["input_mode"] == mode
        assert report["source_mode"] == "native" and report["source_size"] == [8960, 1320]
        assert report["zip_structure_valid"] and report["zip_file_count"] == 9
        assert report["zip_test_bad_file"] is None
        assert report["decoded_kzb"]["stitch"]
        assert report["vehicle_runtime_verified"] is False
        if mode == "crop":
            assert report["input_sizes"] == {label: list(size) for label, size in sizes.items()}
            assert report["crop_positions"] == {"light": [0.25, 0.75], "dark": [0.8, 0.2]}
            for label in sizes:
                with Image.open(work / "crop-work" / f"cropped_{label}_8960x1320.png") as master:
                    assert master.size == (8960, 1320)
                    assert master.getchannel("A").getextrema() == (255, 255)
        with zipfile.ZipFile(output) as archive:
            assert archive.testzip() is None
            assert len([entry for entry in archive.infolist() if not entry.is_dir()]) == 9
        reports[mode] = {"zip_sha256": sha256(output), "wallpaper_root": report["wallpaper_root"]}
    assert reports["crop"]["wallpaper_root"] != reports["native"]["wallpaper_root"]
    summary = {"passed": True, "release_archive_sha256": sha256(args.archive), "packages": reports, "vehicle_runtime_verified": False}
    (work / "release-smoke-report.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
