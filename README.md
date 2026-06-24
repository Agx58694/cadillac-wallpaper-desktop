# Cadillac Wallpaper Desktop

[中文](README.zh-CN.md) | English

Flutter desktop app for building Cadillac-compatible OTA wallpaper packages from two `2198x367` PNG masters.

The desktop UI does not reimplement KZB, ASTC, crop, alpha, or dim-mask rules. Both modes call the same Python CLI, `packager/cadillac_wallpaper_packager.py`, then read `package-report.json` and display the validation checks in the app.

> This is an unofficial project. It is not affiliated with, endorsed by, or sponsored by General Motors or Cadillac. See [DISCLAIMER.md](DISCLAIMER.md).

Chinese usage guide: [docs/usage-zh-CN.md](docs/usage-zh-CN.md).

## Features

- Standard OTA mode: select light and dark `2198x367` PNG masters, then output an OTA zip and a sibling report JSON.
- Android-linked theme mode: select light/dark masters plus theme metadata, then output a `.cwtheme` package and save it in the local desktop theme library.
- Report-driven validation UI for zip integrity, PNG size/alpha, preview alpha reuse, KZB size/record offsets, `rec0`, transparent RGB rules, and KZB/VCD stitch MAE.
- macOS desktop support for Intel and Apple Silicon builds.
- Windows x64 desktop support.
- Drag-and-drop image import, progress logs, path redaction, and quick open-output-folder actions.
- Bundled football template, so release downloads can build packages without configuring a separate template zip.

> The current release only supports the football template. Other official template shapes differ and will be supported in later updates.

## Theme Package Format

`.cwtheme` files contain:

```text
cwtheme/
  manifest.json
  previews/light_preview_2198x367.png
  previews/dark_preview_2198x367.png
  previews/thumbnail_light.png
  previews/thumbnail_dark.png
  masters/light_master_2198x367.png
  masters/dark_master_2198x367.png
  payload/ota_wallpaper.zip
  report/package-report.json
```

## Bundled Template And Optional Override

The app bundles the football template by default:

```text
BFA3A0F4596C4C57A6BCDC1EB3348932 / cadi_wallpaper05111930
```

Release downloads can build packages directly without setting a template zip.

To test with your own compatible template package, override the bundled template at runtime:

```bash
export CADILLAC_INPUT_ZIP=/path/to/your/template.zip
```

Optional overrides:

```bash
export CADILLAC_PYTHON=/path/to/python-with-pillow
export CADILLAC_PACKAGER_SCRIPT=/path/to/cadillac_wallpaper_packager.py
export CADILLAC_ASTCENC=/path/to/astcenc-or-astcenc.exe
export CADILLAC_LIGHT_DIM_MASK=/path/to/light_dim_alpha_fixed_smoothed_used.png
export CADILLAC_DARK_DIM_MASK=/path/to/dark_dim_alpha_fixed_smoothed_used.png
```

On Windows use `set NAME=value` in `cmd.exe` or `$env:NAME="value"` in PowerShell.

The current packaging rules only support the football template. Overriding `CADILLAC_INPUT_ZIP` with another official theme is not guaranteed to work in this release.

## Development

```bash
flutter pub get
flutter analyze
flutter test --coverage
```

Current coverage target is 80%+ line coverage.

## macOS Build

```bash
flutter config --enable-macos-desktop
flutter pub get
flutter analyze
flutter test
flutter build macos --release
```

Expected release app path:

```text
build/macos/Build/Products/Release/cadillac_wallpaper_desktop.app
```

Architecture verification:

```bash
lipo -info build/macos/Build/Products/Release/cadillac_wallpaper_desktop.app/Contents/MacOS/cadillac_wallpaper_desktop
```

The final macOS release must report both `x86_64` and `arm64`.

## Windows x64 Build

Run on a Windows x64 host with Flutter desktop enabled:

```powershell
flutter config --enable-windows-desktop
flutter pub get
flutter analyze
flutter test --coverage
flutter build windows --release
```

Expected Windows artifact directory:

```text
build\windows\x64\runner\Release\
```

Expected executable:

```text
build\windows\x64\runner\Release\cadillac_wallpaper_desktop.exe
```

Windows verification:

```powershell
Test-Path build\windows\x64\runner\Release\cadillac_wallpaper_desktop.exe
Get-Item build\windows\x64\runner\Release\cadillac_wallpaper_desktop.exe
```

## Windows One-Click Build Kit

From macOS or Linux, create a Windows build kit zip:

```bash
scripts/make_windows_build_kit.sh
```

Copy `dist/CadillacPackager-windows-build-kit.zip` to a Windows x64 machine, extract it, then right-click `build_windows_one_click.cmd` and choose "Run as administrator". The generated release package will be:

```text
dist\CadillacPackager-windows-x64.zip
```

The Windows build kit includes the currently supported football template. After copying it to a Windows machine, the packaged app can use the bundled template by default.
