#!/usr/bin/env python3
"""Build a Cadillac OTA wallpaper package from native or legacy day/night art."""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import math
import os
import re
import shutil
import tempfile
import zipfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any


PROJECT_ROOT = Path(__file__).resolve().parent
DEFAULT_INPUT_ZIP = PROJECT_ROOT / "templates/BFA3A0F4596C4C57A6BCDC1EB3348932.zip"
DEFAULT_ASTCENC = PROJECT_ROOT / "tools/macos/astcenc"
DEFAULT_LIGHT_DIM_MASK = PROJECT_ROOT / "masks/light_dim_alpha_fixed_smoothed_used.png"
DEFAULT_DARK_DIM_MASK = PROJECT_ROOT / "masks/dark_dim_alpha_fixed_smoothed_used.png"

PREVIEW_SIZE = (2198, 367)
NATIVE_SIZE = (8960, 1320)
VCD_SIZE = (3950, 1320)
RID_SIZE = (1920, 1080)
PNG_TARGET_SIZES = {
    "vcd/wallpaper/light_wallpaper_vcd.png": VCD_SIZE,
    "vcd/wallpaper/dark_wallpaper_vcd.png": VCD_SIZE,
    "rid/screenSaver/light_screenSaver_rid.png": RID_SIZE,
    "rid/screenSaver/dark_screenSaver_rid.png": RID_SIZE,
    "light_dim_background.png": VCD_SIZE,
    "dark_dim_background.png": VCD_SIZE,
    "light_preview_image.png": PREVIEW_SIZE,
    "dark_preview_image.png": PREVIEW_SIZE,
}
PREVIEW_TARGETS = {"light_preview_image.png", "dark_preview_image.png"}


def redact_text(value: Any) -> str:
    text = str(value)
    home = str(Path.home())
    if home and home != "/":
        text = text.replace(home, "<HOME>")
    text = re.sub(r"/(Users|home)/[^/\s\"<>]+", "<HOME>", text)
    text = re.sub(r"[A-Za-z]:[\\/]+Users[\\/]+[^\\/\s\"<>]+", "<HOME>", text)
    text = re.sub(r"/var/folders/[^\s\"<>]+", "<TEMP>", text)
    return text


def redacted_path(path: Path) -> str:
    try:
        return redact_text(path.expanduser().resolve())
    except Exception:
        return redact_text(path)


def redact_report_values(value: Any) -> Any:
    if isinstance(value, str):
        return redact_text(value)
    if isinstance(value, list):
        return [redact_report_values(item) for item in value]
    if isinstance(value, dict):
        return {key: redact_report_values(item) for key, item in value.items()}
    return value


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def publish_verified_zip(source: Path, destination: Path) -> None:
    """Copy to the target filesystem, then create the final name without overwrite."""
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary_path: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(dir=destination.parent, prefix=".ota-",
                                         suffix=".tmp", delete=False) as temporary:
            temporary_path = Path(temporary.name)
            with source.open("rb") as original:
                shutil.copyfileobj(original, temporary, length=1024 * 1024)
            temporary.flush()
            os.fsync(temporary.fileno())
        try:
            os.link(temporary_path, destination)
        except FileExistsError:
            if file_sha256(destination) != file_sha256(temporary_path):
                raise FileExistsError(f"output ZIP already exists with different content: {destination}")
    finally:
        if temporary_path is not None:
            temporary_path.unlink(missing_ok=True)


def progress(message: str) -> None:
    print(f"[cadillac-packager] {redact_text(message)}", flush=True)


def load_runtime_dependencies() -> None:
    global Image, ImageChops, ImageFilter, ImageOps, ImageStat, kzb, identity
    from PIL import Image as pil_image
    from PIL import ImageChops as pil_image_chops
    from PIL import ImageFilter as pil_image_filter
    from PIL import ImageOps as pil_image_ops
    from PIL import ImageStat as pil_image_stat

    import kzb_astc_patcher as kzb_module
    import kzb_identity as identity_module

    Image = pil_image
    ImageChops = pil_image_chops
    ImageFilter = pil_image_filter
    ImageOps = pil_image_ops
    ImageStat = pil_image_stat
    kzb = kzb_module
    identity = identity_module


@dataclass(frozen=True)
class ThemeRule:
    label: str
    preview_path: str
    vcd_path: str
    rid_path: str
    dim_path: str
    vcd_crop: tuple[int, int, int, int]
    rid_crop: tuple[int, int, int, int]
    dim_blur_radius: float
    dim_overlay_rgb: tuple[int, int, int]


THEME_RULES = {
    "light": ThemeRule(
        label="light",
        preview_path="light_preview_image.png",
        vcd_path="vcd/wallpaper/light_wallpaper_vcd.png",
        rid_path="rid/screenSaver/light_screenSaver_rid.png",
        dim_path="light_dim_background.png",
        vcd_crop=(1256, 48, 2196, 362),
        rid_crop=(904, 48, 1441, 350),
        dim_blur_radius=48,
        dim_overlay_rgb=(232, 242, 250),
    ),
    "dark": ThemeRule(
        label="dark",
        preview_path="dark_preview_image.png",
        vcd_path="vcd/wallpaper/dark_wallpaper_vcd.png",
        rid_path="rid/screenSaver/dark_screenSaver_rid.png",
        dim_path="dark_dim_background.png",
        vcd_crop=(1260, 20, 2200, 334),
        rid_crop=(872, 8, 1494, 358),
        dim_blur_radius=32,
        dim_overlay_rgb=(0, 0, 0),
    ),
}


def md5_bytes(data: bytes) -> str:
    return hashlib.md5(data).hexdigest()


def md5_image_channel(channel: Image.Image) -> str:
    return hashlib.md5(channel.tobytes()).hexdigest()


def load_preview_master(path: Path, label: str) -> Image.Image:
    """Load a full rectangular 2198x367 master and ignore any input alpha."""
    if not path.exists():
        raise FileNotFoundError(path)
    with Image.open(path) as image:
        if image.format != "PNG":
            raise ValueError(f"{label} image must be PNG")
        source = image.convert("RGBA")
    if source.size != PREVIEW_SIZE:
        raise ValueError(f"{label} image must be {PREVIEW_SIZE}, got {source.size}: {path}")

    rgb = source.convert("RGB")
    opaque = Image.new("L", PREVIEW_SIZE, 255)
    return Image.merge("RGBA", (*rgb.split(), opaque))


def load_native_master(path: Path, label: str) -> Image.Image:
    """Require an opaque, complete native canvas; never distort its aspect ratio."""
    if not path.exists():
        raise FileNotFoundError(path)
    with Image.open(path) as image:
        if image.format != "PNG":
            raise ValueError(f"{label} image must be PNG")
        source = image.convert("RGBA")
    if source.size != NATIVE_SIZE:
        raise ValueError(f"{label} native image must be {NATIVE_SIZE}, got {source.size}: {path}")
    if source.getchannel("A").getextrema() != (255, 255):
        raise ValueError(f"{label} native image must be fully opaque: {path}")
    return source


def fit_without_distortion(image: Image.Image, size: tuple[int, int]) -> Image.Image:
    fitted = ImageOps.fit(image.convert("RGB"), size, Image.Resampling.LANCZOS)
    return Image.merge("RGBA", (*fitted.split(), Image.new("L", size, 255)))


def crop_with_edge_pad(
    image: Image.Image,
    bbox: tuple[int, int, int, int],
) -> Image.Image:
    """Crop a bbox, repeating edge pixels when the bbox exceeds image bounds."""
    left, top, right, bottom = bbox
    pad_left = max(0, -left)
    pad_top = max(0, -top)
    pad_right = max(0, right - image.width)
    pad_bottom = max(0, bottom - image.height)
    source = image.convert("RGBA")

    if any((pad_left, pad_top, pad_right, pad_bottom)):
        width, height = source.size
        padded = Image.new(
            "RGBA",
            (width + pad_left + pad_right, height + pad_top + pad_bottom),
        )
        padded.paste(source, (pad_left, pad_top))
        if pad_top:
            padded.paste(
                source.crop((0, 0, width, 1)).resize((width, pad_top)),
                (pad_left, 0),
            )
        if pad_bottom:
            padded.paste(
                source.crop((0, height - 1, width, height)).resize((width, pad_bottom)),
                (pad_left, pad_top + height),
            )
        if pad_left:
            padded.paste(
                padded.crop((pad_left, 0, pad_left + 1, padded.height)).resize(
                    (pad_left, padded.height)
                ),
                (0, 0),
            )
        if pad_right:
            padded.paste(
                padded.crop(
                    (pad_left + width - 1, 0, pad_left + width, padded.height)
                ).resize((pad_right, padded.height)),
                (pad_left + width, 0),
            )
        source = padded
        left += pad_left
        right += pad_left
        top += pad_top
        bottom += pad_top

    return source.crop((left, top, right, bottom))


def resized_crop(
    master: Image.Image,
    bbox: tuple[int, int, int, int],
    target_size: tuple[int, int],
    sharpen: bool,
) -> Image.Image:
    resized = crop_with_edge_pad(master, bbox).resize(target_size, Image.Resampling.LANCZOS)
    if sharpen:
        resized = resized.filter(ImageFilter.UnsharpMask(radius=0.8, percent=130, threshold=2))
    alpha = Image.new("L", target_size, 255)
    rgb = resized.convert("RGB")
    return Image.merge("RGBA", (*rgb.split(), alpha))


def apply_preview_alpha(master: Image.Image, original_preview_bytes: bytes) -> Image.Image:
    with Image.open(io.BytesIO(original_preview_bytes)) as original:
        alpha = original.convert("RGBA").getchannel("A")
    if alpha.size != PREVIEW_SIZE:
        raise ValueError(f"template preview alpha must be {PREVIEW_SIZE}, got {alpha.size}")
    result = master.convert("RGBA")
    result.putalpha(alpha)
    return result


def make_dim_background(
    vcd: Image.Image,
    mask_path: Path,
    rule: ThemeRule,
) -> Image.Image:
    if not mask_path.exists():
        raise FileNotFoundError(mask_path)
    with Image.open(mask_path) as mask_image:
        mask = mask_image.convert("L")
    if mask.size != VCD_SIZE:
        raise ValueError(f"{rule.label} dim mask must be {VCD_SIZE}, got {mask.size}")

    blurred = vcd.convert("RGBA").filter(ImageFilter.GaussianBlur(radius=rule.dim_blur_radius))
    overlay = Image.new("RGBA", VCD_SIZE, (*rule.dim_overlay_rgb, 0))
    overlay.putalpha(mask)
    composited = Image.alpha_composite(blurred, overlay)
    rgb = composited.convert("RGB")
    alpha = Image.new("L", VCD_SIZE, 255)
    return Image.merge("RGBA", (*rgb.split(), alpha))


def png_bytes(image: Image.Image) -> bytes:
    buffer = io.BytesIO()
    image.save(buffer, format="PNG", optimize=True)
    return buffer.getvalue()


def save_png(image: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, format="PNG", optimize=True)


def derive_external_pngs(
    archive: zipfile.ZipFile,
    root: str,
    light_master: Image.Image,
    dark_master: Image.Image,
    work_dir: Path,
    light_dim_mask: Path,
    dark_dim_mask: Path,
    preview_blur: float,
    sharpen: bool,
    source_mode: str,
) -> tuple[dict[str, bytes], dict[str, Any]]:
    masters = {"light": light_master, "dark": dark_master}
    dim_masks = {"light": light_dim_mask, "dark": dark_dim_mask}
    replacements: dict[str, bytes] = {}
    report: dict[str, Any] = {}

    for label, rule in THEME_RULES.items():
        master = masters[label]
        save_png(master, work_dir / "source_masters" / f"{label}_{source_mode}_master.png")
        if source_mode == "native":
            preview_source = fit_without_distortion(master, PREVIEW_SIZE)
            vcd = master.crop((kzb.KZB_VCD_JOIN_X, 0, *NATIVE_SIZE))
            rid = fit_without_distortion(vcd, RID_SIZE)
        else:
            preview_source = master
            vcd = resized_crop(master, rule.vcd_crop, VCD_SIZE, sharpen=sharpen)
            rid = resized_crop(master, rule.rid_crop, RID_SIZE, sharpen=sharpen)
        if preview_blur > 0:
            preview_source = preview_source.filter(ImageFilter.GaussianBlur(radius=preview_blur))
        preview = apply_preview_alpha(
            preview_source,
            archive.read(f"{root}/{rule.preview_path}"),
        )
        dim = make_dim_background(vcd, dim_masks[label], rule)

        outputs = {
            rule.preview_path: preview,
            rule.vcd_path: vcd,
            rule.rid_path: rid,
            rule.dim_path: dim,
        }
        for relative_path, image in outputs.items():
            save_png(image, work_dir / "derived_png" / relative_path)
            replacements[f"{root}/{relative_path}"] = png_bytes(image)

        report[label] = {
            "preview_alpha_md5": md5_image_channel(preview.getchannel("A")),
            "vcd_crop": list(rule.vcd_crop) if source_mode == "legacy" else [5010, 0, 8960, 1320],
            "rid_crop": list(rule.rid_crop) if source_mode == "legacy" else "aspect-preserving-center-crop-of-vcd",
            "preview_derivation": "aspect-preserving-center-crop" if source_mode == "native" else "legacy-preview",
            "dim_mask": redacted_path(dim_masks[label]),
            "dim_blur_radius": rule.dim_blur_radius,
            "dim_overlay_rgb": list(rule.dim_overlay_rgb),
        }

    return replacements, report


def premultiply_rgb_by_alpha(image: Image.Image) -> Image.Image:
    """Premultiply RGB by alpha so alpha=0 pixels have RGB 0,0,0."""
    red, green, blue, alpha = image.convert("RGBA").split()
    return Image.merge(
        "RGBA",
        (
            ImageChops.multiply(red, alpha),
            ImageChops.multiply(green, alpha),
            ImageChops.multiply(blue, alpha),
            alpha,
        ),
    )


def apply_original_alpha_premultiplied(source: Image.Image, alpha: Image.Image) -> Image.Image:
    result = source.convert("RGBA")
    result.putalpha(alpha.convert("L"))
    return premultiply_rgb_by_alpha(result)


def build_kzb_payloads(
    astcenc: Path,
    output_dir: Path,
    light_master: Image.Image,
    dark_master: Image.Image,
    source_kzb: bytes,
    source_records: list[kzb.TextureRecord],
    quality: str,
    source_mode: str,
) -> tuple[dict[int, bytes], dict[str, Any]]:
    output_dir.mkdir(parents=True, exist_ok=True)
    alphas = kzb.build_half_alphas(
        astcenc=astcenc,
        output_dir=output_dir / "source_masks",
        kzb=source_kzb,
        records=source_records,
    )

    if source_mode == "native":
        light_full = light_master.convert("RGB")
        dark_full = dark_master.convert("RGB")
    else:
        light_full = kzb.compose_full_texture_from_vcd_mapping(
            light_master, kzb.LIGHT_VCD_PREVIEW_CROP,
        )
        dark_full = kzb.compose_full_texture_from_vcd_mapping(
            dark_master, kzb.DARK_VCD_PREVIEW_CROP,
        )
    sources = {
        1: apply_original_alpha_premultiplied(
            dark_full.filter(ImageFilter.GaussianBlur(radius=18)),
            alphas[1],
        ),
        2: apply_original_alpha_premultiplied(dark_full, alphas[2]),
        3: dark_full.convert("RGBA"),
        4: apply_original_alpha_premultiplied(
            light_full.filter(ImageFilter.GaussianBlur(radius=18)),
            alphas[4],
        ),
        5: apply_original_alpha_premultiplied(light_full, alphas[5]),
        6: light_full.convert("RGBA"),
    }

    payloads: dict[int, bytes] = {}
    source_reports: dict[str, Any] = {}
    progress("step 5/9 encode KZB ASTC records")
    for index, image in sources.items():
        source_png = output_dir / f"record{index}_source_storage_yflip.png"
        output_astc = output_dir / f"record{index}_8960x1320_8x8.astc"
        progress(f"encode ASTC record {index}/6")
        kzb.save_storage_orientation(image, source_png)
        payloads[index] = kzb.encode_astc_payload(
            astcenc=astcenc,
            source_png=source_png,
            output_astc=output_astc,
            quality=quality,
        )
        source_reports[str(index)] = {
            "source_png": redacted_path(source_png),
            "source_alpha_extrema": list(image.getchannel("A").getextrema()),
        }

    return payloads, source_reports


def patch_kzb_from_masters(
    source_kzb: bytes,
    astcenc: Path,
    work_dir: Path,
    light_master: Image.Image,
    dark_master: Image.Image,
    quality: str,
    source_mode: str,
) -> tuple[bytes, dict[str, Any]]:
    source_records = kzb.find_texture_records(source_kzb)
    payloads, source_reports = build_kzb_payloads(
        astcenc=astcenc,
        output_dir=work_dir / "kzb_astc_payloads",
        light_master=light_master,
        dark_master=dark_master,
        source_kzb=source_kzb,
        source_records=source_records,
        quality=quality,
        source_mode=source_mode,
    )
    patched_kzb, _ = kzb.patch_kzb(source_kzb, payloads)
    patched_records = kzb.find_texture_records(patched_kzb)
    report = {
        "source_kzb_md5": md5_bytes(source_kzb),
        "patched_kzb_md5": md5_bytes(patched_kzb),
        "source_kzb_size": len(source_kzb),
        "patched_kzb_size": len(patched_kzb),
        "source_records": [record.__dict__ for record in source_records],
        "patched_records": [record.__dict__ for record in patched_records],
        "replaced_records": sorted(payloads),
        "record0_preserved": source_records[0].md5 == patched_records[0].md5,
        "record_offsets_same": [
            source.header_offset == patched.header_offset
            for source, patched in zip(source_records, patched_records)
        ],
        "record_source_reports": source_reports,
    }
    return patched_kzb, report


def rgba_extrema_from_png_bytes(data: bytes) -> tuple[tuple[int, int], ...]:
    with Image.open(io.BytesIO(data)) as image:
        return tuple(image.convert("RGBA").getextrema())


def verify_pngs(
    template_archive: zipfile.ZipFile,
    output_archive: zipfile.ZipFile,
    template_root: str,
    output_root: str,
) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for relative_path, expected_size in PNG_TARGET_SIZES.items():
        output_data = output_archive.read(f"{output_root}/{relative_path}")
        with Image.open(io.BytesIO(output_data)) as image:
            rgba = image.convert("RGBA")
            alpha_extrema = rgba.getchannel("A").getextrema()
            entry: dict[str, Any] = {
                "size": list(rgba.size),
                "size_matches": rgba.size == expected_size,
                "alpha_extrema": list(alpha_extrema),
                "bytes": len(output_data),
            }
            if relative_path in PREVIEW_TARGETS:
                original_alpha = Image.open(
                    io.BytesIO(template_archive.read(f"{template_root}/{relative_path}"))
                ).convert("RGBA").getchannel("A")
                entry["preview_alpha_md5"] = md5_image_channel(rgba.getchannel("A"))
                entry["template_alpha_md5"] = md5_image_channel(original_alpha)
                entry["preview_alpha_matches_template"] = (
                    entry["preview_alpha_md5"] == entry["template_alpha_md5"]
                )
            else:
                entry["fully_opaque"] = alpha_extrema == (255, 255)
            result[relative_path] = entry
    return result


def channel_max_where_alpha_zero(image: Image.Image) -> list[int] | None:
    rgba = image.convert("RGBA")
    alpha = rgba.getchannel("A")
    alpha_zero_count = alpha.histogram()[0]
    if not alpha_zero_count:
        return None
    mask = alpha.point(lambda pixel: 255 if pixel == 0 else 0)
    maxima: list[int] = []
    for channel in rgba.convert("RGB").split():
        extrema = ImageStat.Stat(channel, mask=mask).extrema[0]
        maxima.append(int(extrema[1]))
    return maxima


def alpha_summary(image: Image.Image) -> dict[str, Any]:
    alpha = image.convert("RGBA").getchannel("A")
    histogram = alpha.histogram()
    total = alpha.width * alpha.height
    alpha0 = histogram[0]
    alpha255 = histogram[255]
    alpha_mid = total - alpha0 - alpha255
    return {
        "alpha_extrema": list(alpha.getextrema()),
        "alpha0_pct": round(alpha0 / total * 100, 6),
        "alpha_1_254_pct": round(alpha_mid / total * 100, 6),
        "alpha255_pct": round(alpha255 / total * 100, 6),
        "rgb_where_alpha0_max": channel_max_where_alpha_zero(image),
    }


def image_mae(left: Image.Image, right: Image.Image) -> float:
    diff = ImageChops.difference(left.convert("RGB"), right.convert("RGB"))
    stat = ImageStat.Stat(diff)
    return round(sum(stat.mean) / len(stat.mean), 6)


def verify_kzb_decode(
    astcenc: Path,
    output_kzb: bytes,
    output_archive: zipfile.ZipFile,
    root: str,
    work_dir: Path,
) -> dict[str, Any]:
    records = kzb.find_texture_records(output_kzb)
    verify_dir = work_dir / "verify_decode"
    verify_dir.mkdir(parents=True, exist_ok=True)
    aux_reports: dict[str, Any] = {}
    for index in (1, 2, 4, 5):
        record = records[index]
        decoded = kzb.decode_record_payload(
            astcenc=astcenc,
            payload=output_kzb[record.payload_start : record.payload_end],
            astc_path=verify_dir / f"record{index}.astc",
            png_path=verify_dir / f"record{index}_decoded_storage.png",
        )
        aux_reports[str(index)] = alpha_summary(decoded)

    stitch_reports: dict[str, Any] = {}
    for index, relative_path in (
        (3, "vcd/wallpaper/dark_wallpaper_vcd.png"),
        (6, "vcd/wallpaper/light_wallpaper_vcd.png"),
    ):
        record = records[index]
        decoded_storage = kzb.decode_record_payload(
            astcenc=astcenc,
            payload=output_kzb[record.payload_start : record.payload_end],
            astc_path=verify_dir / f"record{index}.astc",
            png_path=verify_dir / f"record{index}_decoded_storage.png",
        )
        decoded = decoded_storage.transpose(Image.Transpose.FLIP_TOP_BOTTOM)
        right_crop = decoded.crop((kzb.KZB_VCD_JOIN_X, 0, kzb.KZB_TEXTURE_WIDTH, kzb.KZB_TEXTURE_HEIGHT))
        with Image.open(io.BytesIO(output_archive.read(f"{root}/{relative_path}"))) as vcd:
            stitch_reports[str(index)] = {
                "external_vcd": relative_path,
                "right_crop_vs_vcd_mae": image_mae(right_crop, vcd.convert("RGBA")),
            }

    return {
        "aux_records": aux_reports,
        "stitch": stitch_reports,
        "decode_dir": redacted_path(verify_dir),
    }


def assert_report_is_safe(report: dict[str, Any], max_stitch_mae: float) -> None:
    if report["zip_test_bad_file"] is not None:
        raise ValueError(f"zip test failed at {report['zip_test_bad_file']}")
    if report["zip_file_count"] != 9:
        raise ValueError("final OTA must contain exactly eight PNGs and one KZB")

    for relative_path, entry in report["pngs"].items():
        if not entry["size_matches"]:
            raise ValueError(f"{relative_path} size mismatch: {entry['size']}")
        if relative_path in PREVIEW_TARGETS:
            if not entry["preview_alpha_matches_template"]:
                raise ValueError(f"{relative_path} alpha differs from template")
        elif not entry["fully_opaque"]:
            raise ValueError(f"{relative_path} is not fully opaque")

    kzb_report = report["kzb"]
    if not kzb_report["record0_preserved"]:
        raise ValueError("KZB rec0 changed")
    if not kzb_report["identity_rebuild_consistent"]:
        raise ValueError("KZB identity rebuild did not verify")

    decode = report.get("decoded_kzb")
    if not decode:
        return
    for index, entry in decode["aux_records"].items():
        if entry["rgb_where_alpha0_max"] not in (None, [0, 0, 0]):
            raise ValueError(
                f"KZB rec{index} transparent RGB is not zero: "
                f"{entry['rgb_where_alpha0_max']}"
            )
    for index, entry in decode["stitch"].items():
        mae = entry["right_crop_vs_vcd_mae"]
        if mae > max_stitch_mae:
            raise ValueError(f"KZB rec{index} stitch MAE too high: {mae}")


def build_package(
    input_zip: Path,
    output_zip: Path,
    light_image: Path,
    dark_image: Path,
    astcenc: Path,
    work_dir: Path,
    light_dim_mask: Path,
    dark_dim_mask: Path,
    quality: str = "-medium",
    preview_blur: float = 0.45,
    sharpen: bool = True,
    decode_verify: bool = True,
    max_stitch_mae: float = 4.0,
    source_mode: str = "legacy",
    theme_key: str = "wallpaper",
) -> dict[str, Any]:
    progress("step 1/9 validate inputs and template")
    if source_mode not in ("native", "legacy"):
        raise ValueError(f"unsupported source mode: {source_mode}")
    if not decode_verify:
        raise ValueError("decoded ASTC/alpha/seam verification is required for final OTA output")
    if not re.fullmatch(r"[a-z][a-z0-9_]{0,31}", theme_key):
        raise ValueError("theme key must be 1-32 lowercase ASCII letters, digits or underscores")
    if not math.isfinite(preview_blur) or not 0 <= preview_blur <= 20:
        raise ValueError("preview blur must be finite and between 0 and 20")
    if not math.isfinite(max_stitch_mae) or not 0 <= max_stitch_mae <= 255:
        raise ValueError("maximum stitch MAE must be finite and between 0 and 255")
    if not input_zip.exists():
        raise FileNotFoundError(input_zip)
    if not astcenc.exists():
        raise FileNotFoundError(astcenc)
    if input_zip.resolve() == output_zip.resolve():
        raise ValueError("output ZIP must differ from template ZIP")
    if output_zip.resolve() in {light_image.resolve(), dark_image.resolve()}:
        raise ValueError("output ZIP must differ from source images")
    source_kzb, _, kzb_name = identity.read_source(input_zip)
    template_kzb, _, parsed_prefab = identity.validate_kzb(source_kzb)
    if identity.resource_layout_profile(template_kzb) != "football-static":
        raise ValueError("this two-image packager accepts only the audited static wallpaper template")
    root = kzb_name.split("/ipd/wallpaper/", 1)[0]
    root_properties = {item["property"]: item["value"] for item in parsed_prefab["root"]["properties"]["values"]}
    if (root_properties.get("Node.Width"), root_properties.get("Node.Height")) != NATIVE_SIZE:
        raise ValueError("template does not have the audited 8960x1320 native canvas")
    if (kzb.KZB_TEXTURE_WIDTH, kzb.KZB_TEXTURE_HEIGHT, kzb.KZB_VCD_JOIN_X) != (8960, 1320, 5010):
        raise ValueError("unsupported KZB texture geometry")
    if len(kzb.find_texture_records(source_kzb)) != 7:
        raise ValueError("template must have seven native ASTC records")
    progress(f"template wallpaper root: {root}, project: {template_kzb.project_name}")

    work_dir.mkdir(parents=True, exist_ok=True)
    run_dir = Path(tempfile.mkdtemp(prefix="build-", dir=work_dir))

    progress(f"step 2/9 load {source_mode} day/night masters")
    loader = load_native_master if source_mode == "native" else load_preview_master
    light_master = loader(light_image, "light")
    dark_master = loader(dark_image, "dark")
    replacements: dict[str, bytes] = {}

    with zipfile.ZipFile(input_zip) as source_archive:
        progress("step 3/9 derive external PNGs")
        external_replacements, external_report = derive_external_pngs(
            archive=source_archive,
            root=root,
            light_master=light_master,
            dark_master=dark_master,
            work_dir=run_dir,
            light_dim_mask=light_dim_mask,
            dark_dim_mask=dark_dim_mask,
            preview_blur=preview_blur,
            sharpen=sharpen,
            source_mode=source_mode,
        )
        replacements.update(external_replacements)

        progress("step 4/9 prepare KZB source records")
        patched_kzb, kzb_report = patch_kzb_from_masters(
            source_kzb=source_kzb,
            astcenc=astcenc,
            work_dir=run_dir,
            light_master=light_master,
            dark_master=dark_master,
            quality=quality,
            source_mode=source_mode,
        )
        replacements[kzb_name] = patched_kzb

        progress("step 6/9 write nine-file candidate")
        candidate_zip = run_dir / "candidate.zip"
        with zipfile.ZipFile(candidate_zip, "w") as output_archive:
            for info in source_archive.infolist():
                if info.is_dir():
                    continue
                data = replacements[info.filename]
                output_archive.writestr(kzb.copy_info(info), data)

    progress("step 7/9 rebuild independent internal and outer identities")
    candidate_kzb, candidate_pngs, _ = identity.read_source(candidate_zip)
    internal_id, _, _ = identity.content_identity(theme_key, candidate_kzb, candidate_pngs)
    final_stage = run_dir / "final-ota.zip"
    identity_report = identity.build_package(
        candidate_zip,
        theme_key,
        internal_id,
        final_stage,
        run_dir / "identity-report.json",
    )
    final_kzb_name = identity_report["kzb_path"]
    final_root = final_kzb_name.split("/ipd/wallpaper/", 1)[0]
    final_kzb = identity.read_source(final_stage)[0]
    final_records = kzb.find_texture_records(final_kzb)
    kzb_report["patched_kzb_size"] = len(final_kzb)
    kzb_report["final_records"] = [record.__dict__ for record in final_records]
    kzb_report["record_offsets_same"] = [
        source["header_offset"] == final.header_offset
        for source, final in zip(kzb_report["source_records"], final_records)
    ]
    kzb_report["identity_rebuild_consistent"] = (
        identity_report["inverse_rebuild_byte_identical"]
        and identity_report["no_old_identity_remaining"]
    )

    with zipfile.ZipFile(input_zip) as template_archive, zipfile.ZipFile(final_stage) as output_archive:
        output_names = output_archive.namelist()
        progress("step 8/9 verify final ZIP, PNG, and KZB invariants")
        report: dict[str, Any] = {
            "input_zip": redacted_path(input_zip),
            "output_zip": redacted_path(output_zip),
            "light_image": redacted_path(light_image),
            "dark_image": redacted_path(dark_image),
            "work_dir": redacted_path(run_dir),
            "astcenc": redacted_path(astcenc),
            "quality": quality,
            "source_mode": source_mode,
            "source_size": list(light_master.size),
            "wallpaper_root": final_root,
            "preview_paths": {
                "light": f"{final_root}/light_preview_image.png",
                "dark": f"{final_root}/dark_preview_image.png",
            },
            "preview_size": list(PREVIEW_SIZE),
            "preview_blur": preview_blur,
            "sharpen": sharpen,
            "zip_names_identical_order": template_archive.namelist() == output_names,
            "zip_structure_valid": True,
            "zip_file_count": len([name for name in output_names if not name.endswith("/")]),
            "zip_test_bad_file": output_archive.testzip(),
            "external_pngs": external_report,
            "pngs": verify_pngs(template_archive, output_archive, root, final_root),
            "kzb": kzb_report,
            "identity": redact_report_values(identity_report),
            "vehicle_runtime_verified": False,
        }
        if decode_verify:
            progress("decode verify KZB/VCD stitch")
            report["decoded_kzb"] = verify_kzb_decode(
                astcenc=astcenc,
                output_kzb=output_archive.read(final_kzb_name),
                output_archive=output_archive,
                root=final_root,
                work_dir=run_dir,
            )
    assert_report_is_safe(report, max_stitch_mae=max_stitch_mae)
    publish_verified_zip(final_stage, output_zip)
    identity.read_source(output_zip)
    progress("safety checks passed")
    return report


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Build a static day/night Cadillac OTA wallpaper from two matching "
            "8960x1320 native images or two 2198x367 legacy preview images."
        )
    )
    parser.add_argument("--light-image", type=Path, required=True)
    parser.add_argument("--dark-image", type=Path, required=True)
    parser.add_argument("--output-zip", type=Path, required=True)
    parser.add_argument("--input-zip", type=Path, default=DEFAULT_INPUT_ZIP)
    parser.add_argument("--astcenc", type=Path, default=DEFAULT_ASTCENC)
    parser.add_argument("--work-dir", type=Path)
    parser.add_argument("--report", type=Path)
    parser.add_argument("--light-dim-mask", type=Path, default=DEFAULT_LIGHT_DIM_MASK)
    parser.add_argument("--dark-dim-mask", type=Path, default=DEFAULT_DARK_DIM_MASK)
    parser.add_argument("--quality", default="-medium", help="astcenc quality, e.g. --quality=-medium")
    parser.add_argument("--preview-blur", type=float, default=0.45)
    parser.add_argument("--no-sharpen", action="store_true")
    parser.add_argument("--skip-decode-verify", action="store_true")
    parser.add_argument("--max-stitch-mae", type=float, default=4.0)
    parser.add_argument("--source-mode", choices=("native", "legacy"), default="legacy")
    parser.add_argument("--theme-key", default="wallpaper")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    load_runtime_dependencies()
    work_dir = args.work_dir
    if work_dir is None:
        work_dir = PROJECT_ROOT / "build" / f"{args.output_zip.stem}_work"
    report_path = args.report
    if report_path is None:
        report_path = work_dir / "package-report.json"
    forbidden = (args.output_zip, args.input_zip, args.light_image, args.dark_image)
    if any(report_path.resolve() == path.resolve() for path in forbidden):
        raise ValueError("report path must differ from ZIP and source image paths")
    if report_path.exists():
        raise FileExistsError(f"report already exists; choose a new output path: {report_path}")
    report = build_package(
        input_zip=args.input_zip,
        output_zip=args.output_zip,
        light_image=args.light_image,
        dark_image=args.dark_image,
        astcenc=args.astcenc,
        work_dir=work_dir,
        light_dim_mask=args.light_dim_mask,
        dark_dim_mask=args.dark_dim_mask,
        quality=args.quality,
        preview_blur=args.preview_blur,
        sharpen=not args.no_sharpen,
        decode_verify=not args.skip_decode_verify,
        max_stitch_mae=args.max_stitch_mae,
        source_mode=args.source_mode,
        theme_key=args.theme_key,
    )
    report_path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=report_path.parent,
                                     prefix=".package-report-", suffix=".tmp", delete=False) as temporary:
        json.dump(report, temporary, ensure_ascii=False, indent=2)
        temporary_path = Path(temporary.name)
    try:
        os.link(temporary_path, report_path)
    finally:
        temporary_path.unlink(missing_ok=True)
    progress("step 9/9 write report.json")
    print(
        json.dumps(
            {
                "output_zip": redacted_path(args.output_zip),
                "report": redacted_path(report_path),
            },
            ensure_ascii=False,
            indent=2,
        ),
        flush=True,
    )


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        progress(f"error: {type(error).__name__}: {error}")
        raise SystemExit(1)
