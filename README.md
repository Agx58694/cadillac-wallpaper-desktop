# Cadillac Wallpaper Desktop

[中文](README.zh-CN.md) | English

A Flutter desktop packager for two **static day/night** Cadillac OTA wallpaper images. The GUI calls the Python packager for KZB, ASTC, image derivation, package identity, and final ZIP validation. It does not implement those binary rules in Dart.

> Unofficial compatibility tool. It is not affiliated with, endorsed by, or sponsored by General Motors or Cadillac. See [DISCLAIMER.md](DISCLAIMER.md).

For the complete desktop-to-vehicle workflow, see [中文使用说明](docs/usage-zh-CN.md).

## Download

Download the v1.1.0 release assets below. GitHub's automatic source archives are not ready-to-run apps.

| Platform | Asset |
| --- | --- |
| macOS 12+ Apple Silicon / Intel | [CadillacPackager-macos-universal.zip](https://github.com/Agx58694/cadillac-wallpaper-desktop/releases/download/v1.1.0/CadillacPackager-macos-universal.zip) |
| Windows x64 | [CadillacPackager-windows-x64.zip](https://github.com/Agx58694/cadillac-wallpaper-desktop/releases/download/v1.1.0/CadillacPackager-windows-x64.zip) |
| Android 12+ head unit | [wallpaper-studio-0.2.1-test.apk](https://github.com/Agx58694/cadillac-wallpaper-desktop/releases/download/v1.1.0/wallpaper-studio-0.2.1-test.apk) |

These links become available when the v1.1.0 Release is published. See the [v1.1.0 release notes](docs/release-notes-v1.1.0.md) for the scope and validation boundary.

## Create a wallpaper

1. Prepare one daytime and one nighttime PNG with the **same composition and dimensions**.
2. Prefer two opaque **8960×1320** masters. The native split is IPD **5010×1320** on the left and VCD **3950×1320** on the right, joined at x=5010. Keep subjects clear of the vehicle's instrument, card, and toolbar overlays.
3. In the desktop app, select **Standard OTA** for a ZIP or **Theme package** for a `.cwtheme`. Drag in the two PNGs and start packaging.
4. Check that every final-package validation passes. The OTA ZIP and sibling report are saved outside the OTA archive.
5. On an Android 12+ head unit with the compatible installer, import the OTA ZIP or `.cwtheme`, inspect day/night previews, then tap **应用壁纸**. Only a matching system callback confirms application; a timeout means the result is unconfirmed.

The **legacy** input mode continues to accept two 2198×367 preview masters. It derives the native resources from that smaller image, so detail and composition are limited. The app selects the mode from the input dimensions; it rejects mismatched day/night sizes and other dimensions. For native mode, prepare art at the target aspect ratio instead of stretching unrelated images to fit.

This version packages static day/night art. It does not create per-image animations, four-state wallpapers, dynamic right-screen video, weather/time effects, or vehicle FPS measurement.

## Package format and compatibility

The finished OTA ZIP has exactly **nine files** beneath one generated 32-character hexadecimal ID and one `cadi_wallpaper...` folder:

```text
<32-hex-id>/cadi_wallpaper.../
  light_preview_image.png             2198×367
  dark_preview_image.png              2198×367
  light_dim_background.png            3950×1320
  dark_dim_background.png             3950×1320
  vcd/wallpaper/light_wallpaper_vcd.png 3950×1320
  vcd/wallpaper/dark_wallpaper_vcd.png  3950×1320
  rid/screenSaver/light_screenSaver_rid.png 1920×1080
  rid/screenSaver/dark_screenSaver_rid.png  1920×1080
  ipd/wallpaper/<project>.kzb
```

The KZB keeps the audited static football scene structure, masks, and day/night state. Each content version receives independent internal resource identity and matching outer paths. The final validator checks the ZIP, all required images, preserved `rec0`, transparent RGB, KZB references, and IPD/VCD seam. Internal identity rebuilding can legitimately change KZB size and record offsets.

`.cwtheme` uses the same OTA engine. It contains `cwtheme/payload/ota_wallpaper.zip`, a schema v1 manifest, previews, thumbnails, the original two masters, and a report. The master filenames reflect the input dimensions; the manifest's installation paths are derived from the actual OTA ZIP. Existing theme-library entries and older packages remain readable.

The app continues to bundle the repository's existing static football template. The static packaging path accepts only its audited `football-static` resource structure, including compatible external copies; unknown or dynamic templates are rejected. Other official themes are not claimed as supported. The Winter-Star and Alps experimental packages are **not bundled**.

## Build and test

```bash
flutter pub get
flutter analyze
flutter test
PYTHONPATH=packager python3 -m unittest discover -s packager/tests -p 'test_*.py'
```

Install Pillow for Python source execution: `python3 -m pip install Pillow==11.3.0`. A macOS source-only `flutter build macos --release` does **not** bundle the packager runtime. The `desktop-release.yml` workflow builds architecture-specific Python/Pillow runtimes, puts both behind a Universal launcher inside the app, verifies the Flutter executable, launcher, and `astcenc` architecture slices, and uploads a macOS artifact. The Windows workflow bundles a PyInstaller runtime and `astcenc.exe` with the Flutter app. The release workflow runs manually and uploads Actions artifacts; creating a public GitHub Release is a separate publishing step.

For a Windows source build, use `scripts/build_windows_release.ps1` on Windows x64. `scripts/make_windows_build_kit.sh` creates the existing Windows build kit from macOS/Linux. Set `CADILLAC_PACKAGER_CLI` to override a bundled executable, or `CADILLAC_PYTHON` and `CADILLAC_PACKAGER_SCRIPT` for a source Python runtime. `CADILLAC_INPUT_ZIP` and `CADILLAC_ASTCENC` override the bundled template and encoder for compatible local testing.

## Installer status

The compatible Android installer is **壁纸空间** (`com.cadillac.wallpaperstudio`). Its existing `wallpaper-studio-0.2.1-test.apk` accepts OTA ZIP and `.cwtheme`, imports into its library, and can request system application. It is a debug-signed validation APK and includes a built-in sample wallpaper. Earlier app/package combinations received vehicle success feedback, including an A/B/A switch with independent identities; **0.2.1 and arbitrary packages have not been verified on every vehicle or OTA version**. The older `com.cadillac.themeinstaller` app only installs to a fixed football directory and is not the route for new generated identities.

## Community

This project remains open source and free. Cadillac owners can help test vehicle and OTA compatibility, share product feedback, or help with tutorials and videos. Scan the WeChat code to get in touch.

<img src="docs/assets/wechat-contact.png" alt="WeChat contact" width="240">

Good-faith learning, discussion, forks, and contributions are welcome. Copying the open-source work, rebranding it, and selling it for profit is not.

禁止偷电
