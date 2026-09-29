# v1.1.0：两张静态日夜图打包与车机导入

本版将两张静态白天、黑夜 PNG 打包为 9 文件 OTA 壁纸 ZIP，也可输出含同一 OTA 成品的 `.cwtheme`。仅适配仓库既有的静态足球模板结构；动态模板、四态和视频壁纸不在本版范围内。

- **原生模式**：两张 8960×1320 PNG，保留左侧 5010×1320 IPD、右侧 3950×1320 VCD 的原生画布与 x=5010 接缝。
- **旧预览兼容模式**：仍接受两张 2198×367 PNG，生成车机所需尺寸；放大不能恢复原图缺失的细节。
- **独立身份**：每个内容版本生成对应的外层目录和 KZB 内部资源身份；相同内容及主题标识重复打包时保持稳定。成品附有校验报告。

下载附件：

| 设备 | Release 附件 |
| --- | --- |
| macOS 12+，Apple Silicon / Intel | `CadillacPackager-macos-universal.zip` |
| Windows x64 | `CadillacPackager-windows-x64.zip` |
| Android 12+ 车机 | `wallpaper-studio-0.2.1-test.apk` |

macOS 包含双架构桌面程序、Python/Pillow 打包运行时和 `astcenc`；Windows x64 包含独立打包运行时。Android“壁纸空间”0.2.1（包名 `com.cadillac.wallpaperstudio`）可导入 OTA ZIP 或 `.cwtheme`，检查日夜预览后请求应用。该 APK 为**调试签名验证版**，内置“雨夜球场 V12”示例；SHA-256：`421ca622556a6dad41413a3b449545063706ed7135738b30f3f791155499279d`。

安装器导入流程已有本地/模拟器检查；此前版本与独立身份对照包有实车 A/B/A 左右屏切换反馈。**0.2.1 与本版新生成的壁纸尚无本次实车应用结果，也未验证所有车型和 OTA 版本**。只有车机返回与本次壁纸身份匹配的成功回调，才表示应用已确认；超时应视为待确认。操作步骤见[中文使用说明](usage-zh-CN.md)。
