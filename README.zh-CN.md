# Cadillac Wallpaper Desktop

中文 | [English](README.md)

这是一个 Flutter 桌面程序，用于把两张 `2198x367` PNG 主图打包成 Cadillac 兼容的 OTA 壁纸包。

桌面端不会重新实现 KZB、ASTC、裁剪、alpha 或 dim-mask 规则。两个模式都复用同一个 Python CLI：`packager/cadillac_wallpaper_packager.py`，然后读取 `package-report.json` 并在界面中展示校验结果。

> 这是非官方项目，与 General Motors、Cadillac 或相关商标持有人没有从属、赞助、背书或授权关系。详见 [DISCLAIMER.md](DISCLAIMER.md)。

完整使用说明见 [docs/usage-zh-CN.md](docs/usage-zh-CN.md)。

## 下载

从 [GitHub 最新 Release](https://github.com/Agx58694/cadillac-wallpaper-desktop/releases/latest) 下载桌面程序。

| 系统 | 下载文件 |
| --- | --- |
| macOS Apple Silicon / M 系列 | [CadillacPackager-macos-universal.zip](https://github.com/Agx58694/cadillac-wallpaper-desktop/releases/latest/download/CadillacPackager-macos-universal.zip) |
| macOS Intel | [CadillacPackager-macos-universal.zip](https://github.com/Agx58694/cadillac-wallpaper-desktop/releases/latest/download/CadillacPackager-macos-universal.zip) |
| Windows x64 | [CadillacPackager-windows-x64.zip](https://github.com/Agx58694/cadillac-wallpaper-desktop/releases/latest/download/CadillacPackager-windows-x64.zip) |

请下载上表中的 release assets。Release 页面里的 `Source code` 压缩包是源码包，不是可直接运行的桌面程序。

## 功能

- 标准 OTA 模式：选择白天和黑夜两张 `2198x367` PNG 主图，输出 OTA zip 和对应的 report JSON。
- Android 联动主题包模式：选择白天/黑夜主图并填写主题信息，输出 `.cwtheme`，同时保存到桌面端本地主题库。
- 基于 report 的校验展示：zip 完整性、PNG 尺寸/alpha、preview alpha 是否复用模板、KZB size、KZB record offset、`rec0`、透明 RGB 规则、KZB/VCD 拼接 MAE。
- 支持 macOS 桌面构建，包括 Intel 和 Apple Silicon。
- 支持 Windows x64 桌面构建。
- 支持拖拽导入图片、进度日志、路径脱敏、打包后快速打开输出文件夹。
- 内置足球模板，下载后不需要另行配置模板 zip 即可打包。

> 当前版本只适配足球模板这一款。其他官方主题模板结构不同，后续版本再逐步适配。

## 主题包结构

`.cwtheme` 文件内容如下：

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

## 内置模板和可选覆盖

应用默认内置足球模板：

```text
BFA3A0F4596C4C57A6BCDC1EB3348932 / cadi_wallpaper05111930
```

正常下载 release 后可以直接打包，不需要额外设置模板 zip。

如果你要用自己的兼容模板包，可以通过环境变量覆盖内置模板：

```bash
export CADILLAC_INPUT_ZIP=/path/to/your/template.zip
```

可选覆盖项：

```bash
export CADILLAC_PYTHON=/path/to/python-with-pillow
export CADILLAC_PACKAGER_SCRIPT=/path/to/cadillac_wallpaper_packager.py
export CADILLAC_ASTCENC=/path/to/astcenc-or-astcenc.exe
export CADILLAC_LIGHT_DIM_MASK=/path/to/light_dim_alpha_fixed_smoothed_used.png
export CADILLAC_DARK_DIM_MASK=/path/to/dark_dim_alpha_fixed_smoothed_used.png
```

Windows 下可以在 `cmd.exe` 中使用 `set NAME=value`，或在 PowerShell 中使用 `$env:NAME="value"`。

注意：当前打包规则只适配足球模板。即使使用 `CADILLAC_INPUT_ZIP` 覆盖到其他官方主题模板，本版本也不保证能正确生成。

## 开发验证

```bash
flutter pub get
flutter analyze
flutter test --coverage
```

当前覆盖率目标是 80% 以上行覆盖率。

## macOS 构建

```bash
flutter config --enable-macos-desktop
flutter pub get
flutter analyze
flutter test
flutter build macos --release
```

预期产物路径：

```text
build/macos/Build/Products/Release/cadillac_wallpaper_desktop.app
```

架构验证：

```bash
lipo -info build/macos/Build/Products/Release/cadillac_wallpaper_desktop.app/Contents/MacOS/cadillac_wallpaper_desktop
```

最终 macOS release 应同时包含 `x86_64` 和 `arm64`。

## Windows x64 构建

在 Windows x64 主机上运行：

```powershell
flutter config --enable-windows-desktop
flutter pub get
flutter analyze
flutter test --coverage
flutter build windows --release
```

预期 Windows 产物目录：

```text
build\windows\x64\runner\Release\
```

预期可执行文件：

```text
build\windows\x64\runner\Release\cadillac_wallpaper_desktop.exe
```

Windows 验证命令：

```powershell
Test-Path build\windows\x64\runner\Release\cadillac_wallpaper_desktop.exe
Get-Item build\windows\x64\runner\Release\cadillac_wallpaper_desktop.exe
```

## Windows 一键构建包

在 macOS 或 Linux 上创建 Windows 构建包：

```bash
scripts/make_windows_build_kit.sh
```

把 `dist/CadillacPackager-windows-build-kit.zip` 复制到 Windows x64 机器，解压后右键 `build_windows_one_click.cmd`，选择“以管理员身份运行”。最终 release 包会生成在：

```text
dist\CadillacPackager-windows-x64.zip
```

Windows 构建包会包含当前支持的足球模板。复制到 Windows 机器后，打包出的 app 默认也可以直接使用该内置模板。
