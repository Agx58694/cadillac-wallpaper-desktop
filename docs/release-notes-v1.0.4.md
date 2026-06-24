# Cadillac Wallpaper Desktop v1.0.4

此版本开始在 GitHub Actions 同时发布 macOS 和 Windows 桌面包。

## 发行包

- `CadillacPackager-macos-universal.zip`：macOS Apple Silicon / M 系列和 macOS Intel。
- `CadillacPackager-windows-x64.zip`：Windows x64。

## 变化

- GitHub release workflow 增加 Windows x64 构建产物。
- Windows x64 release 包内置独立 `cadillac_wallpaper_packager.exe`，正常使用不再依赖用户本机 Python/Pillow。
- Windows x64 release 校验会确认主程序、独立打包 Runtime、`astcenc.exe` 和足球模板 zip 都已进入产物。
- macOS release 继续使用 Universal `.app`，同时支持 `x86_64` 和 `arm64`。

## 当前限制

当前只适配足球模板这一款：

```text
BFA3A0F4596C4C57A6BCDC1EB3348932 / cadi_wallpaper05111930
```

其他官方主题模板结构不同，后续版本再逐步适配。

## 使用说明

完整中文使用说明见：

https://github.com/Agx58694/cadillac-wallpaper-desktop/blob/v1.0.4/docs/usage-zh-CN.md
