# Cadillac Wallpaper Desktop

[中文](README.zh-CN.md) | English

Package two static day/night PNGs as a Cadillac compatible wallpaper. The desktop app creates an OTA ZIP or `.cwtheme`; the Android “壁纸空间” app imports and requests application on the head unit.

## Download

| Device | File |
| --- | --- |
| macOS 12+ (Apple Silicon / Intel) | [Desktop ZIP](https://github.com/Agx58694/cadillac-wallpaper-desktop/releases/download/v1.1.0/CadillacPackager-macos-universal.zip) |
| Windows x64 | [Desktop ZIP](https://github.com/Agx58694/cadillac-wallpaper-desktop/releases/download/v1.1.0/CadillacPackager-windows-x64.zip) |
| Android 12+ head unit | [壁纸空间 0.2.1 test APK](https://github.com/Agx58694/cadillac-wallpaper-desktop/releases/download/v1.1.0/wallpaper-studio-0.2.1-test.apk) |

Unzip and run the desktop app, then install the APK on the head unit. GitHub's automatic `Source code` archives are not installers.

## Use

1. Prepare opaque day and night PNGs with matching dimensions and composition. **8960×1320** is recommended: IPD occupies the left 5010×1320, VCD the right 3950×1320, with the join at x=5010. Two **2198×367** legacy preview images also work, with reduced detail after enlargement.
2. In the desktop app, choose **标准 OTA** for a ZIP or **主题包** for a `.cwtheme`. Add both images, start packaging, and wait for the checks to pass.
3. Transfer the result to the head unit. Import it in “壁纸空间”, inspect the day/night previews, and tap **应用壁纸**. A matching success callback confirms application; after a timeout, check the vehicle display and app record.

See the [Chinese usage guide](docs/usage-zh-CN.md) for detailed steps and troubleshooting.

This version supports only the bundled static day/night template. The APK is a debug-signed validation build with a sample wallpaper; version 0.2.1 and newly generated wallpapers have no real-vehicle application result from this release. This tool is not affiliated with or endorsed by General Motors or Cadillac; see the [disclaimer](DISCLAIMER.md).
