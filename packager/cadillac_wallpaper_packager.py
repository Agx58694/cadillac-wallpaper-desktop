#!/usr/bin/env python3
"""Build a tested Cadillac OTA wallpaper package from 2198x367 masters."""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import re
import shutil
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


def progress(message: str) -> None:
    print(f"[cadillac-packager] {redact_text(message)}", flush=True)


def load_runtime_dependencies() -> None:
    global Image, ImageChops, ImageFilter, ImageStat, kzb
    from PIL import Image as pil_image
    from PIL import ImageChops as pil_image_chops
    from PIL import ImageFilter as pil_image_filter
    from PIL import ImageStat as pil_image_stat

    import kzb_astc_patcher as kzb_module

    Image = pil_image
    ImageChops = pil_image_chops
    ImageFilter = pil_image_filter
    ImageStat = pil_image_stat
    kzb = kzb_module


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
        source = image.convert("RGBA")
    if source.size != PREVIEW_SIZE:
        raise ValueError(f"{label} image must be {PREVIEW_SIZE}, got {source.size}: {path}")

    rgb = source.convert("RGB")
    opaque = Image.new("L", PREVIEW_SIZE, 255)
    return Image.merge("RGBA", (*rgb.split(), opaque))


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
) -> tuple[dict[str, bytes], dict[str, Any]]:
    masters = {"light": light_master, "dark": dark_master}
    dim_masks = {"light": light_dim_mask, "dark": dark_dim_mask}
    replacements: dict[str, bytes] = {}
    report: dict[str, Any] = {}

    for label, rule in THEME_RULES.items():
        master = masters[label]
        save_png(master, work_dir / "preview_masters" / f"{label}_preview_master.png")

        preview_source = master
        if preview_blur > 0:
            preview_source = master.filter(ImageFilter.GaussianBlur(radius=preview_blur))
        preview = apply_preview_alpha(
            preview_source,
            archive.read(f"{root}/{rule.preview_path}"),
        )
        vcd = resized_crop(master, rule.vcd_crop, VCD_SIZE, sharpen=sharpen)
        rid = resized_crop(master, rule.rid_crop, RID_SIZE, sharpen=sharpen)
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
            "vcd_crop": list(rule.vcd_crop),
            "rid_crop": list(rule.rid_crop),
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
) -> tuple[dict[int, bytes], dict[str, Any]]:
    output_dir.mkdir(parents=True, exist_ok=True)
    alphas = kzb.build_half_alphas(
        astcenc=astcenc,
        output_dir=output_dir / "source_masks",
        kzb=source_kzb,
        records=source_records,
    )

    light_full = kzb.compose_full_texture_from_vcd_mapping(
        light_master,
        kzb.LIGHT_VCD_PREVIEW_CROP,
    )
    dark_full = kzb.compose_full_texture_from_vcd_mapping(
        dark_master,
        kzb.DARK_VCD_PREVIEW_CROP,
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
    root: str,
) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for relative_path, expected_size in PNG_TARGET_SIZES.items():
        output_data = output_archive.read(f"{root}/{relative_path}")
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
                    io.BytesIO(template_archive.read(f"{root}/{relative_path}"))
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
    if not report["zip_names_identical_order"]:
        raise ValueError("zip entry order changed")

    for relative_path, entry in report["pngs"].items():
        if not entry["size_matches"]:
            raise ValueError(f"{relative_path} size mismatch: {entry['size']}")
        if relative_path in PREVIEW_TARGETS:
            if not entry["preview_alpha_matches_template"]:
                raise ValueError(f"{relative_path} alpha differs from template")
        elif not entry["fully_opaque"]:
            raise ValueError(f"{relative_path} is not fully opaque")

    kzb_report = report["kzb"]
    if kzb_report["source_kzb_size"] != kzb_report["patched_kzb_size"]:
        raise ValueError("patched KZB size changed")
    if not kzb_report["record0_preserved"]:
        raise ValueError("KZB rec0 changed")
    if not all(kzb_report["record_offsets_same"]):
        raise ValueError("KZB record offsets changed")

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
) -> dict[str, Any]:
    progress("step 1/9 validate inputs")
    if not input_zip.exists():
        raise FileNotFoundError(input_zip)
    if not astcenc.exists():
        raise FileNotFoundError(astcenc)
    if work_dir.exists():
        shutil.rmtree(work_dir)
    work_dir.mkdir(parents=True, exist_ok=True)

    progress("step 2/9 load 2198x367 masters")
    light_master = load_preview_master(light_image, "light")
    dark_master = load_preview_master(dark_image, "dark")
    replacements: dict[str, bytes] = {}

    with zipfile.ZipFile(input_zip) as source_archive:
        source_names = source_archive.namelist()
        root = kzb.find_wallpaper_root(source_names)
        progress(f"template wallpaper root: {root}")
        progress("step 3/9 derive external PNGs")
        external_replacements, external_report = derive_external_pngs(
            archive=source_archive,
            root=root,
            light_master=light_master,
            dark_master=dark_master,
            work_dir=work_dir,
            light_dim_mask=light_dim_mask,
            dark_dim_mask=dark_dim_mask,
            preview_blur=preview_blur,
            sharpen=sharpen,
        )
        replacements.update(external_replacements)

        kzb_name = f"{root}/{kzb.KZB_TEXTURE_PATH_SUFFIX}"
        progress("step 4/9 prepare KZB source records")
        patched_kzb, kzb_report = patch_kzb_from_masters(
            source_kzb=source_archive.read(kzb_name),
            astcenc=astcenc,
            work_dir=work_dir,
            light_master=light_master,
            dark_master=dark_master,
            quality=quality,
        )
        replacements[kzb_name] = patched_kzb

        progress("step 6/9 write output OTA zip")
        output_zip.parent.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(output_zip, "w") as output_archive:
            for info in source_archive.infolist():
                if info.is_dir():
                    output_archive.writestr(info, b"")
                    continue
                data = replacements.get(info.filename)
                if data is None:
                    data = source_archive.read(info.filename)
                output_archive.writestr(kzb.copy_info(info), data)

    with zipfile.ZipFile(input_zip) as template_archive, zipfile.ZipFile(output_zip) as output_archive:
        output_names = output_archive.namelist()
        root = kzb.find_wallpaper_root(output_names)
        progress("step 7/9 verify ZIP, PNG, and KZB invariants")
        report: dict[str, Any] = {
            "input_zip": redacted_path(input_zip),
            "output_zip": redacted_path(output_zip),
            "light_image": redacted_path(light_image),
            "dark_image": redacted_path(dark_image),
            "work_dir": redacted_path(work_dir),
            "astcenc": redacted_path(astcenc),
            "quality": quality,
            "preview_size": list(PREVIEW_SIZE),
            "preview_blur": preview_blur,
            "sharpen": sharpen,
            "zip_names_identical_order": template_archive.namelist() == output_names,
            "zip_test_bad_file": output_archive.testzip(),
            "external_pngs": external_report,
            "pngs": verify_pngs(template_archive, output_archive, root),
            "kzb": kzb_report,
        }
        if decode_verify:
            progress("step 8/9 decode verify KZB/VCD stitch")
            report["decoded_kzb"] = verify_kzb_decode(
                astcenc=astcenc,
                output_kzb=output_archive.read(f"{root}/{kzb.KZB_TEXTURE_PATH_SUFFIX}"),
                output_archive=output_archive,
                root=root,
                work_dir=work_dir,
            )
    assert_report_is_safe(report, max_stitch_mae=max_stitch_mae)
    progress("safety checks passed")
    return report


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Build a final Cadillac OTA wallpaper zip from two 2198x367 images. "
            "The tool replaces external PNGs and KZB ASTC records, then applies "
            "the v22 transparent-RGB rule for KZB auxiliary layers."
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
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    load_runtime_dependencies()
    work_dir = args.work_dir
    if work_dir is None:
        work_dir = PROJECT_ROOT / "build" / f"{args.output_zip.stem}_work"
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
    )
    report_path = args.report
    if report_path is None:
        report_path = work_dir / "package-report.json"
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2))
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
