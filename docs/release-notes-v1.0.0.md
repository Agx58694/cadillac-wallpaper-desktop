# Cadillac Wallpaper Desktop v1.0.0

首个公开桌面版本，提供 macOS 和 Windows 桌面打包程序。

## 发行包

- `CadillacPackager-windows-x64.zip`：Windows x64。
- `CadillacPackager-macos-arm64.zip`：macOS Apple Silicon / M 系列。
- `CadillacPackager-macos-x64.zip`：macOS Intel。

## 功能

- 标准 OTA 打包：输入白天和黑夜 `2198x367` PNG，输出 OTA zip 和 report。
- Android 联动主题包：输入白天/黑夜主图和主题信息，输出 `.cwtheme` 并保存到本地主题库。
- 共用 `cadillac_wallpaper_packager.py` Python CLI，不重新实现 KZB/ASTC 规则。
- UI 读取 report 并展示 zip、PNG、preview alpha、KZB size、record offset、`rec0`、透明 RGB、KZB/VCD 拼接 MAE 等校验。
- 支持拖拽图片、进度日志、路径脱敏、打包完成后打开输出文件夹。

## 使用说明

完整中文使用说明见：

https://github.com/Agx58694/cadillac-wallpaper-desktop/blob/v1.0.0/docs/usage-zh-CN.md

公开发行包不会内置 OEM OTA 模板 zip。运行前需要提供兼容模板，并通过 `CADILLAC_INPUT_ZIP` 指定。
