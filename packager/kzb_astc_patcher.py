#!/usr/bin/env python3
"""Patch Cadillac Kanzi KZB wallpaper ASTC payloads in-place."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import shutil
import struct
import subprocess
import tempfile
import zipfile
from dataclasses import dataclass
from pathlib import Path

from PIL import Image, ImageFilter


KZB_TEXTURE_HEADER = struct.pack("<8I", 8960, 1320, 0, 0, 2, 65, 1, 2_956_800)
KZB_TEXTURE_WIDTH = 8960
KZB_TEXTURE_HEIGHT = 1320
KZB_TEXTURE_PAYLOAD_SIZE = 2_956_800
KZB_TEXTURE_BLOCK_SIZE = "8x8"
KZB_VCD_JOIN_X = 5010
VCD_TEXTURE_WIDTH = 3950
VCD_TEXTURE_HEIGHT = 1320
LIGHT_VCD_PREVIEW_CROP = (1256, 48, 2196, 362)
DARK_VCD_PREVIEW_CROP = (1260, 20, 2200, 334)
KZB_TEXTURE_PATH_SUFFIX = (
    "ipd/wallpaper/cadi_wallpaper_football0c2enliifml.kzb"
)


@dataclass(frozen=True)
class TextureRecord:
    index: int
    header_offset: int
    payload_start: int
    payload_end: int
    md5: str


def find_wallpaper_root(names: list[str]) -> str:
    suffix = "/cadi_wallpaper05111930/"
    for name in names:
        if suffix in name:
            return name.split(suffix, 1)[0] + suffix.rstrip("/")
    raise ValueError("could not find cadi_wallpaper05111930 root in input zip")


def find_texture_records(kzb: bytes) -> list[TextureRecord]:
    records: list[TextureRecord] = []
    start = 0
    while True:
        offset = kzb.find(KZB_TEXTURE_HEADER, start)
        if offset < 0:
            break
        payload_start = offset + len(KZB_TEXTURE_HEADER)
        payload_end = payload_start + KZB_TEXTURE_PAYLOAD_SIZE
        if payload_end > len(kzb):
            raise ValueError(f"texture record at {offset:#x} exceeds KZB size")
        payload = kzb[payload_start:payload_end]
        records.append(
            TextureRecord(
                index=len(records),
                header_offset=offset,
                payload_start=payload_start,
                payload_end=payload_end,
                md5=hashlib.md5(payload).hexdigest(),
            )
        )
        start = offset + 1
    if len(records) != 7:
        raise ValueError(f"expected 7 ASTC texture records, found {len(records)}")
    return records


def cover_resize(
    source: Image.Image,
    size: tuple[int, int],
    focus: tuple[float, float],
) -> Image.Image:
    target_width, target_height = size
    image = source.convert("RGBA")
    scale = max(target_width / image.width, target_height / image.height)
    resized = image.resize(
        (math.ceil(image.width * scale), math.ceil(image.height * scale)),
        Image.Resampling.LANCZOS,
    )
    overflow_x = resized.width - target_width
    overflow_y = resized.height - target_height
    focus_x = min(1.0, max(0.0, focus[0]))
    focus_y = min(1.0, max(0.0, focus[1]))
    left = round(overflow_x * focus_x)
    top = round(overflow_y * focus_y)
    return resized.crop((left, top, left + target_width, top + target_height))


def compose_full_texture(source: Image.Image, focus: tuple[float, float]) -> Image.Image:
    return cover_resize(
        source,
        (KZB_TEXTURE_WIDTH, KZB_TEXTURE_HEIGHT),
        focus,
    ).convert("RGB")


def edge_pad_for_bbox(
    source: Image.Image,
    bbox: tuple[float, float, float, float],
) -> tuple[Image.Image, tuple[float, float, float, float]]:
    left, top, right, bottom = bbox
    pad_left = math.ceil(max(0.0, -left))
    pad_top = math.ceil(max(0.0, -top))
    pad_right = math.ceil(max(0.0, right - source.width))
    pad_bottom = math.ceil(max(0.0, bottom - source.height))
    if not any((pad_left, pad_top, pad_right, pad_bottom)):
        return source, bbox

    width, height = source.size
    padded = Image.new(
        source.mode,
        (width + pad_left + pad_right, height + pad_top + pad_bottom),
    )
    padded.paste(source, (pad_left, pad_top))
    if pad_top:
        top_row = source.crop((0, 0, width, 1)).resize((width, pad_top))
        padded.paste(top_row, (pad_left, 0))
    if pad_bottom:
        bottom_row = source.crop((0, height - 1, width, height)).resize(
            (width, pad_bottom)
        )
        padded.paste(bottom_row, (pad_left, pad_top + height))
    if pad_left:
        left_col = padded.crop((pad_left, 0, pad_left + 1, padded.height)).resize(
            (pad_left, padded.height)
        )
        padded.paste(left_col, (0, 0))
    if pad_right:
        right_col = padded.crop(
            (pad_left + width - 1, 0, pad_left + width, padded.height)
        ).resize((pad_right, padded.height))
        padded.paste(right_col, (pad_left + width, 0))

    shifted_bbox = (
        left + pad_left,
        top + pad_top,
        right + pad_left,
        bottom + pad_top,
    )
    return padded, shifted_bbox


def compose_full_texture_from_vcd_mapping(
    source: Image.Image,
    vcd_preview_crop: tuple[int, int, int, int],
) -> Image.Image:
    left, top, right, bottom = vcd_preview_crop
    source_width = (right - left) / VCD_TEXTURE_WIDTH
    source_height = (bottom - top) / VCD_TEXTURE_HEIGHT
    full_bbox = (
        left - KZB_VCD_JOIN_X * source_width,
        top,
        right,
        bottom,
    )
    padded_source, padded_bbox = edge_pad_for_bbox(source.convert("RGBA"), full_bbox)
    return padded_source.transform(
        (KZB_TEXTURE_WIDTH, KZB_TEXTURE_HEIGHT),
        Image.Transform.EXTENT,
        padded_bbox,
        Image.Resampling.BICUBIC,
    ).convert("RGB")


def apply_original_alpha(source: Image.Image, alpha: Image.Image) -> Image.Image:
    result = source.convert("RGBA")
    result.putalpha(alpha.convert("L"))
    return result


def load_source(path: Path, blur_radius: float = 0) -> Image.Image:
    with Image.open(path) as image:
        result = image.convert("RGBA")
    if blur_radius:
        result = result.filter(ImageFilter.GaussianBlur(radius=blur_radius))
    return result


def make_dim_variant(source: Image.Image, is_dark: bool) -> Image.Image:
    blurred = source.convert("RGBA").filter(ImageFilter.GaussianBlur(radius=30))
    if is_dark:
        overlay = Image.new("RGBA", blurred.size, (0, 0, 0, 96))
    else:
        overlay = Image.new("RGBA", blurred.size, (232, 242, 250, 54))
    return Image.alpha_composite(blurred, overlay)


def astc_header() -> bytes:
    return (
        bytes([0x13, 0xAB, 0xA1, 0x5C, 8, 8, 1])
        + KZB_TEXTURE_WIDTH.to_bytes(3, "little")
        + KZB_TEXTURE_HEIGHT.to_bytes(3, "little")
        + (1).to_bytes(3, "little")
    )


def decode_record_payload(
    astcenc: Path,
    payload: bytes,
    astc_path: Path,
    png_path: Path,
) -> Image.Image:
    astc_path.write_bytes(astc_header() + payload)
    subprocess.run(
        [str(astcenc), "-dl", str(astc_path), str(png_path), "-silent"],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    return Image.open(png_path).convert("RGBA")


def build_half_alphas(
    astcenc: Path,
    output_dir: Path,
    kzb: bytes,
    records: list[TextureRecord],
) -> dict[int, Image.Image]:
    output_dir.mkdir(parents=True, exist_ok=True)
    alphas: dict[int, Image.Image] = {}
    for index in (1, 2, 4, 5):
        record = records[index]
        payload = kzb[record.payload_start : record.payload_end]
        decoded = decode_record_payload(
            astcenc=astcenc,
            payload=payload,
            astc_path=output_dir / f"source_record{index}.astc",
            png_path=output_dir / f"source_record{index}.png",
        )
        alphas[index] = decoded.getchannel("A")
        alphas[index].save(output_dir / f"source_record{index}_alpha.png")
    return alphas


def save_storage_orientation(image: Image.Image, output: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    storage = image.transpose(Image.Transpose.FLIP_TOP_BOTTOM)
    storage.save(output)


def encode_astc_payload(
    astcenc: Path,
    source_png: Path,
    output_astc: Path,
    quality: str,
) -> bytes:
    subprocess.run(
        [
            str(astcenc),
            "-cl",
            str(source_png),
            str(output_astc),
            KZB_TEXTURE_BLOCK_SIZE,
            quality,
            "-silent",
        ],
        check=True,
    )
    astc = output_astc.read_bytes()
    payload = astc[16:]
    if len(payload) != KZB_TEXTURE_PAYLOAD_SIZE:
        raise ValueError(
            f"{output_astc} payload is {len(payload)}, expected {KZB_TEXTURE_PAYLOAD_SIZE}"
        )
    return payload


def build_payloads(
    astcenc: Path,
    output_dir: Path,
    light_source: Path,
    dark_source: Path,
    quality: str,
    focus: tuple[float, float],
    source_kzb: bytes,
    source_records: list[TextureRecord],
    aux_mode: str,
) -> dict[int, bytes]:
    output_dir.mkdir(parents=True, exist_ok=True)
    alphas = build_half_alphas(
        astcenc=astcenc,
        output_dir=output_dir / "source_masks",
        kzb=source_kzb,
        records=source_records,
    )
    light_full = compose_full_texture_from_vcd_mapping(
        load_source(light_source),
        LIGHT_VCD_PREVIEW_CROP,
    )
    dark_full = compose_full_texture_from_vcd_mapping(
        load_source(dark_source),
        DARK_VCD_PREVIEW_CROP,
    )
    light_blur = light_full.filter(ImageFilter.GaussianBlur(radius=18))
    dark_blur = dark_full.filter(ImageFilter.GaussianBlur(radius=18))
    if aux_mode == "masked":
        sources = {
            1: apply_original_alpha(dark_blur, alphas[1]),
            2: apply_original_alpha(dark_full, alphas[2]),
            3: dark_full,
            4: apply_original_alpha(light_blur, alphas[4]),
            5: apply_original_alpha(light_full, alphas[5]),
            6: light_full,
        }
    elif aux_mode == "full":
        sources = {
            1: dark_blur,
            2: dark_full,
            3: dark_full,
            4: light_blur,
            5: light_full,
            6: light_full,
        }
    else:
        raise ValueError(f"unsupported aux_mode: {aux_mode}")

    payloads: dict[int, bytes] = {}
    for index, image in sources.items():
        source_png = output_dir / f"record{index}_source_storage_yflip.png"
        output_astc = output_dir / f"record{index}_8960x1320_8x8.astc"
        save_storage_orientation(image, source_png)
        payloads[index] = encode_astc_payload(
            astcenc=astcenc,
            source_png=source_png,
            output_astc=output_astc,
            quality=quality,
        )
    return payloads


def patch_kzb(kzb: bytes, payloads: dict[int, bytes]) -> tuple[bytes, list[TextureRecord]]:
    records = find_texture_records(kzb)
    patched = bytearray(kzb)
    for index, payload in payloads.items():
        if index == 0:
            raise ValueError("record 0 is the shared mask and must not be replaced")
        if len(payload) != KZB_TEXTURE_PAYLOAD_SIZE:
            raise ValueError(f"record {index} payload size mismatch")
        record = records[index]
        patched[record.payload_start : record.payload_end] = payload
    return bytes(patched), records


def copy_info(info: zipfile.ZipInfo) -> zipfile.ZipInfo:
    copied = zipfile.ZipInfo(info.filename, date_time=info.date_time)
    copied.comment = info.comment
    copied.extra = info.extra
    copied.internal_attr = info.internal_attr
    copied.external_attr = info.external_attr
    copied.create_system = info.create_system
    copied.compress_type = info.compress_type
    return copied


def build_package(
    input_zip: Path,
    output_zip: Path,
    astcenc: Path,
    light_kzb_source: Path,
    dark_kzb_source: Path,
    work_dir: Path,
    quality: str,
    focus: tuple[float, float],
    aux_mode: str,
) -> dict[str, object]:
    if not astcenc.exists():
        raise FileNotFoundError(astcenc)

    for path in (light_kzb_source, dark_kzb_source):
        if not path.exists():
            raise FileNotFoundError(path)

    with zipfile.ZipFile(input_zip) as source_archive:
        root = find_wallpaper_root(source_archive.namelist())
        kzb_name = f"{root}/{KZB_TEXTURE_PATH_SUFFIX}"
        source_kzb = source_archive.read(kzb_name)
        source_records = find_texture_records(source_kzb)
        payloads = build_payloads(
            astcenc=astcenc,
            output_dir=work_dir / "astc_payloads",
            light_source=light_kzb_source,
            dark_source=dark_kzb_source,
            quality=quality,
            focus=focus,
            source_kzb=source_kzb,
            source_records=source_records,
            aux_mode=aux_mode,
        )
        patched_kzb, source_records = patch_kzb(source_kzb, payloads)
        patched_records = find_texture_records(patched_kzb)

        output_zip.parent.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(output_zip, "w") as output_archive:
            for info in source_archive.infolist():
                if info.is_dir():
                    output_archive.writestr(info, b"")
                    continue
                data = patched_kzb if info.filename == kzb_name else source_archive.read(info.filename)
                output_archive.writestr(copy_info(info), data)

    return {
        "input_zip": str(input_zip.resolve()),
        "output_zip": str(output_zip.resolve()),
        "astcenc": str(astcenc.resolve()),
        "quality": quality,
        "light_kzb_source": str(light_kzb_source.resolve()),
        "dark_kzb_source": str(dark_kzb_source.resolve()),
        "focus": focus,
        "aux_mode": aux_mode,
        "source_kzb_md5": hashlib.md5(source_kzb).hexdigest(),
        "patched_kzb_md5": hashlib.md5(patched_kzb).hexdigest(),
        "source_records": [record.__dict__ for record in source_records],
        "patched_records": [record.__dict__ for record in patched_records],
        "replaced_records": sorted(payloads),
        "record0_preserved": source_records[0].md5 == patched_records[0].md5,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Patch Cadillac KZB ASTC wallpaper textures.")
    parser.add_argument("--input-zip", type=Path, required=True)
    parser.add_argument("--output-zip", type=Path, required=True)
    parser.add_argument("--light-kzb-source", type=Path, required=True)
    parser.add_argument("--dark-kzb-source", type=Path, required=True)
    parser.add_argument("--astcenc", type=Path, required=True)
    parser.add_argument("--work-dir", type=Path, required=True)
    parser.add_argument("--quality", default="-medium")
    parser.add_argument(
        "--aux-mode",
        choices=("masked", "full"),
        default="masked",
        help="Use original alpha for rec1/2/4/5, or make these auxiliary records full-width and opaque.",
    )
    parser.add_argument(
        "--focus",
        default="0.5,0.5",
        help="Normalized x,y cover-resize focus for KZB full textures.",
    )
    parser.add_argument("--report", type=Path)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    if args.work_dir.exists():
        shutil.rmtree(args.work_dir)
    args.work_dir.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=args.work_dir) as _:
        report = build_package(
            input_zip=args.input_zip,
            output_zip=args.output_zip,
            astcenc=args.astcenc,
            light_kzb_source=args.light_kzb_source,
            dark_kzb_source=args.dark_kzb_source,
            work_dir=args.work_dir,
            quality=args.quality,
            focus=parse_focus(args.focus),
            aux_mode=args.aux_mode,
        )
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2))
    print(json.dumps(report, ensure_ascii=False, indent=2))


def parse_focus(value: str) -> tuple[float, float]:
    parts = value.split(",")
    if len(parts) != 2:
        raise ValueError("--focus must use x,y format")
    return float(parts[0]), float(parts[1])


if __name__ == "__main__":
    main()
