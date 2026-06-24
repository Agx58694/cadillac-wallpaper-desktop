# Cadillac Wallpaper Desktop v1.0.0

首个公开桌面版本，先发布 macOS Universal 打包程序，单个 `.app` 同时支持 Apple Silicon 和 Intel。

## 发行包

- `CadillacPackager-macos-universal.zip`：macOS Apple Silicon / M 系列和 macOS Intel。

Windows x64 版本后续补发。

## 功能

- 标准 OTA 打包：输入白天和黑夜 `2198x367` PNG，输出 OTA zip 和 report。
- Android 联动主题包：输入白天/黑夜主图和主题信息，输出 `.cwtheme` 并保存到本地主题库。
- 共用 `cadillac_wallpaper_packager.py` Python CLI，不重新实现 KZB/ASTC 规则。
- UI 读取 report 并展示 zip、PNG、preview alpha、KZB size、record offset、`rec0`、透明 RGB、KZB/VCD 拼接 MAE 等校验。
- 支持拖拽图片、进度日志、路径脱敏、打包完成后打开输出文件夹。
- 内置当前支持的足球模板。

## 使用说明

完整中文使用说明见：

https://github.com/Agx58694/cadillac-wallpaper-desktop/blob/v1.0.0/docs/usage-zh-CN.md

当前版本只适配足球模板这一款。其他官方主题模板结构不同，后续版本再逐步适配。
