# Cadillac Wallpaper Desktop

中文 | [English](README.md)

这是一个将**两张静态日夜 PNG**打包为 Cadillac 兼容 OTA 壁纸的 Flutter 桌面程序。界面统一调用 Python 打包核心处理 KZB、ASTC、图片派生、独立身份和最终 ZIP 校验，不在 Dart 中另写二进制规则。

> 这是非官方兼容工具，与 General Motors、Cadillac 或相关商标持有人没有从属、赞助、背书或授权关系。详见 [免责声明](DISCLAIMER.md)。

从电脑制图到车机导入、应用的步骤见 [完整中文使用说明](docs/usage-zh-CN.md)。

## 下载

下载下方 v1.1.0 对应的附件。GitHub 自动生成的 `Source code` 是源码，不能直接当作应用运行。

| 系统 | 文件 |
| --- | --- |
| macOS 12+ Apple Silicon / Intel | [CadillacPackager-macos-universal.zip](https://github.com/Agx58694/cadillac-wallpaper-desktop/releases/download/v1.1.0/CadillacPackager-macos-universal.zip) |
| Windows x64 | [CadillacPackager-windows-x64.zip](https://github.com/Agx58694/cadillac-wallpaper-desktop/releases/download/v1.1.0/CadillacPackager-windows-x64.zip) |
| Android 12+ 车机 | [wallpaper-studio-0.2.1-test.apk](https://github.com/Agx58694/cadillac-wallpaper-desktop/releases/download/v1.1.0/wallpaper-studio-0.2.1-test.apk) |

上述链接在 v1.1.0 Release 发布后生效。版本范围和验收边界见 [v1.1.0 发布说明](docs/release-notes-v1.1.0.md)。

## 两张图如何打包

1. 准备白天和黑夜两张**同尺寸、同构图**的 PNG。
2. 推荐两张不透明的 **8960×1320** 原生母图：左侧 IPD **5010×1320**，右侧 VCD **3950×1320**，接缝 x=5010。主体需避开实际车机的仪表、卡片和工具栏遮挡区域。
3. 在程序中选“标准 OTA”输出 ZIP，或选“主题包”输出 `.cwtheme`，导入两张图并开始打包。
4. 查看最终成品的全部校验结果；报告放在 OTA ZIP 之外。
5. 在兼容的 Android 12+ 车机安装器中导入 ZIP 或 `.cwtheme`，查看日夜预览，再点“应用壁纸”。只有系统返回本次对应的成功回调才表示应用成功；超时表示结果尚未确认。

**旧版预览兼容模式**仍接受两张 2198×367 图，但会从低分辨率素材派生原生资源，细节和构图范围受限。程序按图片尺寸识别模式，拒绝日夜尺寸不一致或其他尺寸。原生模式不会把不相关比例的图非等比拉伸到车机画布。

本次只做静态日夜壁纸打包；不自动生成雪花、落叶等专属动效，不提供四态壁纸、右屏视频、天气/时间效果或车机壁纸 FPS 测量。

## 成品格式

最终 OTA ZIP 在一个新生成的 32 位十六进制 ID 和一个 `cadi_wallpaper...` 文件夹下，严格包含 **9 个文件**：

```text
<32位十六进制ID>/cadi_wallpaper.../
  light_preview_image.png             2198×367
  dark_preview_image.png              2198×367
  light_dim_background.png            3950×1320
  dark_dim_background.png             3950×1320
  vcd/wallpaper/light_wallpaper_vcd.png 3950×1320
  vcd/wallpaper/dark_wallpaper_vcd.png  3950×1320
  rid/screenSaver/light_screenSaver_rid.png 1920×1080
  rid/screenSaver/dark_screenSaver_rid.png  1920×1080
  ipd/wallpaper/<项目身份>.kzb
```

KZB 保留已审计的静态足球场景、遮罩和原日夜状态。每个内容版本生成独立的内部资源身份和相应的外层路径。最终校验覆盖 ZIP、8 张 PNG、`rec0`、透明区 RGB、KZB 引用与左右接缝。合法的变长身份重建会改变 KZB 大小和记录偏移，不将“偏移永远不变”当作新版通过条件。

`.cwtheme` 复用同一个 OTA 引擎，内含 `cwtheme/payload/ota_wallpaper.zip`、schema v1 清单、预览、缩略图、原始两张母图与报告。母图文件名由真实输入尺寸决定，清单里的安装路径来自成品 ZIP；旧主题库和旧包继续可读。

程序继续沿用仓库已有的静态足球模板。静态打包入口只接受经审计的 `football-static` 资源结构及其兼容外部副本；未知或动态模板会被拒绝。目前不宣称适配其他官方主题。Winter-Star 和 Alps 实验包**没有内置**。

## 开发和分发验证

```bash
flutter pub get
flutter analyze
flutter test
PYTHONPATH=packager python3 -m unittest discover -s packager/tests -p 'test_*.py'
```

源码运行 Python 核心时可安装 `Pillow==11.3.0`。单独运行 `flutter build macos --release` 只会生成 Flutter app，**不会**自动加入 Python 打包 runtime。现有 `desktop-release.yml` 工作流分别构建 x86_64、arm64 Python/Pillow CLI，并通过 Universal 启动器放入同一个 macOS app；同时检查 Flutter 主程序、启动器和 `astcenc` 的架构。Windows 工作流将 PyInstaller CLI、`astcenc.exe` 与 Flutter 程序一起打包。工作流通过手动触发，产物在 Actions 中；正式 GitHub Release 需要单独发布。

Windows x64 源码打包使用 `scripts/build_windows_release.ps1`。可在 macOS/Linux 用 `scripts/make_windows_build_kit.sh` 制作现有 Windows 构建包。需要测试本地兼容模板或工具时，可设置 `CADILLAC_INPUT_ZIP`、`CADILLAC_ASTCENC`；`CADILLAC_PACKAGER_CLI` 可覆盖内置打包可执行文件，`CADILLAC_PYTHON` 与 `CADILLAC_PACKAGER_SCRIPT` 用于源码 Python 运行方式。

## 安装器现状

与新独立身份包配套的是“壁纸空间”（`com.cadillac.wallpaperstudio`）。现有 `wallpaper-studio-0.2.1-test.apk` 能导入 OTA ZIP 和 `.cwtheme`，保存到壁纸库，并请求系统应用。它是调试签名的验证版 APK，内含一张示例壁纸。更早的应用与独立身份对照包有实车应用、A/B/A 左右屏即时切换反馈；**0.2.1 本身及任意新包还没有覆盖所有车型和 OTA 版本的实车验证**。旧 `com.cadillac.themeinstaller` 固定写入足球目录，不适合新独立身份包。

## 一起完善

这个项目会继续围绕 Cadillac 车机壁纸做开源、免费的工具。欢迎车友测试不同车型和 OTA 版本、提出体验建议，或帮忙制作教程、帖子和视频。扫码联系：

<img src="docs/assets/wechat-contact.png" alt="微信联系方式" width="240">

欢迎基于开源精神学习、交流、二次开发和提交改进；抵制抄袭、换壳后拿去盈利。这个系列坚持开源免费。

禁止偷电
