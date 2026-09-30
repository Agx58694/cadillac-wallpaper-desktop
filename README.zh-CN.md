# Cadillac Wallpaper Desktop

中文 | [English](README.md)

将两张静态日夜 PNG 打包为 Cadillac 车机壁纸。电脑端生成 OTA ZIP 或 `.cwtheme`，再通过 Android“壁纸空间”导入和应用。

## 下载

| 设备 | 文件 |
| --- | --- |
| macOS 12+（Apple Silicon / Intel） | [桌面程序 ZIP](https://github.com/Agx58694/cadillac-wallpaper-desktop/releases/download/v1.1.0/CadillacPackager-macos-universal.zip) |
| Windows x64 | [桌面程序 ZIP](https://github.com/Agx58694/cadillac-wallpaper-desktop/releases/download/v1.1.0/CadillacPackager-windows-x64.zip) |
| Android 12+ 车机 | [壁纸空间 0.2.1 测试版 APK](https://github.com/Agx58694/cadillac-wallpaper-desktop/releases/download/v1.1.0/wallpaper-studio-0.2.1-test.apk) |

解压桌面程序后运行；车机安装 APK。GitHub 自动生成的 `Source code` 是源码，不是安装包。

## 使用方法

1. 准备白天和黑夜两张同尺寸、同构图的不透明 PNG。推荐 **8960×1320**；左侧 IPD 为 5010×1320，右侧 VCD 为 3950×1320，接缝在 x=5010。也兼容两张 **2198×367** 旧版预览图，但放大后细节较少。
2. 在桌面程序选择“标准 OTA”生成 ZIP，或选择“主题包”生成 `.cwtheme`；导入两张图，开始打包，等待校验通过。
3. 将成品传到车机，在“壁纸空间”中导入并检查日夜预览，然后点“应用壁纸”。收到对应本次壁纸的成功回调才表示应用已确认；超时则先查看车机画面和记录。

详细步骤与常见问题见[中文使用说明](docs/usage-zh-CN.md)。

本版仅支持仓库内置的静态日夜模板。APK 是调试签名验证版，内置示例壁纸；0.2.1 和本版新生成的壁纸尚无本次实车应用结果。此工具与 General Motors、Cadillac 无从属或背书关系，详见[免责声明](DISCLAIMER.md)。
